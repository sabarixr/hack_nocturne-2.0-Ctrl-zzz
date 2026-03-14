"""
MediaPipe hand landmark extraction from (augmented) video dataset.

Uses the MediaPipe Tasks API (HandLandmarker) — NOT mp.solutions —
because mp.solutions is removed in Python 3.13+.

Pipeline:
  1. For each video, run HandLandmarker in VIDEO mode on every frame
  2. Extract 21 landmarks x 3 coords x 2 hands = 126 features per frame
  3. Zero-pad missing hands (if only one detected or none)
  4. Normalize per hand: wrist-centered + scale by max pairwise distance
  5. Interpolate missing frames (linear) if gaps exist
  6. Resample all videos to exactly TARGET_SEQ_LEN (30) frames
  7. Skip videos with < MIN_DETECTION_RATE valid frames
  8. Save to landmarks.npz: X(N,30,126), y(N,), subjects(N,), filenames(N,)

Also writes detection_log.csv with per-video statistics.

Usage:
    python extract_landmarks.py                 # process dataset_augmented/
    python extract_landmarks.py --source original  # process original dataset/
"""

import os
import re
import sys
import csv
import argparse
import time

import cv2
import numpy as np
import mediapipe as mp
from mediapipe.tasks.python import BaseOptions
from mediapipe.tasks.python.vision import (
    HandLandmarker,
    HandLandmarkerOptions,
    RunningMode,
)

from config import (
    DATASET_DIR,
    AUGMENTED_DIR,
    LANDMARKS_FILE,
    DETECTION_LOG,
    HAND_LANDMARKER_PATH,
    CLASSES,
    CLASS_TO_IDX,
    MP_MAX_HANDS,
    MP_MIN_DETECTION_CONF,
    MP_MIN_PRESENCE_CONF,
    MP_MIN_TRACKING_CONF,
    NUM_LANDMARKS_PER_HAND,
    LANDMARK_DIMS,
    FEATURES_PER_HAND,
    TOTAL_FEATURES,
    TARGET_SEQ_LEN,
    MIN_DETECTION_RATE,
)


# ---------------------------------------------------------------------------
# Subject extraction from filename
# ---------------------------------------------------------------------------
SUBJECT_PATTERN = re.compile(r"_Crop_(\d{3})_")


def extract_subject(filename: str) -> str:
    """
    Extract the 3-digit subject ID from a filename like:
      accident_Crop_001_02.avi           -> '001'
      accident_Crop_001_02_hflip.avi     -> '001'
    Falls back to 'unknown' if pattern not found.
    """
    m = SUBJECT_PATTERN.search(filename)
    return m.group(1) if m else "unknown"


# ---------------------------------------------------------------------------
# HandLandmarker creation (Tasks API)
# ---------------------------------------------------------------------------

def create_hand_landmarker(mode: str = "VIDEO") -> HandLandmarker:
    """
    Create a MediaPipe HandLandmarker using the Tasks API.
    A fresh instance is needed per video in VIDEO mode because
    detect_for_video requires strictly increasing timestamps.
    """
    if not os.path.isfile(HAND_LANDMARKER_PATH):
        print(f"[ERROR] HandLandmarker model not found: {HAND_LANDMARKER_PATH}")
        print("  Download from: https://storage.googleapis.com/mediapipe-models/"
              "hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task")
        sys.exit(1)

    run_mode = RunningMode.VIDEO if mode == "VIDEO" else RunningMode.IMAGE

    opts = HandLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=HAND_LANDMARKER_PATH),
        running_mode=run_mode,
        num_hands=MP_MAX_HANDS,
        min_hand_detection_confidence=MP_MIN_DETECTION_CONF,
        min_hand_presence_confidence=MP_MIN_PRESENCE_CONF,
        min_tracking_confidence=MP_MIN_TRACKING_CONF,
    )
    return HandLandmarker.create_from_options(opts)


# ---------------------------------------------------------------------------
# Per-hand normalization
# ---------------------------------------------------------------------------

def normalize_hand(landmarks: np.ndarray) -> np.ndarray:
    """
    Normalize a single hand's landmarks (21, 3).
      1. Subtract wrist (landmark 0) to make wrist-centered
      2. Scale by max distance from any landmark to wrist (origin)
    Returns (21, 3) normalized.
    """
    lm = landmarks.copy()
    wrist = lm[0].copy()
    lm -= wrist

    dists = np.linalg.norm(lm, axis=1)
    max_dist = np.max(dists)
    if max_dist > 1e-6:
        lm /= max_dist

    return lm


# ---------------------------------------------------------------------------
# Extract landmarks from a single video
# ---------------------------------------------------------------------------

def extract_video_landmarks(video_path: str) -> tuple[np.ndarray | None, float]:
    """
    Process one video using a fresh HandLandmarker (VIDEO mode).
    Returns:
      - landmarks array of shape (num_frames, 126) or None on failure
      - detection_rate (fraction of frames with at least one hand)

    For each frame:
      - Run HandLandmarker.detect_for_video()
      - If two hands: sort by wrist.x (left first), normalize each
      - If one hand: assign to hand_0, zero-pad hand_1
      - If no hands: mark frame as missing for interpolation
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return None, 0.0

    video_fps = cap.get(cv2.CAP_PROP_FPS)
    if video_fps <= 0:
        video_fps = 25.0

    # Create a fresh landmarker for this video (timestamps must be increasing)
    landmarker = create_hand_landmarker(mode="VIDEO")
    use_video_mode = True

    all_landmarks = []  # list of (126,) arrays; None for missing frames
    frame_count = 0
    detected_count = 0
    timestamp_ms = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            break
        frame_count += 1

        # Convert to MediaPipe Image
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

        result = None
        if use_video_mode:
            try:
                result = landmarker.detect_for_video(mp_image, timestamp_ms)
            except Exception:
                # Fall back to IMAGE mode if VIDEO mode fails
                try:
                    landmarker.close()
                except Exception:
                    pass
                use_video_mode = False
                landmarker = create_hand_landmarker(mode="IMAGE")
                try:
                    result = landmarker.detect(mp_image)
                except Exception:
                    pass

        if not use_video_mode and result is None:
            try:
                result = landmarker.detect(mp_image)
            except Exception:
                pass

        timestamp_ms += max(1, int(1000 / video_fps))

        if result is not None and result.hand_landmarks and len(result.hand_landmarks) > 0:
            detected_count += 1
            hands_np = []
            for hand_lm in result.hand_landmarks[:MP_MAX_HANDS]:
                lm = np.array([[p.x, p.y, p.z] for p in hand_lm])  # (21, 3)
                hands_np.append(lm)

            # Sort by wrist x-coordinate (left hand first)
            if len(hands_np) == 2:
                if hands_np[0][0, 0] > hands_np[1][0, 0]:
                    hands_np[0], hands_np[1] = hands_np[1], hands_np[0]

            # Normalize each hand
            hand_0 = normalize_hand(hands_np[0])
            hand_1 = (
                normalize_hand(hands_np[1])
                if len(hands_np) >= 2
                else np.zeros((NUM_LANDMARKS_PER_HAND, LANDMARK_DIMS))
            )

            # Flatten: (21*3) + (21*3) = 126
            frame_features = np.concatenate([hand_0.flatten(), hand_1.flatten()])
            all_landmarks.append(frame_features)
        else:
            all_landmarks.append(None)  # missing frame

    cap.release()
    try:
        landmarker.close()
    except Exception:
        pass

    if frame_count == 0:
        return None, 0.0

    detection_rate = detected_count / frame_count

    # Interpolate missing frames
    all_landmarks = interpolate_missing(all_landmarks)

    if all_landmarks is None:
        return None, detection_rate

    # Stack to (num_frames, 126)
    arr = np.stack(all_landmarks, axis=0)

    return arr, detection_rate


def interpolate_missing(landmarks: list) -> list | None:
    """
    Linearly interpolate missing (None) frames.
    If ALL frames are None, return None.
    If only edges are None, fill with nearest valid frame.
    """
    n = len(landmarks)
    if n == 0:
        return None

    valid_idx = [i for i, lm in enumerate(landmarks) if lm is not None]
    if not valid_idx:
        return None

    # Fill leading Nones with first valid
    first_valid = valid_idx[0]
    for i in range(first_valid):
        landmarks[i] = landmarks[first_valid].copy()

    # Fill trailing Nones with last valid
    last_valid = valid_idx[-1]
    for i in range(last_valid + 1, n):
        landmarks[i] = landmarks[last_valid].copy()

    # Interpolate interior gaps
    for k in range(len(valid_idx) - 1):
        i_start = valid_idx[k]
        i_end = valid_idx[k + 1]
        if i_end - i_start <= 1:
            continue
        for j in range(i_start + 1, i_end):
            alpha = (j - i_start) / (i_end - i_start)
            landmarks[j] = (1 - alpha) * landmarks[i_start] + alpha * landmarks[i_end]

    return landmarks


def resample_frames(arr: np.ndarray, target_len: int) -> np.ndarray:
    """
    Resample (T, 126) to (target_len, 126) using linear interpolation.
    """
    T = arr.shape[0]
    if T == target_len:
        return arr
    if T == 0:
        return np.zeros((target_len, arr.shape[1]), dtype=np.float32)

    old_indices = np.linspace(0, T - 1, target_len)
    new_arr = np.zeros((target_len, arr.shape[1]), dtype=np.float32)
    for i, idx in enumerate(old_indices):
        lower = int(np.floor(idx))
        upper = min(lower + 1, T - 1)
        alpha = idx - lower
        new_arr[i] = (1 - alpha) * arr[lower] + alpha * arr[upper]

    return new_arr


# ---------------------------------------------------------------------------
# Visualization debug helper
# ---------------------------------------------------------------------------

def visualize_landmarks(landmarks_2d: np.ndarray, title: str = "Landmarks") -> None:
    """
    Quick visualization of a single video's landmarks (30, 126).
    Plots the first hand's x,y coordinates for each frame.
    Requires matplotlib (optional dependency).
    """
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        print("[WARN] matplotlib not installed, skipping visualization")
        return

    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    for hand_idx, ax in enumerate(axes):
        offset = hand_idx * FEATURES_PER_HAND
        for lm_idx in range(NUM_LANDMARKS_PER_HAND):
            x = landmarks_2d[:, offset + lm_idx * 3]
            y = landmarks_2d[:, offset + lm_idx * 3 + 1]
            ax.plot(x, y, ".-", alpha=0.5, markersize=2)
        ax.set_title(f"{title} - Hand {hand_idx}")
        ax.set_xlabel("x (normalized)")
        ax.set_ylabel("y (normalized)")
        ax.invert_yaxis()
        ax.set_aspect("equal")

    plt.tight_layout()
    plt.savefig("landmarks_debug.png", dpi=100)
    plt.close()
    print(f"  Debug plot saved to landmarks_debug.png")


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------

def run_extraction(source_dir: str) -> None:
    print("=" * 60)
    print("Landmark extraction (Tasks API)")
    print(f"  Source:    {source_dir}")
    print(f"  Output:    {LANDMARKS_FILE}")
    print(f"  Model:     {HAND_LANDMARKER_PATH}")
    print(f"  Target frames: {TARGET_SEQ_LEN}")
    print(f"  Min detection rate: {MIN_DETECTION_RATE:.0%}")
    print("=" * 60)

    if not os.path.isdir(source_dir):
        print(f"[ERROR] Source directory not found: {source_dir}")
        sys.exit(1)

    all_X = []
    all_y = []
    all_subjects = []
    all_filenames = []
    skipped = 0
    failed = 0

    log_rows = []
    t0 = time.time()

    for cls in CLASSES:
        cls_dir = os.path.join(source_dir, cls)
        if not os.path.isdir(cls_dir):
            print(f"  [WARN] Missing class folder: {cls_dir}")
            continue

        videos = sorted([
            f for f in os.listdir(cls_dir)
            if f.lower().endswith((".avi", ".mp4"))
        ])

        cls_count = 0
        for vname in videos:
            vpath = os.path.join(cls_dir, vname)
            landmarks, det_rate = extract_video_landmarks(vpath)

            subject = extract_subject(vname)

            log_rows.append({
                "class": cls,
                "filename": vname,
                "subject": subject,
                "detection_rate": f"{det_rate:.3f}",
                "status": "",
            })

            if landmarks is None:
                log_rows[-1]["status"] = "FAILED"
                failed += 1
                continue

            if det_rate < MIN_DETECTION_RATE:
                log_rows[-1]["status"] = "SKIPPED_LOW_DETECTION"
                skipped += 1
                continue

            # Resample to target length
            resampled = resample_frames(landmarks, TARGET_SEQ_LEN)

            all_X.append(resampled.astype(np.float32))
            all_y.append(CLASS_TO_IDX[cls])
            all_subjects.append(subject)
            all_filenames.append(vname)
            log_rows[-1]["status"] = "OK"
            cls_count += 1

        print(f"  {cls:>10s}: {cls_count} videos extracted from {len(videos)} total")

    # Stack and save
    if not all_X:
        print("[ERROR] No landmarks extracted. Check your dataset and MediaPipe model.")
        sys.exit(1)

    X = np.stack(all_X, axis=0)  # (N, 30, 126)
    y = np.array(all_y, dtype=np.int64)
    subjects = np.array(all_subjects, dtype="U10")
    filenames = np.array(all_filenames, dtype="U200")

    np.savez_compressed(
        LANDMARKS_FILE,
        X=X, y=y, subjects=subjects, filenames=filenames,
    )

    elapsed = time.time() - t0
    print("-" * 60)
    print(f"  Saved: {X.shape[0]} samples, shape {X.shape}")
    print(f"  Skipped (low detection): {skipped}")
    print(f"  Failed (unreadable): {failed}")
    print(f"  Time: {elapsed:.1f}s")
    print(f"  File: {LANDMARKS_FILE}")

    # Write detection log
    with open(DETECTION_LOG, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["class", "filename", "subject", "detection_rate", "status"])
        writer.writeheader()
        writer.writerows(log_rows)
    print(f"  Log:  {DETECTION_LOG}")
    print("=" * 60)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract hand landmarks from video dataset")
    parser.add_argument(
        "--source", type=str, default="augmented",
        choices=["augmented", "original"],
        help="Which dataset to process: 'augmented' (default) or 'original'",
    )
    args = parser.parse_args()

    source = AUGMENTED_DIR if args.source == "augmented" else DATASET_DIR
    run_extraction(source)
