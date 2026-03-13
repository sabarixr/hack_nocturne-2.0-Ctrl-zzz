"""
Live webcam gesture recognition using the EXPORTED TFLite model.

This is the TFLite equivalent of live_test.py — uses the same MediaPipe
landmark extraction and normalization pipeline, but runs inference through
TFLite instead of PyTorch. Use this to verify the exported model works
correctly before deploying to Flutter.

Pipeline:
    Webcam frame -> MediaPipe HandLandmarker (IMAGE mode) -> 126-dim landmarks
    -> Sliding window buffer (30 frames) -> TFLite interpreter -> prediction
    -> Majority voting over last N predictions -> stable display

Controls:
    Q = quit
    R = reset buffer
    S = screenshot

Usage:
    python live_test_tflite.py
    python live_test_tflite.py --tflite models/flutter_export/sign_language_model.tflite
    python live_test_tflite.py --camera 1
"""

import os
import sys
import time

import cv2
import numpy as np
from collections import deque

import mediapipe as mp
from mediapipe.tasks.python import BaseOptions
from mediapipe.tasks.python.vision import (
    HandLandmarker,
    HandLandmarkerOptions,
    RunningMode,
)

from config import (
    HAND_LANDMARKER_PATH,
    CLASSES,
    TARGET_SEQ_LEN,
    TOTAL_FEATURES,
    MP_MAX_HANDS,
    MP_MIN_DETECTION_CONF,
    MP_MIN_PRESENCE_CONF,
    NUM_LANDMARKS_PER_HAND,
    LANDMARK_DIMS,
    BASE_DIR,
)

# ---------------------------------------------------------------------------
# Default TFLite model path
# ---------------------------------------------------------------------------
DEFAULT_TFLITE_PATH = os.path.join(
    BASE_DIR, "models", "flutter_export", "sign_language_model.tflite"
)

# ---------------------------------------------------------------------------
# Constants (same as live_test.py)
# ---------------------------------------------------------------------------
SLIDING_WINDOW_STRIDE = 3
VOTING_WINDOW_SIZE = 7
CONFIDENCE_THRESHOLD = 0.40
NO_HAND_RESET_FRAMES = 10

# BGR colors
COLOR_GREEN = (0, 255, 0)
COLOR_RED = (0, 0, 255)
COLOR_YELLOW = (0, 255, 255)
COLOR_WHITE = (255, 255, 255)
COLOR_BLACK = (0, 0, 0)
COLOR_GRAY = (128, 128, 128)
COLOR_CYAN = (255, 255, 0)

HAND_CONNECTIONS = [
    (0, 1), (1, 2), (2, 3), (3, 4),
    (0, 5), (5, 6), (6, 7), (7, 8),
    (0, 9), (9, 10), (10, 11), (11, 12),
    (0, 13), (13, 14), (14, 15), (15, 16),
    (0, 17), (17, 18), (18, 19), (19, 20),
    (5, 9), (9, 13), (13, 17),
]


# ---------------------------------------------------------------------------
# Normalization — identical to extract_landmarks.py / live_test.py
# ---------------------------------------------------------------------------

def normalize_hand(landmarks: np.ndarray) -> np.ndarray:
    """Wrist-center + scale by max distance from wrist. Input/output: (21, 3)."""
    lm = landmarks.copy()
    wrist = lm[0].copy()
    lm -= wrist
    dists = np.linalg.norm(lm, axis=1)
    max_dist = np.max(dists)
    if max_dist > 1e-6:
        lm /= max_dist
    return lm


def extract_landmark_vector(result) -> tuple:
    """
    Extract 126-dim normalized landmark vector from a HandLandmarker result.
    Returns (vector, hands_detected).
    """
    if not result or not result.hand_landmarks or len(result.hand_landmarks) == 0:
        return np.zeros(TOTAL_FEATURES, dtype=np.float32), False

    hands_np = []
    for hand_lm in result.hand_landmarks[:MP_MAX_HANDS]:
        lm = np.array([[p.x, p.y, p.z] for p in hand_lm])
        hands_np.append(lm)

    # Sort by wrist x (left hand first)
    if len(hands_np) == 2 and hands_np[0][0, 0] > hands_np[1][0, 0]:
        hands_np[0], hands_np[1] = hands_np[1], hands_np[0]

    hand_0 = normalize_hand(hands_np[0])
    hand_1 = (
        normalize_hand(hands_np[1])
        if len(hands_np) >= 2
        else np.zeros((NUM_LANDMARKS_PER_HAND, LANDMARK_DIMS))
    )

    vector = np.concatenate([hand_0.flatten(), hand_1.flatten()])
    return vector.astype(np.float32), True


# ---------------------------------------------------------------------------
# TFLite inference wrapper
# ---------------------------------------------------------------------------

class TFLiteModel:
    """Thin wrapper around TFLite interpreter."""

    def __init__(self, model_path: str):
        import tensorflow as tf

        self.interpreter = tf.lite.Interpreter(model_path=model_path)
        self.interpreter.allocate_tensors()

        self.input_details = self.interpreter.get_input_details()
        self.output_details = self.interpreter.get_output_details()

        in_shape = self.input_details[0]["shape"]
        out_shape = self.output_details[0]["shape"]
        print(f"  TFLite input shape:  {in_shape}  dtype={self.input_details[0]['dtype']}")
        print(f"  TFLite output shape: {out_shape} dtype={self.output_details[0]['dtype']}")

    def predict(self, input_data: np.ndarray) -> np.ndarray:
        """
        Run inference.
        input_data: (1, 30, 126) float32
        returns: (8,) probabilities after softmax
        """
        self.interpreter.set_tensor(self.input_details[0]["index"], input_data)
        self.interpreter.invoke()
        logits = self.interpreter.get_tensor(self.output_details[0]["index"])[0]  # (8,)

        # Apply softmax
        exp_logits = np.exp(logits - np.max(logits))
        probs = exp_logits / exp_logits.sum()
        return probs


# ---------------------------------------------------------------------------
# Drawing helpers
# ---------------------------------------------------------------------------

def draw_hand_landmarks(frame, hand_landmarks_list, frame_w, frame_h):
    for hand_lms in hand_landmarks_list:
        coords = [(lm.x, lm.y) for lm in hand_lms]
        for i, j in HAND_CONNECTIONS:
            x1, y1 = int(coords[i][0] * frame_w), int(coords[i][1] * frame_h)
            x2, y2 = int(coords[j][0] * frame_w), int(coords[j][1] * frame_h)
            cv2.line(frame, (x1, y1), (x2, y2), (255, 200, 0), 2)
        for x, y in coords:
            cv2.circle(frame, (int(x * frame_w), int(y * frame_h)), 4, (0, 255, 128), -1)


def draw_overlay(frame, prediction, confidence, buffer_size, hands_detected, fps):
    fh, fw = frame.shape[:2]

    # Semi-transparent top bar
    overlay = frame.copy()
    cv2.rectangle(overlay, (0, 0), (fw, 100), COLOR_BLACK, -1)
    cv2.addWeighted(overlay, 0.65, frame, 0.35, 0, frame)

    # TFLite badge
    cv2.putText(frame, "[TFLite]", (fw - 120, 20),
                cv2.FONT_HERSHEY_SIMPLEX, 0.5, COLOR_CYAN, 1)

    if prediction is not None and confidence >= CONFIDENCE_THRESHOLD:
        if confidence >= 0.80:
            color = COLOR_GREEN
        elif confidence >= 0.60:
            color = COLOR_YELLOW
        else:
            color = COLOR_RED

        label = f"{prediction.upper()} ({confidence:.0%})"
        cv2.putText(frame, label, (15, 40), cv2.FONT_HERSHEY_SIMPLEX, 1.2, color, 3)

        bar_w = int((fw - 30) * confidence)
        cv2.rectangle(frame, (15, 55), (15 + bar_w, 72), color, -1)
        cv2.rectangle(frame, (15, 55), (fw - 15, 72), COLOR_WHITE, 1)
    else:
        min_frames = TARGET_SEQ_LEN // 2
        if buffer_size < min_frames:
            msg = f"Collecting frames... ({buffer_size}/{min_frames})"
            cv2.putText(frame, msg, (15, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.8, COLOR_WHITE, 2)
        elif not hands_detected:
            cv2.putText(frame, "No hands detected - show a sign!", (15, 40),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, COLOR_GRAY, 2)
        else:
            cv2.putText(frame, "Analyzing gesture...", (15, 40),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, COLOR_YELLOW, 2)

    # Bottom status
    status_y = fh - 40
    hand_color = COLOR_GREEN if hands_detected else COLOR_RED
    hand_text = "DETECTED" if hands_detected else "NOT DETECTED"
    cv2.putText(frame, f"Hands: {hand_text}", (15, status_y),
                cv2.FONT_HERSHEY_SIMPLEX, 0.5, hand_color, 1)

    cv2.putText(frame, f"Buffer: {buffer_size}/{TARGET_SEQ_LEN} | FPS: {fps:.0f}",
                (15, fh - 15), cv2.FONT_HERSHEY_SIMPLEX, 0.4, COLOR_WHITE, 1)

    cv2.putText(frame, "Q:quit  R:reset  S:screenshot", (fw - 280, fh - 15),
                cv2.FONT_HERSHEY_SIMPLEX, 0.4, COLOR_WHITE, 1)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Live webcam gesture recognition (TFLite)")
    parser.add_argument("--tflite", type=str, default=DEFAULT_TFLITE_PATH,
                        help=f"Path to TFLite model (default: {DEFAULT_TFLITE_PATH})")
    parser.add_argument("--camera", type=int, default=0,
                        help="Camera index (default: 0)")
    args = parser.parse_args()

    # =========================================================================
    # Load TFLite model
    # =========================================================================
    if not os.path.isfile(args.tflite):
        print(f"[ERROR] TFLite model not found: {args.tflite}")
        print("  Run export_tflite.py first.")
        sys.exit(1)

    print(f"  Loading TFLite model: {args.tflite}")
    tflite_model = TFLiteModel(args.tflite)
    size_mb = os.path.getsize(args.tflite) / (1024 * 1024)
    print(f"  Model size: {size_mb:.2f} MB")

    # =========================================================================
    # Initialize MediaPipe HandLandmarker (IMAGE mode)
    # =========================================================================
    if not os.path.isfile(HAND_LANDMARKER_PATH):
        print(f"[ERROR] HandLandmarker model not found: {HAND_LANDMARKER_PATH}")
        sys.exit(1)

    opts = HandLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=HAND_LANDMARKER_PATH),
        running_mode=RunningMode.IMAGE,
        num_hands=MP_MAX_HANDS,
        min_hand_detection_confidence=MP_MIN_DETECTION_CONF,
        min_hand_presence_confidence=MP_MIN_PRESENCE_CONF,
    )
    hand_landmarker = HandLandmarker.create_from_options(opts)
    print("  MediaPipe HandLandmarker initialized (IMAGE mode)")

    # =========================================================================
    # Open webcam
    # =========================================================================
    print(f"  Opening camera {args.camera}...")
    cap = cv2.VideoCapture(args.camera)
    if not cap.isOpened():
        print("[ERROR] Cannot open webcam.")
        sys.exit(1)

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

    # Buffers
    landmark_buffer = deque(maxlen=TARGET_SEQ_LEN)
    prediction_history = deque(maxlen=VOTING_WINDOW_SIZE)

    current_prediction = None
    current_confidence = 0.0
    frame_count = 0
    hands_detected = False
    fps_timer = time.time()
    fps_count = 0
    fps_display = 0.0

    print(f"\n{'=' * 50}")
    print(f"  LIVE GESTURE RECOGNITION (TFLite)")
    print(f"  Model:   {args.tflite}")
    print(f"  Classes: {', '.join(CLASSES)}")
    print(f"  Window:  {TARGET_SEQ_LEN} frames, stride {SLIDING_WINDOW_STRIDE}")
    print(f"  Voting:  {VOTING_WINDOW_SIZE} predictions, threshold {CONFIDENCE_THRESHOLD:.0%}")
    print(f"{'=' * 50}")
    print("  Press Q to quit, R to reset, S for screenshot\n")

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break

            fh, fw = frame.shape[:2]
            frame = cv2.flip(frame, 1)

            # =================================================================
            # Extract landmarks
            # =================================================================
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

            try:
                result = hand_landmarker.detect(mp_image)
            except Exception:
                result = None

            landmark_vector, hands_detected = extract_landmark_vector(result)

            if result and result.hand_landmarks:
                draw_hand_landmarks(frame, result.hand_landmarks, fw, fh)

            landmark_buffer.append(landmark_vector)
            frame_count += 1
            fps_count += 1

            # =================================================================
            # Run TFLite prediction (sliding window)
            # =================================================================
            min_frames = TARGET_SEQ_LEN // 2
            if (len(landmark_buffer) >= min_frames and
                    frame_count % SLIDING_WINDOW_STRIDE == 0):

                buffer_arr = np.array(list(landmark_buffer), dtype=np.float32)

                buf_len = buffer_arr.shape[0]
                if buf_len < TARGET_SEQ_LEN:
                    padded = np.zeros((TARGET_SEQ_LEN, TOTAL_FEATURES), dtype=np.float32)
                    padded[:buf_len] = buffer_arr
                    buffer_arr = padded

                # TFLite inference
                input_data = buffer_arr[np.newaxis, ...]  # (1, 30, 126)
                probs = tflite_model.predict(input_data)

                class_idx = np.argmax(probs)
                pred_conf = float(probs[class_idx])
                pred_class = CLASSES[class_idx]

                prediction_history.append((pred_class, pred_conf))

                # Majority voting weighted by confidence
                if len(prediction_history) > 0:
                    class_votes = {}
                    for cls, conf in prediction_history:
                        if conf >= CONFIDENCE_THRESHOLD:
                            class_votes[cls] = class_votes.get(cls, 0) + conf

                    if class_votes:
                        best_class = max(class_votes, key=class_votes.get)
                        winner_confs = [
                            conf for cls, conf in prediction_history
                            if cls == best_class
                        ]
                        avg_conf = sum(winner_confs) / len(winner_confs)
                        current_prediction = best_class
                        current_confidence = avg_conf
                    else:
                        current_prediction = None
                        current_confidence = 0.0

            # Reset if no hands for a while
            if not hands_detected and len(landmark_buffer) > 0:
                recent = list(landmark_buffer)[-NO_HAND_RESET_FRAMES:]
                no_hand_count = sum(1 for lm in recent if np.all(lm == 0))
                if no_hand_count >= NO_HAND_RESET_FRAMES - 2:
                    current_prediction = None
                    current_confidence = 0.0
                    prediction_history.clear()

            # =================================================================
            # Draw overlay + display
            # =================================================================
            elapsed = time.time() - fps_timer
            if elapsed >= 1.0:
                fps_display = fps_count / elapsed
                fps_count = 0
                fps_timer = time.time()

            draw_overlay(frame, current_prediction, current_confidence,
                         len(landmark_buffer), hands_detected, fps_display)

            cv2.imshow("ISL Gesture Recognition - TFLite", frame)

            key = cv2.waitKey(1) & 0xFF
            if key == ord("q"):
                break
            elif key == ord("r"):
                landmark_buffer.clear()
                prediction_history.clear()
                current_prediction = None
                current_confidence = 0.0
                print("  Buffer reset.")
            elif key == ord("s"):
                path = f"screenshot_{int(time.time())}.png"
                cv2.imwrite(path, frame)
                print(f"  Screenshot saved: {path}")

    except KeyboardInterrupt:
        print("\n  Interrupted.")
    finally:
        cap.release()
        cv2.destroyAllWindows()
        try:
            hand_landmarker.close()
        except Exception:
            pass
        print("  Done.")


if __name__ == "__main__":
    main()
