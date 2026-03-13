from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
import tensorflow as tf
from sklearn.metrics import classification_report, confusion_matrix, f1_score

from .config import (
    DEFAULT_AFFECTNET_DIR,
    DEFAULT_ARTIFACT_DIR,
    DEFAULT_BATCH_SIZE,
    DEFAULT_CLASSIFICATION_LEARNING_RATE,
    DEFAULT_EPOCHS,
    DEFAULT_FACE_LANDMARKER_TASK,
    DEFAULT_FEATURE_CONFIG_PATH,
    DEFAULT_LABEL_MAP_PATH,
    DEFAULT_MODEL_PATH,
    DEFAULT_PREPROCESSOR_PATH,
    DEFAULT_RANDOM_SEED,
    DEFAULT_RAF_DB_DIR,
    DEFAULT_SFEW_DIR,
)
from .dataset import (
    apply_standardizer,
    build_class_balanced_alpha,
    build_class_weight_map,
    build_tf_dataset,
    extract_landmark_dataset,
    fit_standardizer,
    load_dataset_frame,
    maybe_limit_frame,
    split_dataset_three_way,
)
from .features import EngineeredFeatureConfig, feature_config_to_dict
from .model import build_emotion_model
from .utils import ensure_dir, save_json


def configure_tensorflow_runtime() -> None:
    gpus = tf.config.list_physical_devices("GPU")
    try:
        tf.config.optimizer.set_jit(False)
    except Exception:
        pass
    for gpu in gpus:
        try:
            tf.config.experimental.set_memory_growth(gpu, True)
        except Exception:
            pass


class CosineAnnealingScheduler(tf.keras.callbacks.Callback):
    def __init__(self, initial_lr: float, min_lr: float, total_epochs: int) -> None:
        super().__init__()
        self.initial_lr = float(initial_lr)
        self.min_lr = float(min_lr)
        self.total_epochs = max(int(total_epochs), 1)

    def _compute_lr(self, epoch: int) -> float:
        cosine = 0.5 * (1.0 + math.cos(math.pi * epoch / self.total_epochs))
        return self.min_lr + (self.initial_lr - self.min_lr) * cosine

    def on_epoch_begin(self, epoch: int, logs=None) -> None:
        learning_rate = self._compute_lr(epoch)
        current_lr = self.model.optimizer.learning_rate
        if hasattr(current_lr, "assign"):
            current_lr.assign(learning_rate)
        else:
            self.model.optimizer.learning_rate = learning_rate
        print(f"Epoch {epoch + 1}: learning rate = {learning_rate:.8f}")


class LearningRateLogger(tf.keras.callbacks.Callback):
    def on_epoch_end(self, epoch: int, logs=None) -> None:
        learning_rate = float(tf.keras.backend.get_value(self.model.optimizer.learning_rate))
        print(f"Epoch {epoch + 1} ended with learning rate = {learning_rate:.8f}")


class DualMetricEarlyStopping(tf.keras.callbacks.Callback):
    def __init__(self, patience: int = 10, min_delta: float = 1e-4, restore_best_weights: bool = True) -> None:
        super().__init__()
        self.patience = int(patience)
        self.min_delta = float(min_delta)
        self.restore_best_weights = restore_best_weights
        self.wait = 0
        self.best_val_accuracy = float("-inf")
        self.best_val_loss = float("inf")
        self.best_weights = None

    def on_epoch_end(self, epoch: int, logs=None) -> None:
        logs = logs or {}
        val_accuracy = logs.get("val_accuracy")
        val_loss = logs.get("val_loss")
        if val_accuracy is None or val_loss is None:
            return

        accuracy_improved = val_accuracy > (self.best_val_accuracy + self.min_delta)
        loss_improved = val_loss < (self.best_val_loss - self.min_delta)

        if accuracy_improved:
            self.best_val_accuracy = float(val_accuracy)
        if loss_improved:
            self.best_val_loss = float(val_loss)

        if accuracy_improved or loss_improved:
            self.wait = 0
            if self.restore_best_weights:
                current_best_loss = logs.get("val_loss", float("inf"))
                should_store = self.best_weights is None or accuracy_improved or (
                    abs(float(val_accuracy) - self.best_val_accuracy) <= self.min_delta and current_best_loss <= self.best_val_loss
                )
                if should_store:
                    self.best_weights = self.model.get_weights()
        else:
            self.wait += 1
            if self.wait > self.patience:
                print(
                    f"Stopping early: neither val_accuracy nor val_loss improved for more than {self.patience} epochs."
                )
                self.model.stop_training = True
                if self.restore_best_weights and self.best_weights is not None:
                    self.model.set_weights(self.best_weights)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train a landmark-based emotion model from AffectNet, RAF-DB, and SFEW")
    parser.add_argument("--affectnet-dir", default=str(DEFAULT_AFFECTNET_DIR))
    parser.add_argument("--rafdb-dir", default=str(DEFAULT_RAF_DB_DIR))
    parser.add_argument("--sfew-dir", default=str(DEFAULT_SFEW_DIR))
    parser.add_argument("--face-landmarker-task", default=str(DEFAULT_FACE_LANDMARKER_TASK))
    parser.add_argument("--artifacts-dir", default=str(DEFAULT_ARTIFACT_DIR))
    parser.add_argument("--epochs", type=int, default=DEFAULT_EPOCHS)
    parser.add_argument("--batch-size", type=int, default=DEFAULT_BATCH_SIZE)
    parser.add_argument("--random-seed", type=int, default=DEFAULT_RANDOM_SEED)
    parser.add_argument("--max-rows", type=int, default=None)
    parser.add_argument("--validation-size", type=float, default=0.15)
    parser.add_argument("--test-size", type=float, default=0.15)
    parser.add_argument("--min-label-confidence", type=float, default=0.0)
    parser.add_argument("--learning-rate", type=float, default=DEFAULT_CLASSIFICATION_LEARNING_RATE)
    parser.add_argument("--min-learning-rate", type=float, default=1e-6)
    parser.add_argument("--focal-gamma", type=float, default=2.0)
    parser.add_argument("--class-balance-beta", type=float, default=0.9999)
    parser.add_argument("--no-engineered-features", action="store_true")
    parser.add_argument("--disable-cache", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    configure_tensorflow_runtime()
    tf.keras.utils.set_random_seed(args.random_seed)

    artifacts_dir = Path(args.artifacts_dir)
    ensure_dir(artifacts_dir)

    feature_config = EngineeredFeatureConfig(include_engineered=not args.no_engineered_features)

    print("Loading and merging AffectNet, RAF-DB, and SFEW manifests...")
    merged_split = load_dataset_frame(
        affectnet_dir=Path(args.affectnet_dir),
        rafdb_dir=Path(args.rafdb_dir),
        sfew_dir=Path(args.sfew_dir),
        min_label_confidence=args.min_label_confidence,
    )
    full_frame = maybe_limit_frame(merged_split.frame, args.max_rows, args.random_seed)
    train_frame, val_frame, test_frame = split_dataset_three_way(
        full_frame,
        validation_size=args.validation_size,
        test_size=args.test_size,
        random_seed=args.random_seed,
    )
    print(f"Train samples requested: {len(train_frame):,}")
    print(f"Validation samples requested: {len(val_frame):,}")
    print(f"Test samples requested: {len(test_frame):,}")

    label_to_id = {label: index for index, label in enumerate(merged_split.labels)}

    print("Extracting MediaPipe landmarks for train split...")
    train_dataset = extract_landmark_dataset(
        split_frame=train_frame,
        split_name="train",
        task_path=Path(args.face_landmarker_task),
        label_to_id=label_to_id,
        feature_config=feature_config,
        use_cache=not args.disable_cache,
    )
    print("Extracting MediaPipe landmarks for validation split...")
    val_dataset = extract_landmark_dataset(
        split_frame=val_frame,
        split_name="val",
        task_path=Path(args.face_landmarker_task),
        label_to_id=label_to_id,
        feature_config=feature_config,
        use_cache=not args.disable_cache,
    )
    print("Extracting MediaPipe landmarks for test split...")
    test_dataset = extract_landmark_dataset(
        split_frame=test_frame,
        split_name="test",
        task_path=Path(args.face_landmarker_task),
        label_to_id=label_to_id,
        feature_config=feature_config,
        use_cache=not args.disable_cache,
    )

    landmark_mean, landmark_std, engineered_mean, engineered_std = fit_standardizer(
        train_dataset.landmarks,
        train_dataset.engineered,
    )
    train_landmarks, train_engineered = apply_standardizer(
        train_dataset.landmarks,
        train_dataset.engineered,
        landmark_mean,
        landmark_std,
        engineered_mean,
        engineered_std,
    )
    val_landmarks, val_engineered = apply_standardizer(
        val_dataset.landmarks,
        val_dataset.engineered,
        landmark_mean,
        landmark_std,
        engineered_mean,
        engineered_std,
    )
    test_landmarks, test_engineered = apply_standardizer(
        test_dataset.landmarks,
        test_dataset.engineered,
        landmark_mean,
        landmark_std,
        engineered_mean,
        engineered_std,
    )

    print(f"Train samples kept after landmark extraction: {len(train_dataset.labels):,}")
    print(f"Validation samples kept after landmark extraction: {len(val_dataset.labels):,}")
    print(f"Test samples kept after landmark extraction: {len(test_dataset.labels):,}")

    class_weight_map = build_class_weight_map(train_dataset.labels, num_classes=len(merged_split.labels))
    print("Class weights:", {merged_split.labels[index]: round(weight, 4) for index, weight in class_weight_map.items()})
    focal_alpha = build_class_balanced_alpha(
        train_dataset.labels,
        num_classes=len(merged_split.labels),
        beta=args.class_balance_beta,
    )
    print("Class-balanced focal alpha:", {merged_split.labels[index]: round(weight, 4) for index, weight in enumerate(focal_alpha)})

    train_tf_dataset = build_tf_dataset(
        landmarks=train_landmarks,
        engineered=train_engineered,
        labels=train_dataset.labels,
        batch_size=args.batch_size,
        shuffle=True,
        num_classes=len(merged_split.labels),
    )
    val_tf_dataset = build_tf_dataset(
        landmarks=val_landmarks,
        engineered=val_engineered,
        labels=val_dataset.labels,
        batch_size=args.batch_size,
        shuffle=False,
        num_classes=len(merged_split.labels),
    )
    test_tf_dataset = build_tf_dataset(
        landmarks=test_landmarks,
        engineered=test_engineered,
        labels=test_dataset.labels,
        batch_size=args.batch_size,
        shuffle=False,
        num_classes=len(merged_split.labels),
    )

    model = build_emotion_model(
        num_classes=len(merged_split.labels),
        engineered_dim=train_engineered.shape[1],
        learning_rate=args.learning_rate,
        focal_alpha=focal_alpha,
        focal_gamma=args.focal_gamma,
    )
    callbacks = [
        CosineAnnealingScheduler(initial_lr=args.learning_rate, min_lr=args.min_learning_rate, total_epochs=args.epochs),
        LearningRateLogger(),
        DualMetricEarlyStopping(patience=10, restore_best_weights=True),
        tf.keras.callbacks.ModelCheckpoint(filepath=str(artifacts_dir / DEFAULT_MODEL_PATH.name), monitor="val_accuracy", mode="max", save_best_only=True),
    ]

    print("Training landmark encoder...")
    history = model.fit(
        train_tf_dataset,
        validation_data=val_tf_dataset,
        epochs=args.epochs,
        callbacks=callbacks,
        verbose=1,
    )

    val_probabilities = model.predict(val_tf_dataset, verbose=0)
    val_predicted_ids = np.argmax(val_probabilities, axis=1)
    probabilities = model.predict(test_tf_dataset, verbose=0)
    predicted_ids = np.argmax(probabilities, axis=1)
    label_ids = list(range(len(merged_split.labels)))
    val_macro_f1 = float(f1_score(val_dataset.labels, val_predicted_ids, labels=label_ids, average="macro", zero_division=0))
    test_macro_f1 = float(f1_score(test_dataset.labels, predicted_ids, labels=label_ids, average="macro", zero_division=0))
    validation_report = classification_report(
        val_dataset.labels,
        val_predicted_ids,
        labels=label_ids,
        target_names=merged_split.labels,
        output_dict=True,
        zero_division=0,
    )
    test_report = classification_report(
        test_dataset.labels,
        predicted_ids,
        labels=label_ids,
        target_names=merged_split.labels,
        output_dict=True,
        zero_division=0,
    )

    dataset_metrics = {}
    for dataset_name in sorted(set(test_dataset.dataset_names)):
        indices = [index for index, name in enumerate(test_dataset.dataset_names) if name == dataset_name]
        if not indices:
            continue
        dataset_true = test_dataset.labels[indices]
        dataset_pred = predicted_ids[indices]
        dataset_metrics[dataset_name] = {
            "samples": int(len(indices)),
            "macro_f1": float(f1_score(dataset_true, dataset_pred, labels=label_ids, average="macro", zero_division=0)),
            "classification_report": classification_report(
                dataset_true,
                dataset_pred,
                labels=label_ids,
                target_names=merged_split.labels,
                output_dict=True,
                zero_division=0,
            ),
        }

    metrics_payload = {
        "validation_classification_report": validation_report,
        "validation_confusion_matrix": confusion_matrix(val_dataset.labels, val_predicted_ids, labels=label_ids).tolist(),
        "validation_macro_f1": val_macro_f1,
        "validation_per_class_recall": {
            label: float(validation_report[label]["recall"])
            for label in merged_split.labels
        },
        "classification_report": test_report,
        "confusion_matrix": confusion_matrix(test_dataset.labels, predicted_ids, labels=label_ids).tolist(),
        "normalized_confusion_matrix": confusion_matrix(
            test_dataset.labels,
            predicted_ids,
            labels=label_ids,
            normalize="true",
        ).tolist(),
        "test_macro_f1": test_macro_f1,
        "train_samples": int(len(train_dataset.labels)),
        "validation_samples": int(len(val_dataset.labels)),
        "test_samples": int(len(test_dataset.labels)),
        "learning_rate": float(args.learning_rate),
        "min_learning_rate": float(args.min_learning_rate),
        "focal_gamma": float(args.focal_gamma),
        "class_balance_beta": float(args.class_balance_beta),
        "focal_alpha": focal_alpha,
        "labels": merged_split.labels,
        "dataset_metrics": dataset_metrics,
    }

    np.savez(
        artifacts_dir / DEFAULT_PREPROCESSOR_PATH.name,
        landmark_mean=landmark_mean,
        landmark_std=landmark_std,
        engineered_mean=engineered_mean,
        engineered_std=engineered_std,
    )
    save_json(artifacts_dir / DEFAULT_LABEL_MAP_PATH.name, {str(index): label for index, label in enumerate(merged_split.labels)})
    save_json(artifacts_dir / DEFAULT_FEATURE_CONFIG_PATH.name, feature_config_to_dict(feature_config))
    save_json(
        artifacts_dir / "training_config.json",
        {
            "architecture": "region_aware_landmark_conv_attention_encoder",
            "input_shape": [478, 3],
            "engineered_dim": int(train_engineered.shape[1]),
            "labels": merged_split.labels,
            "datasets": ["AffectNet", "RAF-DB", "SFEW"],
            "learning_rate": args.learning_rate,
            "min_learning_rate": args.min_learning_rate,
            "focal_gamma": args.focal_gamma,
            "class_balance_beta": args.class_balance_beta,
            "validation_size": args.validation_size,
            "test_size": args.test_size,
            "split_strategy": "merged_stratified_70_15_15",
            "imbalance_strategy": "class_balanced_focal_loss",
            "label_space": "7_class_shared",
        },
    )
    save_json(artifacts_dir / "metrics.json", metrics_payload)
    save_json(artifacts_dir / "history.json", {key: [float(value) for value in values] for key, values in history.history.items()})

    print(f"Validation macro F1: {val_macro_f1:.4f}")
    print(f"Test macro F1: {test_macro_f1:.4f}")
    for dataset_name, payload in dataset_metrics.items():
        print(f"{dataset_name} test macro F1: {payload['macro_f1']:.4f} ({payload['samples']} samples)")
    print("Test classification report:")
    print(classification_report(test_dataset.labels, predicted_ids, labels=label_ids, target_names=merged_split.labels, zero_division=0))
    print("Artifacts written to", artifacts_dir)


if __name__ == "__main__":
    main()
