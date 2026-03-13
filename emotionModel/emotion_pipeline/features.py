from __future__ import annotations

from dataclasses import dataclass
from typing import Dict

import numpy as np

from .config import NUM_LANDMARKS, RAW_FEATURE_SIZE


def _distance(points: np.ndarray, left: int, right: int) -> float:
    return float(np.linalg.norm(points[left] - points[right]))


def _safe_ratio(numerator: float, denominator: float, eps: float = 1e-6) -> float:
    return float(numerator / max(abs(denominator), eps))


def _batch_distance(points: np.ndarray, left: int, right: int) -> np.ndarray:
    return np.linalg.norm(points[:, left] - points[:, right], axis=1)


def _batch_safe_ratio(numerator: np.ndarray, denominator: np.ndarray, eps: float = 1e-6) -> np.ndarray:
    return numerator / np.maximum(np.abs(denominator), eps)


@dataclass(frozen=True)
class EngineeredFeatureConfig:
    include_engineered: bool = True
    center_index: int = 1


ENGINEERED_FEATURE_NAMES = [
    "left_eyebrow_raise",
    "right_eyebrow_raise",
    "brow_raise_asymmetry",
    "left_eye_openness",
    "right_eye_openness",
    "eye_openness_asymmetry",
    "mouth_openness",
    "lip_corner_width",
    "left_lip_corner_offset_x",
    "right_lip_corner_offset_x",
    "lip_corner_asymmetry",
    "left_eyebrow_slope",
    "right_eyebrow_slope",
]

LEFT_EYE_INDICES = np.asarray([33, 133, 159, 145, 158, 153], dtype=np.int32)
RIGHT_EYE_INDICES = np.asarray([362, 263, 386, 374, 385, 380], dtype=np.int32)
LEFT_BROW_INDICES = np.asarray([46, 52, 53, 63, 65, 66, 70, 105], dtype=np.int32)
RIGHT_BROW_INDICES = np.asarray([276, 282, 283, 293, 295, 296, 300, 334], dtype=np.int32)
MOUTH_INDICES = np.asarray([13, 14, 61, 78, 81, 84, 87, 91, 95, 146, 178, 181, 185, 191, 267, 269, 270, 291, 308, 311, 314, 317, 321, 324, 375, 402, 405, 409], dtype=np.int32)
NOSE_INDICES = np.asarray([1, 2, 4, 5, 6, 19, 45, 48, 49, 51, 64, 94, 97, 98, 115, 168, 195, 197, 220, 275, 278, 279, 281, 294, 440], dtype=np.int32)


def region_indices() -> Dict[str, np.ndarray]:
    return {
        "left_eye_brow": np.unique(np.concatenate([LEFT_EYE_INDICES, LEFT_BROW_INDICES])),
        "right_eye_brow": np.unique(np.concatenate([RIGHT_EYE_INDICES, RIGHT_BROW_INDICES])),
        "mouth": MOUTH_INDICES,
        "nose": NOSE_INDICES,
    }


def reshape_landmarks(flat_features: np.ndarray) -> np.ndarray:
    features = np.asarray(flat_features, dtype=np.float32)
    if features.shape[-1] != RAW_FEATURE_SIZE:
        raise ValueError(f"Expected flat feature size {RAW_FEATURE_SIZE}, got {features.shape[-1]}")
    return features.reshape(NUM_LANDMARKS, 3)


def normalize_landmarks(landmarks: np.ndarray, center_index: int = 1) -> np.ndarray:
    coords = np.asarray(landmarks, dtype=np.float32)
    if coords.shape != (NUM_LANDMARKS, 3):
        raise ValueError(f"Expected landmarks shape ({NUM_LANDMARKS}, 3), got {coords.shape}")

    center = coords[center_index]
    centered = coords - center

    left_eye = coords[33]
    right_eye = coords[263]
    eye_vector = right_eye[:2] - left_eye[:2]
    angle = -np.arctan2(eye_vector[1], eye_vector[0])
    cos_angle = np.cos(angle)
    sin_angle = np.sin(angle)
    rotation = np.asarray([[cos_angle, -sin_angle], [sin_angle, cos_angle]], dtype=np.float32)
    centered[:, :2] = centered[:, :2] @ rotation.T

    min_xy = centered[:, :2].min(axis=0)
    max_xy = centered[:, :2].max(axis=0)
    width_height = np.maximum(max_xy - min_xy, 1e-6)
    interpupil = max(float(np.linalg.norm((right_eye - left_eye)[:2])), 1e-6)
    scale = float(max(width_height[0], width_height[1], interpupil, 1e-6))

    normalized = centered / scale
    return normalized.astype(np.float32)


def normalize_landmark_batch(landmarks_batch: np.ndarray, center_index: int = 1) -> np.ndarray:
    coords = np.asarray(landmarks_batch, dtype=np.float32)
    if coords.ndim != 3 or coords.shape[1:] != (NUM_LANDMARKS, 3):
        raise ValueError(f"Expected landmark batch shape (N, {NUM_LANDMARKS}, 3), got {coords.shape}")

    centers = coords[:, center_index:center_index + 1, :]
    centered = coords - centers

    left_eye = coords[:, 33, :2]
    right_eye = coords[:, 263, :2]
    eye_vector = right_eye - left_eye
    angles = -np.arctan2(eye_vector[:, 1], eye_vector[:, 0])
    cos_angles = np.cos(angles)
    sin_angles = np.sin(angles)
    rotation = np.stack(
        [
            np.stack([cos_angles, -sin_angles], axis=1),
            np.stack([sin_angles, cos_angles], axis=1),
        ],
        axis=1,
    )
    centered[:, :, :2] = np.einsum("nij,nkj->nki", rotation, centered[:, :, :2])

    min_xy = centered[:, :, :2].min(axis=1)
    max_xy = centered[:, :, :2].max(axis=1)
    width_height = np.maximum(max_xy - min_xy, 1e-6)
    interpupil = np.linalg.norm(right_eye - left_eye, axis=1, keepdims=True)
    scale = np.maximum(np.max(width_height, axis=1, keepdims=True), interpupil)
    scale = np.maximum(scale, 1e-6).reshape(-1, 1, 1)
    return (centered / scale).astype(np.float32)


def compute_engineered_features(normalized_landmarks: np.ndarray) -> np.ndarray:
    points = np.asarray(normalized_landmarks, dtype=np.float32)
    if points.shape != (NUM_LANDMARKS, 3):
        raise ValueError(f"Expected normalized landmarks shape ({NUM_LANDMARKS}, 3), got {points.shape}")

    left_eye_width = _distance(points, 33, 133)
    right_eye_width = _distance(points, 362, 263)
    mouth_width = _distance(points, 61, 291)
    face_width = _distance(points, 234, 454)

    left_eyebrow_raise = _safe_ratio(abs(points[70, 1] - points[159, 1]), left_eye_width)
    right_eyebrow_raise = _safe_ratio(abs(points[300, 1] - points[386, 1]), right_eye_width)
    brow_raise_asymmetry = left_eyebrow_raise - right_eyebrow_raise
    left_eye_openness = _safe_ratio(_distance(points, 159, 145), left_eye_width)
    right_eye_openness = _safe_ratio(_distance(points, 386, 374), right_eye_width)
    eye_openness_asymmetry = left_eye_openness - right_eye_openness
    mouth_openness = _safe_ratio(_distance(points, 13, 14), mouth_width)
    lip_corner_width = _safe_ratio(mouth_width, face_width)
    left_lip_corner_offset_x = _safe_ratio(points[61, 0] - points[1, 0], face_width)
    right_lip_corner_offset_x = _safe_ratio(points[291, 0] - points[1, 0], face_width)
    lip_corner_asymmetry = left_lip_corner_offset_x + right_lip_corner_offset_x
    left_eyebrow_slope = _safe_ratio(points[105, 1] - points[66, 1], points[105, 0] - points[66, 0])
    right_eyebrow_slope = _safe_ratio(points[334, 1] - points[296, 1], points[334, 0] - points[296, 0])

    return np.asarray(
        [
            left_eyebrow_raise,
            right_eyebrow_raise,
            brow_raise_asymmetry,
            left_eye_openness,
            right_eye_openness,
            eye_openness_asymmetry,
            mouth_openness,
            lip_corner_width,
            left_lip_corner_offset_x,
            right_lip_corner_offset_x,
            lip_corner_asymmetry,
            left_eyebrow_slope,
            right_eyebrow_slope,
        ],
        dtype=np.float32,
    )


def compute_engineered_features_batch(normalized_landmarks: np.ndarray) -> np.ndarray:
    points = np.asarray(normalized_landmarks, dtype=np.float32)
    if points.ndim != 3 or points.shape[1:] != (NUM_LANDMARKS, 3):
        raise ValueError(f"Expected normalized landmark batch shape (N, {NUM_LANDMARKS}, 3), got {points.shape}")

    left_eye_width = _batch_distance(points, 33, 133)
    right_eye_width = _batch_distance(points, 362, 263)
    mouth_width = _batch_distance(points, 61, 291)
    face_width = _batch_distance(points, 234, 454)

    engineered = np.stack(
        [
            _batch_safe_ratio(np.abs(points[:, 70, 1] - points[:, 159, 1]), left_eye_width),
            _batch_safe_ratio(np.abs(points[:, 300, 1] - points[:, 386, 1]), right_eye_width),
            _batch_safe_ratio(np.abs(points[:, 70, 1] - points[:, 159, 1]), left_eye_width)
            - _batch_safe_ratio(np.abs(points[:, 300, 1] - points[:, 386, 1]), right_eye_width),
            _batch_safe_ratio(_batch_distance(points, 159, 145), left_eye_width),
            _batch_safe_ratio(_batch_distance(points, 386, 374), right_eye_width),
            _batch_safe_ratio(_batch_distance(points, 159, 145), left_eye_width)
            - _batch_safe_ratio(_batch_distance(points, 386, 374), right_eye_width),
            _batch_safe_ratio(_batch_distance(points, 13, 14), mouth_width),
            _batch_safe_ratio(mouth_width, face_width),
            _batch_safe_ratio(points[:, 61, 0] - points[:, 1, 0], face_width),
            _batch_safe_ratio(points[:, 291, 0] - points[:, 1, 0], face_width),
            _batch_safe_ratio(points[:, 61, 0] - points[:, 1, 0], face_width)
            + _batch_safe_ratio(points[:, 291, 0] - points[:, 1, 0], face_width),
            _batch_safe_ratio(points[:, 105, 1] - points[:, 66, 1], points[:, 105, 0] - points[:, 66, 0]),
            _batch_safe_ratio(points[:, 334, 1] - points[:, 296, 1], points[:, 334, 0] - points[:, 296, 0]),
        ],
        axis=1,
    )
    return engineered.astype(np.float32)


def build_feature_vector(landmarks: np.ndarray, config: EngineeredFeatureConfig | None = None) -> np.ndarray:
    feature_config = config or EngineeredFeatureConfig()
    normalized = normalize_landmarks(landmarks, center_index=feature_config.center_index)
    flat = normalized.reshape(-1)

    if not feature_config.include_engineered:
        return flat.astype(np.float32)

    engineered = compute_engineered_features(normalized)
    return np.concatenate([flat, engineered], axis=0).astype(np.float32)


def feature_config_to_dict(config: EngineeredFeatureConfig) -> Dict[str, object]:
    return {
        "include_engineered": config.include_engineered,
        "center_index": config.center_index,
        "engineered_feature_names": list(ENGINEERED_FEATURE_NAMES),
    }


def transform_feature_rows(flat_rows: np.ndarray, config: EngineeredFeatureConfig | None = None) -> np.ndarray:
    rows = np.asarray(flat_rows, dtype=np.float32)
    feature_config = config or EngineeredFeatureConfig()
    if rows.ndim != 2 or rows.shape[1] != RAW_FEATURE_SIZE:
        raise ValueError(f"Expected flat row matrix shape (N, {RAW_FEATURE_SIZE}), got {rows.shape}")

    landmarks = rows.reshape(-1, NUM_LANDMARKS, 3)
    normalized = normalize_landmark_batch(landmarks, center_index=feature_config.center_index)
    flat = normalized.reshape(rows.shape[0], -1)

    if not feature_config.include_engineered:
        return flat.astype(np.float32)

    engineered = compute_engineered_features_batch(normalized)
    return np.concatenate([flat, engineered], axis=1).astype(np.float32)


def infer_feature_dim(config: EngineeredFeatureConfig | None = None) -> int:
    feature_config = config or EngineeredFeatureConfig()
    return RAW_FEATURE_SIZE + (len(ENGINEERED_FEATURE_NAMES) if feature_config.include_engineered else 0)
