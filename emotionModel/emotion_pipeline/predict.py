from __future__ import annotations

from pathlib import Path
from typing import Dict, List, Tuple

import cv2
import mediapipe as mp
import numpy as np
import tensorflow as tf

from .config import DEFAULT_ARTIFACT_DIR, DEFAULT_FEATURE_CONFIG_PATH, DEFAULT_LABEL_MAP_PATH, DEFAULT_MODEL_PATH, DEFAULT_PREPROCESSOR_PATH, DEFAULT_TFLITE_PATH, NUM_LANDMARKS
from .features import EngineeredFeatureConfig, compute_engineered_features, normalize_landmarks, region_indices
from .model import ClassBalancedFocalLoss, RegionTokenStack
from .utils import load_json


BaseOptions = mp.tasks.BaseOptions
FaceLandmarker = mp.tasks.vision.FaceLandmarker
FaceLandmarkerOptions = mp.tasks.vision.FaceLandmarkerOptions
RunningMode = mp.tasks.vision.RunningMode


def load_runtime_assets(artifacts_dir: str | Path = DEFAULT_ARTIFACT_DIR) -> Tuple[tf.keras.Model, dict[str, np.ndarray], EngineeredFeatureConfig, List[str]]:
    artifacts = Path(artifacts_dir)
    model = tf.keras.models.load_model(
        artifacts / DEFAULT_MODEL_PATH.name,
        safe_mode=False,
        custom_objects={"RegionTokenStack": RegionTokenStack, "ClassBalancedFocalLoss": ClassBalancedFocalLoss},
        compile=False,
    )
    stats = np.load(artifacts / DEFAULT_PREPROCESSOR_PATH.name)
    feature_config_data = load_json(artifacts / DEFAULT_FEATURE_CONFIG_PATH.name)
    label_map = load_json(artifacts / DEFAULT_LABEL_MAP_PATH.name)
    labels = [label_map[str(index)] for index in range(len(label_map))]
    feature_config = EngineeredFeatureConfig(
        include_engineered=bool(feature_config_data["include_engineered"]),
        center_index=int(feature_config_data["center_index"]),
    )
    return model, {key: stats[key] for key in stats.files}, feature_config, labels


def create_face_landmarker(task_path: str | Path) -> FaceLandmarker:
    options = FaceLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=str(task_path)),
        running_mode=RunningMode.IMAGE,
        num_faces=1,
    )
    return FaceLandmarker.create_from_options(options)


def extract_landmarks_from_frame(landmarker: FaceLandmarker, frame_bgr: np.ndarray) -> np.ndarray | None:
    frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame_rgb)
    result = landmarker.detect(mp_image)
    if not result.face_landmarks:
        return None
    face = result.face_landmarks[0]
    if len(face) != NUM_LANDMARKS:
        return None
    return np.asarray([[point.x, point.y, point.z] for point in face], dtype=np.float32)


def preprocess_landmarks(landmarks: np.ndarray, stats: dict[str, np.ndarray], feature_config: EngineeredFeatureConfig) -> tuple[np.ndarray, np.ndarray]:
    normalized = normalize_landmarks(landmarks, center_index=feature_config.center_index)
    engineered = compute_engineered_features(normalized) if feature_config.include_engineered else np.zeros(0, dtype=np.float32)
    standardized_landmarks = ((normalized - stats["landmark_mean"]) / stats["landmark_std"]).astype(np.float32)
    standardized_engineered = ((engineered - stats["engineered_mean"]) / stats["engineered_std"]).astype(np.float32)
    return standardized_landmarks, standardized_engineered


def build_model_inputs(standardized_landmarks: np.ndarray, standardized_engineered: np.ndarray) -> Dict[str, np.ndarray]:
    regions = region_indices()
    return {
        "landmarks": standardized_landmarks[None, ...].astype(np.float32),
        "engineered_features": standardized_engineered[None, ...].astype(np.float32),
        "left_eye_brow": standardized_landmarks[regions["left_eye_brow"]][None, ...].astype(np.float32),
        "right_eye_brow": standardized_landmarks[regions["right_eye_brow"]][None, ...].astype(np.float32),
        "mouth": standardized_landmarks[regions["mouth"]][None, ...].astype(np.float32),
        "nose": standardized_landmarks[regions["nose"]][None, ...].astype(np.float32),
    }


def predict_from_landmarks(
    landmarks: np.ndarray,
    model: tf.keras.Model,
    stats: dict[str, np.ndarray],
    feature_config: EngineeredFeatureConfig,
    labels: List[str],
) -> Dict[str, object]:
    standardized_landmarks, standardized_engineered = preprocess_landmarks(landmarks, stats, feature_config)
    probabilities = model.predict(build_model_inputs(standardized_landmarks, standardized_engineered), verbose=0)[0]
    index = int(np.argmax(probabilities))
    return {
        "emotion": labels[index],
        "confidence": float(probabilities[index]),
        "probabilities": {label: float(probabilities[i]) for i, label in enumerate(labels)},
    }


class TFLiteEmotionClassifier:
    def __init__(self, artifacts_dir: str | Path = DEFAULT_ARTIFACT_DIR, tflite_path: str | Path | None = None) -> None:
        artifacts = Path(artifacts_dir)
        stats = np.load(artifacts / DEFAULT_PREPROCESSOR_PATH.name)
        feature_config_data = load_json(artifacts / DEFAULT_FEATURE_CONFIG_PATH.name)
        label_map = load_json(artifacts / DEFAULT_LABEL_MAP_PATH.name)

        self.stats = {key: stats[key] for key in stats.files}
        self.labels = [label_map[str(index)] for index in range(len(label_map))]
        self.feature_config = EngineeredFeatureConfig(
            include_engineered=bool(feature_config_data["include_engineered"]),
            center_index=int(feature_config_data["center_index"]),
        )

        model_path = Path(tflite_path) if tflite_path else artifacts / DEFAULT_TFLITE_PATH.name
        self.interpreter = tf.lite.Interpreter(model_path=str(model_path))
        self.interpreter.allocate_tensors()
        self.input_details = self.interpreter.get_input_details()
        self.input_name_map = {detail["name"]: detail for detail in self.input_details}
        self.output_details = self.interpreter.get_output_details()[0]

    def _resolve_input_detail(self, logical_name: str):
        candidates = [
            logical_name,
            f"serving_default_{logical_name}:0",
            f"{logical_name}:0",
        ]
        for candidate in candidates:
            if candidate in self.input_name_map:
                return self.input_name_map[candidate]
        for detail in self.input_details:
            if logical_name in detail["name"]:
                return detail
        raise KeyError(f"Unable to find TFLite input tensor for '{logical_name}'")

    def predict(self, landmarks: np.ndarray) -> Dict[str, object]:
        standardized_landmarks, standardized_engineered = preprocess_landmarks(landmarks, self.stats, self.feature_config)
        model_inputs = build_model_inputs(standardized_landmarks, standardized_engineered)
        for logical_name, value in model_inputs.items():
            detail = self._resolve_input_detail(logical_name)
            self.interpreter.set_tensor(detail["index"], value.astype(np.float32))
        self.interpreter.invoke()
        probabilities = self.interpreter.get_tensor(self.output_details["index"])[0]
        index = int(np.argmax(probabilities))
        return {
            "emotion": self.labels[index],
            "confidence": float(probabilities[index]),
            "probabilities": {label: float(probabilities[i]) for i, label in enumerate(self.labels)},
        }
