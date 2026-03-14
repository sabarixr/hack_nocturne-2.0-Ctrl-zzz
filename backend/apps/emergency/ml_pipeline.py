"""
Server-side ML pipeline using MediaPipe.

Processes a raw JPEG/PNG frame (as base64 or bytes) and returns:
  - recognized_signs: list[str]   — detected ASL signs
  - sign_confidence: float        — top sign confidence
  - hand_detected: bool
  - face_detected: bool
  - emotion_angry: float          — 7-class emotion probabilities
  - emotion_sad: float
  - emotion_neutral: float
  - emotion_happy: float
  - emotion_surprise: float
  - emotion_afraid: float
  - emotion_disgust: float
  - signing_speed: float
  - tremor_level: float

Architecture:
  - MediaPipe Hands → 21 landmarks per hand → fed into TFLite sign classifier
    (or heuristic fallback when BYPASS_MODEL=True)
  - MediaPipe Face Mesh → 478 landmarks → geometric emotion features
    (rule-based; no separate TFLite model required)

Thread-safety: the module-level detector instances are created once (lazy)
and reused.  Call process_frame() from any async context via
asyncio.get_event_loop().run_in_executor().
"""

from __future__ import annotations

import base64
import collections
import math
import threading
from typing import Any

import cv2
import numpy as np

# ---------------------------------------------------------------------------
# Lazy-initialised MediaPipe objects (created once per process)
# ---------------------------------------------------------------------------

_lock = threading.Lock()
_mp_hands = None
_mp_face_mesh = None
_hands_detector = None
_face_mesh_detector = None


def _ensure_detectors() -> None:
    global _mp_hands, _mp_face_mesh, _hands_detector, _face_mesh_detector
    if _hands_detector is not None:
        return
    with _lock:
        if _hands_detector is not None:
            return
        import mediapipe as mp  # noqa: PLC0415

        _mp_hands = mp.solutions.hands
        _mp_face_mesh = mp.solutions.face_mesh
        _hands_detector = _mp_hands.Hands(
            static_image_mode=True,
            max_num_hands=2,
            min_detection_confidence=0.5,
        )
        _face_mesh_detector = _mp_face_mesh.FaceMesh(
            static_image_mode=True,
            max_num_faces=1,
            refine_landmarks=True,
            min_detection_confidence=0.5,
        )


# ---------------------------------------------------------------------------
# Sign classifier label set (must match TFLite model output order)
# ---------------------------------------------------------------------------

SIGN_LABELS = [
    "accident",
    "call",
    "doctor",
    "help",
    "hot",
    "lose",
    "pain",
    "thief",
]

# ---------------------------------------------------------------------------
# Sliding-window state per call (keyed by call_id)
# ---------------------------------------------------------------------------

# For each call we keep a short deque of (wrist_x, wrist_y) positions to
# compute signing_speed and tremor_level across successive frames.
_wrist_history: dict[str, collections.deque] = {}
_WRIST_HISTORY_LEN = 20


def _wrist_deque(call_id: str) -> collections.deque:
    if call_id not in _wrist_history:
        _wrist_history[call_id] = collections.deque(maxlen=_WRIST_HISTORY_LEN)
    return _wrist_history[call_id]


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------


def process_frame(frame_b64: str, call_id: str = "") -> dict[str, Any]:
    """
    Decode a base64-encoded JPEG/PNG frame, run MediaPipe, return results.

    Always returns a complete dict — never raises.
    """
    try:
        _ensure_detectors()
        img_bytes = base64.b64decode(frame_b64)
        arr = np.frombuffer(img_bytes, dtype=np.uint8)
        bgr = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if bgr is None:
            return _empty_result()
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        return _run_pipeline(rgb, call_id)
    except Exception as exc:  # noqa: BLE001
        import traceback

        traceback.print_exc()
        print(f"[ml_pipeline] process_frame error: {exc}")
        return _empty_result()


# ---------------------------------------------------------------------------
# Internal pipeline
# ---------------------------------------------------------------------------


def _run_pipeline(rgb: np.ndarray, call_id: str) -> dict[str, Any]:
    hand_result = _detect_hands(rgb, call_id)
    face_result = _detect_face(rgb)
    return {**hand_result, **face_result}


# ---------------------------------------------------------------------------
# Hand detection + sign classification
# ---------------------------------------------------------------------------


def _detect_hands(rgb: np.ndarray, call_id: str) -> dict[str, Any]:
    result = _hands_detector.process(rgb)  # type: ignore[union-attr]

    if not result.multi_hand_landmarks:
        return {
            "hand_detected": False,
            "recognized_signs": [],
            "sign_confidence": 0.0,
            "signing_speed": 0.0,
            "tremor_level": 0.0,
        }

    # Use the first detected hand
    hand_lm = result.multi_hand_landmarks[0]
    h, w = rgb.shape[:2]

    # Build 63-dim feature vector: 21 landmarks × (x, y, z)
    landmarks = np.array(
        [[lm.x, lm.y, lm.z] for lm in hand_lm.landmark], dtype=np.float32
    )  # (21, 3)

    # Wrist-centred normalisation
    wrist = landmarks[0].copy()
    landmarks -= wrist
    scale = np.linalg.norm(landmarks, axis=1).max()
    if scale > 1e-6:
        landmarks /= scale

    # Track wrist for speed/tremor
    wrist_px = (wrist[0] * w, wrist[1] * h)
    dq = _wrist_deque(call_id)
    dq.append(wrist_px)
    signing_speed, tremor_level = _compute_motion(dq)

    # Classify sign
    flat = landmarks.flatten()  # (63,)
    signs, confidence = _classify_sign(flat)

    return {
        "hand_detected": True,
        "recognized_signs": signs,
        "sign_confidence": float(confidence),
        "signing_speed": float(signing_speed),
        "tremor_level": float(tremor_level),
    }


def _classify_sign(flat63: np.ndarray) -> tuple[list[str], float]:
    """
    Classify the 63-dim hand landmark vector.

    If BYPASS_MODEL=True or TFLite unavailable, falls back to a
    geometry-based heuristic that covers the 8 sign classes.
    """
    from django.conf import settings  # noqa: PLC0415

    if not settings.BYPASS_MODEL:
        try:
            return _tflite_classify(flat63)
        except Exception:  # noqa: BLE001
            pass

    return _heuristic_classify(flat63)


def _tflite_classify(flat63: np.ndarray) -> tuple[list[str], float]:
    """Run the bundled TFLite sign classifier (single frame, 63 features)."""
    from django.conf import settings  # noqa: PLC0415

    import tflite_runtime.interpreter as tflite  # noqa: PLC0415

    interp = tflite.Interpreter(model_path=settings.TFLITE_MODEL_PATH)
    interp.allocate_tensors()
    inp = interp.get_input_details()
    out = interp.get_output_details()
    inp_shape = inp[0]["shape"]
    data = flat63.reshape(inp_shape).astype(np.float32)
    interp.set_tensor(inp[0]["index"], data)
    interp.invoke()
    probs = interp.get_tensor(out[0]["index"])[0]
    idx = int(probs.argmax())
    conf = float(probs[idx])
    label = SIGN_LABELS[idx] if idx < len(SIGN_LABELS) else "unknown"
    signs = [label] if conf >= 0.45 else []
    return signs, conf


def _heuristic_classify(flat63: np.ndarray) -> tuple[list[str], float]:
    """
    Rule-based sign detector from 21 wrist-normalised hand landmarks.

    Landmarks (MediaPipe ordering):
      0: wrist
      1-4: thumb (CMC→tip)
      5-8: index (MCP→tip)
      9-12: middle (MCP→tip)
      13-16: ring (MCP→tip)
      17-20: pinky (MCP→tip)
    """
    lm = flat63.reshape(21, 3)

    def tip(finger: int) -> np.ndarray:
        # finger 0=thumb,1=index,2=middle,3=ring,4=pinky
        tips = [4, 8, 12, 16, 20]
        return lm[tips[finger]]

    def mcp(finger: int) -> np.ndarray:
        mcps = [2, 5, 9, 13, 17]
        return lm[mcps[finger]]

    def pip(finger: int) -> np.ndarray:
        pips = [3, 6, 10, 14, 18]
        return lm[pips[finger]]

    # Is finger extended? (tip y < pip y in normalised space where up = negative y)
    def extended(finger: int) -> bool:
        return float(tip(finger)[1]) < float(pip(finger)[1])

    def dist(a: np.ndarray, b: np.ndarray) -> float:
        return float(np.linalg.norm(a - b))

    thumb_ext = float(tip(0)[0]) > float(mcp(0)[0])  # thumb out to side
    idx_ext = extended(1)
    mid_ext = extended(2)
    rng_ext = extended(3)
    pnk_ext = extended(4)

    num_extended = sum([idx_ext, mid_ext, rng_ext, pnk_ext])

    # ── HELP: open palm (all 4 fingers + thumb extended) ────────────────────
    if thumb_ext and num_extended == 4:
        return ["help"], 0.82

    # ── CALL: pinky + thumb extended, rest curled (shaka) ───────────────────
    if thumb_ext and pnk_ext and not idx_ext and not mid_ext and not rng_ext:
        return ["call"], 0.80

    # ── PAIN: index + middle together, bent (touching chest gesture proxy) ──
    if idx_ext and mid_ext and not rng_ext and not pnk_ext:
        finger_gap = dist(tip(1), tip(2))
        if finger_gap < 0.15:
            return ["pain"], 0.72

    # ── DOCTOR: D-hand: index up, thumb + middle touch, rest curled ─────────
    if idx_ext and not mid_ext and not rng_ext and not pnk_ext:
        thumb_mid_gap = dist(tip(0), tip(2))
        if thumb_mid_gap < 0.20:
            return ["doctor"], 0.70

    # ── THIEF: F-hand + movement cue (best static proxy: O-shape) ───────────
    # O-shape: all fingertips close to thumb tip
    avg_gap = np.mean([dist(tip(0), tip(i)) for i in range(1, 5)])
    if avg_gap < 0.18:
        return ["thief"], 0.65

    # ── ACCIDENT: index + pinky extended (ILY / devil horns) ────────────────
    if idx_ext and pnk_ext and not mid_ext and not rng_ext:
        return ["accident"], 0.68

    # ── HOT: curved hand palm down (all curled, wrist forward) ──────────────
    if num_extended == 0 and not thumb_ext:
        # fully fisted hand — map to "hot" (arbitrary but plausible)
        return ["hot"], 0.60

    # ── LOSE: open + then close — static proxy: relaxed spread ──────────────
    # (when nothing else matches + some fingers out)
    if num_extended >= 2:
        return ["lose"], 0.52

    return [], 0.0


# ---------------------------------------------------------------------------
# Motion metrics
# ---------------------------------------------------------------------------


def _compute_motion(
    dq: collections.deque,
) -> tuple[float, float]:
    """Return (signing_speed, tremor_level) from wrist position history."""
    pts = list(dq)
    if len(pts) < 2:
        return 0.0, 0.0
    deltas = [
        math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1])
        for i in range(1, len(pts))
    ]
    speed = float(np.mean(deltas))
    tremor = float(np.std(deltas))
    return speed / 100.0, tremor / 100.0  # normalise to ~[0,1] range


# ---------------------------------------------------------------------------
# Face detection + geometric emotion estimation
# ---------------------------------------------------------------------------


def _detect_face(rgb: np.ndarray) -> dict[str, Any]:
    result = _face_mesh_detector.process(rgb)  # type: ignore[union-attr]

    if not result.multi_face_landmarks:
        return {
            "face_detected": False,
            "emotion_neutral": 1.0,
            "emotion_happy": 0.0,
            "emotion_sad": 0.0,
            "emotion_surprise": 0.0,
            "emotion_afraid": 0.0,
            "emotion_disgust": 0.0,
            "emotion_angry": 0.0,
        }

    lm = result.multi_face_landmarks[0].landmark  # 478 landmarks
    pts = np.array([[p.x, p.y, p.z] for p in lm], dtype=np.float32)

    scores = _geometric_emotion_scores(pts)
    return {"face_detected": True, **scores}


def _dist_pts(pts: np.ndarray, a: int, b: int) -> float:
    return float(np.linalg.norm(pts[a] - pts[b]))


def _geometric_emotion_scores(pts: np.ndarray) -> dict[str, float]:
    """
    Estimate 7-class emotion probabilities from MediaPipe 478-point face mesh
    using geometric ratios (brow raise, eye openness, mouth shape, etc.).

    Returns a dict with keys: neutral, happy, sad, surprise, afraid, disgust, angry.
    Values are softmax-normalised probabilities summing to 1.
    """
    # ── Distances ─────────────────────────────────────────────────────────
    face_width = _dist_pts(pts, 234, 454)
    if face_width < 1e-6:
        face_width = 1.0

    # Eye openness (vertical / horizontal ratio)
    l_eye_h = _dist_pts(pts, 159, 145)
    l_eye_w = _dist_pts(pts, 33, 133)
    r_eye_h = _dist_pts(pts, 386, 374)
    r_eye_w = _dist_pts(pts, 362, 263)
    l_eye_open = l_eye_h / max(l_eye_w, 1e-6)
    r_eye_open = r_eye_h / max(r_eye_w, 1e-6)
    eye_open = (l_eye_open + r_eye_open) / 2.0  # ~0.3 closed, ~0.5 normal, >0.7 wide

    # Brow raise (brow tip y - eye corner y, negative = raised in image coords)
    l_brow_raise = (pts[159][1] - pts[70][1]) / face_width   # positive when raised
    r_brow_raise = (pts[386][1] - pts[300][1]) / face_width
    brow_raise = (l_brow_raise + r_brow_raise) / 2.0

    # Brow furrow: distance between inner brow corners (closer = furrowed)
    brow_gap = _dist_pts(pts, 55, 285) / face_width  # ~0.3 furrowed, ~0.5 neutral

    # Mouth openness
    mouth_h = _dist_pts(pts, 13, 14)
    mouth_w = _dist_pts(pts, 61, 291)
    mouth_open = mouth_h / max(mouth_w, 1e-6)  # ~0 closed, ~0.5 open

    # Lip corners up/down (smile vs frown)
    # 61 = left corner, 291 = right corner, 14 = lower lip center
    lip_corner_avg_y = (pts[61][1] + pts[291][1]) / 2.0
    lip_center_y = pts[14][1]
    smile = lip_center_y - lip_corner_avg_y  # positive = corners higher = smile

    # Nose wrinkle (disgust proxy): distance between nose bridge and upper lip
    nose_lip_dist = _dist_pts(pts, 4, 0) / face_width

    # ── Rule-based score computation ──────────────────────────────────────

    # happy: smile + moderate eye openness
    happy = float(np.clip(smile * 8.0 + eye_open * 0.5, 0, 1))

    # sad: drooping lip corners + furrowed brows
    sad_smile = float(np.clip(-smile * 6.0, 0, 1))
    sad_brow = float(np.clip(0.35 - brow_gap, 0, 1) * 2.0)
    sad = float(np.clip((sad_smile + sad_brow) / 2.0, 0, 1))

    # surprise: wide eyes + raised brows + open mouth
    surprise = float(np.clip(
        (eye_open - 0.45) * 4.0
        + brow_raise * 5.0
        + mouth_open * 2.0,
        0, 1,
    ))

    # afraid: wide eyes + raised brows + mouth open (similar to surprise but weaker smile)
    afraid = float(np.clip(
        (eye_open - 0.40) * 3.0
        + brow_raise * 4.0
        + mouth_open * 1.5
        - happy * 0.5,
        0, 1,
    ))

    # disgust: nose wrinkle (shorter nose-lip distance) + lip curl
    disgust = float(np.clip(
        (0.25 - nose_lip_dist) * 6.0 + mouth_open * 0.5,
        0, 1,
    ))

    # angry: furrowed brows + low brow raise + squinted eyes
    angry = float(np.clip(
        (0.35 - brow_gap) * 5.0
        + (0.3 - brow_raise) * 3.0
        + (0.4 - eye_open) * 2.0,
        0, 1,
    ))

    # neutral: inverse of all others
    activated = happy + sad + surprise + afraid + disgust + angry
    neutral = float(np.clip(1.0 - activated * 0.4, 0.0, 1.0))

    # Softmax normalisation
    raw = np.array([neutral, happy, sad, surprise, afraid, disgust, angry], dtype=np.float64)
    raw = np.clip(raw, 0.0, None)
    total = raw.sum()
    if total < 1e-9:
        raw = np.ones(7) / 7.0
    else:
        raw /= total

    return {
        "emotion_neutral": float(raw[0]),
        "emotion_happy": float(raw[1]),
        "emotion_sad": float(raw[2]),
        "emotion_surprise": float(raw[3]),
        "emotion_afraid": float(raw[4]),
        "emotion_disgust": float(raw[5]),
        "emotion_angry": float(raw[6]),
    }


# ---------------------------------------------------------------------------
# Empty result fallback
# ---------------------------------------------------------------------------


def _empty_result() -> dict[str, Any]:
    return {
        "hand_detected": False,
        "recognized_signs": [],
        "sign_confidence": 0.0,
        "signing_speed": 0.0,
        "tremor_level": 0.0,
        "face_detected": False,
        "emotion_neutral": 1.0,
        "emotion_happy": 0.0,
        "emotion_sad": 0.0,
        "emotion_surprise": 0.0,
        "emotion_afraid": 0.0,
        "emotion_disgust": 0.0,
        "emotion_angry": 0.0,
    }
