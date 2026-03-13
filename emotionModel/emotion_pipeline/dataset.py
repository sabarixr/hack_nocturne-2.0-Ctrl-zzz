from __future__ import annotations

import hashlib
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

import cv2
import mediapipe as mp
import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.model_selection import train_test_split

from .config import (
    CLASSIFICATION_LABELS,
    DEFAULT_AFFECTNET_DIR,
    DEFAULT_DATA_DIR,
    DEFAULT_RAF_DB_DIR,
    DEFAULT_SFEW_DIR,
    LABEL_ALIASES,
    NUM_LANDMARKS,
    RAF_DB_LABEL_MAP,
)
from .features import EngineeredFeatureConfig, compute_engineered_features, feature_config_to_dict, normalize_landmarks, region_indices


IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}

BaseOptions = mp.tasks.BaseOptions
FaceLandmarker = mp.tasks.vision.FaceLandmarker
FaceLandmarkerOptions = mp.tasks.vision.FaceLandmarkerOptions
RunningMode = mp.tasks.vision.RunningMode


@dataclass
class DatasetSplit:
    frame: pd.DataFrame
    labels: list[str]
    name: str


@dataclass
class LandmarkDataset:
    landmarks: np.ndarray
    engineered: np.ndarray
    labels: np.ndarray
    paths: list[str]
    dataset_names: list[str]


def normalize_label(label: str) -> str:
    normalized = str(label).strip().lower()
    if normalized not in LABEL_ALIASES:
        raise ValueError(f"Unsupported label '{label}' found in dataset labels")
    return LABEL_ALIASES[normalized]


def normalize_label_or_none(label: str) -> str | None:
    normalized = str(label).strip().lower()
    if normalized == "contempt":
        return None
    if normalized not in LABEL_ALIASES:
        raise ValueError(f"Unsupported label '{label}' found in dataset labels")
    mapped = LABEL_ALIASES[normalized]
    return mapped if mapped in CLASSIFICATION_LABELS else None


def iter_image_files(root: Path) -> Iterator[Path]:
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS:
            yield path


def maybe_limit_frame(frame: pd.DataFrame, max_rows: int | None, random_seed: int) -> pd.DataFrame:
    if max_rows is None or max_rows <= 0 or len(frame) <= max_rows:
        return frame.reset_index(drop=True)
    print(f"Sampling {max_rows:,} rows from {len(frame):,} rows")
    return frame.sample(n=max_rows, random_state=random_seed).reset_index(drop=True)


def build_affectnet_frame(affectnet_dir: Path, min_label_confidence: float = 0.0) -> pd.DataFrame:
    labels_csv = affectnet_dir / "labels.csv"
    frame = pd.read_csv(labels_csv)
    frame["pth_key"] = frame["pth"].astype(str).str.replace("\\", "/", regex=False).str.lower().str.strip()
    frame["target_label"] = frame["label"].map(normalize_label_or_none)
    frame = frame[frame["target_label"].notna()].copy()
    if "relFCs" in frame.columns:
        frame["relFCs"] = pd.to_numeric(frame["relFCs"], errors="coerce").fillna(0.0)
        frame = frame[frame["relFCs"] >= float(min_label_confidence)].copy()
    labels_lookup = frame.drop_duplicates(subset=["pth_key"], keep="last").set_index("pth_key")

    rows: list[dict[str, object]] = []
    missing_labels = 0
    for split_name in ["Train", "Test"]:
        split_dir = affectnet_dir / split_name
        for image_path in iter_image_files(split_dir):
            relative_path = image_path.relative_to(split_dir).as_posix()
            key = relative_path.lower()
            if key not in labels_lookup.index:
                missing_labels += 1
                continue
            label_row = labels_lookup.loc[key]
            rows.append(
                {
                    "image_path": str(image_path),
                    "relative_path": f"AffectNet/{split_name}/{relative_path}",
                    "target_label": str(label_row["target_label"]),
                    "dataset_name": "AffectNet",
                    "source_split": split_name.lower(),
                }
            )

    merged = pd.DataFrame(rows)
    print(f"AffectNet: found {len(merged):,} usable labeled images")
    if missing_labels:
        print(f"AffectNet: skipped {missing_labels:,} images without matching labels.csv rows")
    return merged


def build_rafdb_frame(rafdb_dir: Path) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for split_name, labels_file in [("train", rafdb_dir / "train_labels.csv"), ("test", rafdb_dir / "test_labels.csv")]:
        labels = pd.read_csv(labels_file)
        for row in labels.itertuples(index=False):
            label_id = int(row.label)
            if label_id not in RAF_DB_LABEL_MAP:
                continue
            class_name = RAF_DB_LABEL_MAP[label_id]
            image_path = rafdb_dir / "DATASET" / split_name / str(label_id) / str(row.image)
            if not image_path.exists():
                continue
            rows.append(
                {
                    "image_path": str(image_path),
                    "relative_path": f"RAF-DB/{split_name}/{label_id}/{row.image}",
                    "target_label": class_name,
                    "dataset_name": "RAF-DB",
                    "source_split": split_name,
                }
            )
    merged = pd.DataFrame(rows)
    print(f"RAF-DB: found {len(merged):,} usable labeled images")
    return merged


def build_sfew_frame(sfew_dir: Path) -> pd.DataFrame:
    labels_csv = sfew_dir / "sfew_labels.csv"
    rows: list[dict[str, object]] = []

    if labels_csv.exists():
        labels_frame = pd.read_csv(labels_csv)
        if "image_file_name" not in labels_frame.columns or "label" not in labels_frame.columns:
            raise ValueError("SFEW/sfew_labels.csv must contain 'image_file_name' and 'label'")

        train_dir = sfew_dir / "Train"
        flat_images = {path.name: path for path in iter_image_files(train_dir)}
        nested_images = {path.relative_to(sfew_dir).as_posix().lower(): path for path in iter_image_files(train_dir)}

        missing = 0
        for row in labels_frame.itertuples(index=False):
            label = normalize_label(row.label)
            if label not in CLASSIFICATION_LABELS:
                continue

            rel_path = str(row.image_file_name).replace("\\", "/").strip()
            image_path = nested_images.get(rel_path.lower())
            if image_path is None:
                image_path = flat_images.get(Path(rel_path).name)
            if image_path is None or not image_path.exists():
                missing += 1
                continue

            rows.append(
                {
                    "image_path": str(image_path),
                    "relative_path": f"SFEW/{image_path.relative_to(sfew_dir).as_posix()}",
                    "target_label": label,
                    "dataset_name": "SFEW",
                    "source_split": "train",
                }
            )

        merged = pd.DataFrame(rows).drop_duplicates(subset=["relative_path"], keep="last")
        print(f"SFEW: found {len(merged):,} usable labeled images from sfew_labels.csv")
        if missing:
            print(f"SFEW: skipped {missing:,} labeled rows without matching files")
        return merged

    for split_name in ["Train", "Val"]:
        split_dir = sfew_dir / split_name
        if not split_dir.exists():
            continue
        for class_dir in sorted(split_dir.iterdir()):
            if not class_dir.is_dir():
                continue
            label = normalize_label(class_dir.name)
            if label not in CLASSIFICATION_LABELS:
                continue
            for image_path in iter_image_files(class_dir):
                rows.append(
                    {
                        "image_path": str(image_path),
                        "relative_path": f"SFEW/{split_name}/{class_dir.name}/{image_path.name}",
                        "target_label": label,
                        "dataset_name": "SFEW",
                        "source_split": split_name.lower(),
                    }
                )

    merged = pd.DataFrame(rows)
    print(f"SFEW: found {len(merged):,} usable labeled images")
    return merged


def load_dataset_frame(
    affectnet_dir: Path = DEFAULT_AFFECTNET_DIR,
    rafdb_dir: Path = DEFAULT_RAF_DB_DIR,
    sfew_dir: Path = DEFAULT_SFEW_DIR,
    min_label_confidence: float = 0.0,
) -> DatasetSplit:
    affectnet_frame = build_affectnet_frame(Path(affectnet_dir), min_label_confidence=min_label_confidence)
    rafdb_frame = build_rafdb_frame(Path(rafdb_dir))
    sfew_frame = build_sfew_frame(Path(sfew_dir))
    merged_frame = pd.concat([affectnet_frame, rafdb_frame, sfew_frame], ignore_index=True)
    if merged_frame.empty:
        raise ValueError("No usable labeled images were found across AffectNet, RAF-DB, and SFEW")
    print("Merged dataset counts by source:")
    print(merged_frame["dataset_name"].value_counts().to_string())
    return DatasetSplit(merged_frame.reset_index(drop=True), CLASSIFICATION_LABELS, "merged_multi_dataset")


def split_dataset_three_way(
    full_frame: pd.DataFrame,
    validation_size: float,
    test_size: float,
    random_seed: int,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    train_part, temp_part = train_test_split(
        full_frame,
        test_size=validation_size + test_size,
        random_state=random_seed,
        stratify=full_frame["target_label"],
    )
    relative_test_size = test_size / (validation_size + test_size)
    val_part, test_part = train_test_split(
        temp_part,
        test_size=relative_test_size,
        random_state=random_seed,
        stratify=temp_part["target_label"],
    )
    return train_part.reset_index(drop=True), val_part.reset_index(drop=True), test_part.reset_index(drop=True)


def build_class_weight_map(train_labels: np.ndarray, num_classes: int) -> dict[int, float]:
    counts = np.bincount(train_labels, minlength=num_classes)
    total = float(train_labels.shape[0])
    weights: dict[int, float] = {}
    for class_index in range(num_classes):
        class_count = float(counts[class_index])
        weights[class_index] = 0.0 if class_count == 0 else total / (num_classes * class_count)
    return weights


def build_class_balanced_alpha(train_labels: np.ndarray, num_classes: int, beta: float = 0.9999) -> list[float]:
    counts = np.bincount(train_labels, minlength=num_classes).astype(np.float32)
    effective_num = 1.0 - np.power(beta, counts)
    alpha = (1.0 - beta) / np.maximum(effective_num, 1e-8)
    alpha = np.where(counts > 0, alpha, 0.0)
    alpha = alpha / np.maximum(alpha.sum(), 1e-8)
    alpha = alpha * num_classes
    return alpha.astype(np.float32).tolist()


def fit_standardizer(landmarks: np.ndarray, engineered: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    landmark_mean = landmarks.mean(axis=0).astype(np.float32)
    landmark_std = landmarks.std(axis=0).astype(np.float32)
    landmark_std = np.where(landmark_std < 1e-6, 1.0, landmark_std).astype(np.float32)
    engineered_mean = engineered.mean(axis=0).astype(np.float32)
    engineered_std = engineered.std(axis=0).astype(np.float32)
    engineered_std = np.where(engineered_std < 1e-6, 1.0, engineered_std).astype(np.float32)
    return landmark_mean, landmark_std, engineered_mean, engineered_std


def apply_standardizer(
    landmarks: np.ndarray,
    engineered: np.ndarray,
    landmark_mean: np.ndarray,
    landmark_std: np.ndarray,
    engineered_mean: np.ndarray,
    engineered_std: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    standardized_landmarks = ((landmarks - landmark_mean) / landmark_std).astype(np.float32)
    standardized_engineered = ((engineered - engineered_mean) / engineered_std).astype(np.float32)
    return standardized_landmarks, standardized_engineered


def build_tf_dataset(
    landmarks: np.ndarray,
    engineered: np.ndarray,
    labels: np.ndarray,
    batch_size: int,
    shuffle: bool = False,
    num_classes: int | None = None,
) -> tf.data.Dataset:
    regions = region_indices()
    inputs = {
        "landmarks": landmarks.astype(np.float32),
        "engineered_features": engineered.astype(np.float32),
        "left_eye_brow": landmarks[:, regions["left_eye_brow"], :].astype(np.float32),
        "right_eye_brow": landmarks[:, regions["right_eye_brow"], :].astype(np.float32),
        "mouth": landmarks[:, regions["mouth"], :].astype(np.float32),
        "nose": landmarks[:, regions["nose"], :].astype(np.float32),
    }
    targets = labels.astype(np.int32)
    if num_classes is not None:
        targets = tf.keras.utils.to_categorical(targets, num_classes=num_classes).astype(np.float32)
    dataset = tf.data.Dataset.from_tensor_slices((inputs, targets))
    if shuffle:
        dataset = dataset.shuffle(buffer_size=min(len(labels), 4096), reshuffle_each_iteration=True)
    dataset = dataset.batch(batch_size)
    dataset = dataset.prefetch(tf.data.AUTOTUNE)
    return dataset


def create_face_landmarker(task_path: Path) -> FaceLandmarker:
    options = FaceLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=str(task_path)),
        running_mode=RunningMode.IMAGE,
        num_faces=1,
    )
    return FaceLandmarker.create_from_options(options)


def extract_landmarks_from_image(landmarker: FaceLandmarker, image_path: Path) -> np.ndarray | None:
    frame_bgr = cv2.imread(str(image_path))
    if frame_bgr is None:
        return None
    frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame_rgb)
    result = landmarker.detect(mp_image)
    if not result.face_landmarks:
        return None
    face = result.face_landmarks[0]
    if len(face) != NUM_LANDMARKS:
        return None
    return np.asarray([[point.x, point.y, point.z] for point in face], dtype=np.float32)


def _cache_path(split_name: str, feature_config: EngineeredFeatureConfig, split_frame: pd.DataFrame, task_path: Path) -> Path:
    frame_signature = "|".join(split_frame["relative_path"].astype(str).tolist())
    signature = hashlib.md5(
        (
            split_name
            + frame_signature
            + str(task_path.resolve())
            + str(feature_config.include_engineered)
            + str(feature_config.center_index)
        ).encode("utf-8")
    ).hexdigest()[:12]
    cache_dir = DEFAULT_DATA_DIR / "landmark_cache"
    cache_dir.mkdir(parents=True, exist_ok=True)
    return cache_dir / f"{split_name}_{signature}.npz"


def extract_landmark_dataset(
    split_frame: pd.DataFrame,
    split_name: str,
    task_path: Path,
    label_to_id: dict[str, int],
    feature_config: EngineeredFeatureConfig,
    use_cache: bool = True,
) -> LandmarkDataset:
    cache_path = _cache_path(split_name, feature_config, split_frame, task_path)
    if use_cache and cache_path.exists():
        cached = np.load(cache_path, allow_pickle=True)
        print(f"Using cached landmarks for {split_name}: {cache_path}")
        return LandmarkDataset(
            landmarks=cached["landmarks"].astype(np.float32),
            engineered=cached["engineered"].astype(np.float32),
            labels=cached["labels"].astype(np.int32),
            paths=cached["paths"].tolist(),
            dataset_names=cached["dataset_names"].tolist(),
        )

    all_landmarks: list[np.ndarray] = []
    all_engineered: list[np.ndarray] = []
    all_labels: list[int] = []
    all_paths: list[str] = []
    all_dataset_names: list[str] = []
    skipped = 0

    with create_face_landmarker(task_path) as landmarker:
        total_rows = len(split_frame)
        for row_index, row in enumerate(split_frame.itertuples(index=False), start=1):
            landmarks = extract_landmarks_from_image(landmarker, Path(row.image_path))
            if landmarks is None:
                skipped += 1
                continue

            normalized = normalize_landmarks(landmarks, center_index=feature_config.center_index)
            engineered = compute_engineered_features(normalized) if feature_config.include_engineered else np.zeros(0, dtype=np.float32)
            all_landmarks.append(normalized.astype(np.float32))
            all_engineered.append(engineered.astype(np.float32))
            all_labels.append(label_to_id[row.target_label])
            all_paths.append(row.relative_path)
            all_dataset_names.append(row.dataset_name)

            if row_index % 250 == 0 or row_index == total_rows:
                print(f"{split_name}: processed {row_index:,}/{total_rows:,} images, skipped {skipped:,}")

    if not all_landmarks:
        raise ValueError(f"No landmarks extracted for split '{split_name}'")

    landmarks_array = np.stack(all_landmarks).astype(np.float32)
    engineered_array = np.stack(all_engineered).astype(np.float32)
    labels_array = np.asarray(all_labels, dtype=np.int32)
    dataset_names_array = np.asarray(all_dataset_names, dtype=object)

    if use_cache:
        np.savez_compressed(
            cache_path,
            landmarks=landmarks_array,
            engineered=engineered_array,
            labels=labels_array,
            paths=np.asarray(all_paths, dtype=object),
            dataset_names=dataset_names_array,
            feature_config=np.asarray(feature_config_to_dict(feature_config), dtype=object),
        )
        print(f"Saved {split_name} landmark cache to {cache_path}")

    return LandmarkDataset(
        landmarks=landmarks_array,
        engineered=engineered_array,
        labels=labels_array,
        paths=all_paths,
        dataset_names=all_dataset_names,
    )
