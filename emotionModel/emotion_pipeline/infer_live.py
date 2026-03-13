from __future__ import annotations

import argparse
from pathlib import Path

import cv2
import numpy as np
import tensorflow as tf

from .config import DEFAULT_ARTIFACT_DIR, DEFAULT_FACE_LANDMARKER_TASK
from .model import ClassBalancedFocalLoss, RegionTokenStack
from .predict import create_face_landmarker, extract_landmarks_from_frame, load_runtime_assets, predict_from_landmarks


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run live webcam emotion inference using MediaPipe landmarks")
    parser.add_argument("--artifacts-dir", default=str(DEFAULT_ARTIFACT_DIR))
    parser.add_argument("--model-path", default=None)
    parser.add_argument("--face-landmarker-task", default=str(DEFAULT_FACE_LANDMARKER_TASK))
    parser.add_argument("--camera-index", type=int, default=0)
    return parser.parse_args()


def draw_prediction(frame: np.ndarray, label: str, confidence: float) -> None:
    text = f"emotion: {label}  confidence: {confidence:.2f}"
    cv2.putText(frame, text, (20, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 255, 0), 2)


def main() -> None:
    args = parse_args()
    artifacts_dir = Path(args.artifacts_dir)
    model, stats, feature_config, labels = load_runtime_assets(artifacts_dir)
    if args.model_path:
        model = tf.keras.models.load_model(
            Path(args.model_path),
            safe_mode=False,
            custom_objects={"RegionTokenStack": RegionTokenStack, "ClassBalancedFocalLoss": ClassBalancedFocalLoss},
            compile=False,
        )

    cap = cv2.VideoCapture(args.camera_index)
    if not cap.isOpened():
        raise RuntimeError("Unable to open camera")

    with create_face_landmarker(args.face_landmarker_task) as landmarker:
        while True:
            ok, frame = cap.read()
            if not ok:
                break

            landmarks = extract_landmarks_from_frame(landmarker, frame)
            if landmarks is not None:
                result = predict_from_landmarks(landmarks, model, stats, feature_config, labels)
                draw_prediction(frame, result["emotion"], result["confidence"])

            cv2.imshow("Emotion Landmark Inference", frame)
            key = cv2.waitKey(1) & 0xFF
            if key in (27, ord("q")):
                break

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
