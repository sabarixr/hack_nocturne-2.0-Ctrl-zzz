"""
Training pipeline for ISL gesture recognition.

Two split modes:
  1. LOSO (Leave-One-Subject-Out):
     - Group by subject ID extracted from filenames
     - Augmented variants stay with their source subject (no leakage)
     - Reports per-fold accuracy + mean/std across folds

  2. Stratified (80/20 split):
     - Augmented variants grouped with source video (GroupShuffleSplit)
     - Single train/val split, suitable for quick iteration

Usage:
    python train.py --mode stratified    # quick 80/20 split (default)
    python train.py --mode loso          # full LOSO cross-validation
    python train.py --model light        # use LightBiLSTM instead
"""

import os
import re
import sys
import time
import argparse
import csv

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from sklearn.model_selection import GroupShuffleSplit
from sklearn.utils.class_weight import compute_class_weight
from collections import Counter

from config import (
    LANDMARKS_FILE,
    BEST_MODEL_PATH,
    TRAINING_LOG,
    CLASSES,
    NUM_CLASSES,
    BATCH_SIZE,
    MAX_EPOCHS,
    LEARNING_RATE,
    WEIGHT_DECAY,
    COSINE_T_MAX,
    COSINE_ETA_MIN,
    EARLY_STOP_PATIENCE,
    RANDOM_SEED,
    BASE_DIR,
)
from model import BiLSTMAttention, LightBiLSTM, count_parameters
from augmentation import LandmarkDataset


# ---------------------------------------------------------------------------
# Reproducibility
# ---------------------------------------------------------------------------

def seed_everything(seed: int = RANDOM_SEED) -> None:
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    torch.backends.cudnn.deterministic = True
    torch.backends.cudnn.benchmark = False


# ---------------------------------------------------------------------------
# Subject / group extraction
# ---------------------------------------------------------------------------
SUBJECT_PATTERN = re.compile(r"_Crop_(\d{3})_")


def extract_subject_from_filename(fname: str) -> str:
    """Extract 3-digit subject ID, e.g. '001' from 'accident_Crop_001_02_hflip.avi'."""
    m = SUBJECT_PATTERN.search(fname)
    return m.group(1) if m else "unknown"


def build_groups(filenames: np.ndarray, subjects: np.ndarray) -> np.ndarray:
    """
    Build group IDs that keep augmented variants together with their source.
    Group key = subject_ID (for LOSO) or subject_ID + base_video (for stratified).
    """
    return subjects  # subject IDs already work for LOSO grouping


def build_video_groups(filenames: np.ndarray) -> np.ndarray:
    """
    For stratified split: group by original video (strip augmentation suffix).
    e.g. 'accident_Crop_001_02_hflip.avi' → 'accident_Crop_001_02'
    This ensures augmented variants never leak across train/val.
    """
    groups = []
    aug_suffixes = re.compile(r"_(hflip|vflip|rotp\d+|rotn\d+|bright|dark|slow|fast)\b")
    for fname in filenames:
        base = os.path.splitext(str(fname))[0]
        base = aug_suffixes.sub("", base)
        groups.append(base)
    return np.array(groups)


# ---------------------------------------------------------------------------
# Class weights
# ---------------------------------------------------------------------------

def compute_weights(y: np.ndarray, device: torch.device) -> torch.Tensor:
    """Compute inverse-frequency class weights for CrossEntropyLoss."""
    classes_present = np.unique(y)
    weights = compute_class_weight("balanced", classes=classes_present, y=y)
    # Fill full weight vector (in case a class is missing)
    full_weights = np.ones(NUM_CLASSES, dtype=np.float32)
    for cls_idx, w in zip(classes_present, weights):
        full_weights[cls_idx] = w
    return torch.tensor(full_weights, dtype=torch.float32).to(device)


# ---------------------------------------------------------------------------
# Training + evaluation loops
# ---------------------------------------------------------------------------

def train_one_epoch(
    model: nn.Module,
    loader: DataLoader,
    criterion: nn.Module,
    optimizer: torch.optim.Optimizer,
    device: torch.device,
) -> tuple[float, float]:
    model.train()
    total_loss = 0.0
    correct = 0
    total = 0

    for X_batch, y_batch in loader:
        X_batch = X_batch.to(device)
        y_batch = y_batch.to(device)

        optimizer.zero_grad()
        logits = model(X_batch)
        loss = criterion(logits, y_batch)
        loss.backward()
        optimizer.step()

        total_loss += loss.item() * y_batch.size(0)
        preds = logits.argmax(dim=1)
        correct += (preds == y_batch).sum().item()
        total += y_batch.size(0)

    avg_loss = total_loss / max(total, 1)
    accuracy = correct / max(total, 1)
    return avg_loss, accuracy


@torch.no_grad()
def evaluate(
    model: nn.Module,
    loader: DataLoader,
    criterion: nn.Module,
    device: torch.device,
) -> tuple[float, float, np.ndarray, np.ndarray]:
    model.eval()
    total_loss = 0.0
    correct = 0
    total = 0
    all_preds = []
    all_labels = []

    for X_batch, y_batch in loader:
        X_batch = X_batch.to(device)
        y_batch = y_batch.to(device)

        logits = model(X_batch)
        loss = criterion(logits, y_batch)

        total_loss += loss.item() * y_batch.size(0)
        preds = logits.argmax(dim=1)
        correct += (preds == y_batch).sum().item()
        total += y_batch.size(0)
        all_preds.extend(preds.cpu().numpy())
        all_labels.extend(y_batch.cpu().numpy())

    avg_loss = total_loss / max(total, 1)
    accuracy = correct / max(total, 1)
    return avg_loss, accuracy, np.array(all_preds), np.array(all_labels)


# ---------------------------------------------------------------------------
# Early stopping
# ---------------------------------------------------------------------------

class EarlyStopping:
    def __init__(self, patience: int = EARLY_STOP_PATIENCE):
        self.patience = patience
        self.best_loss = float("inf")
        self.counter = 0
        self.best_state = None

    def step(self, val_loss: float, model: nn.Module) -> bool:
        """Returns True if training should stop."""
        if val_loss < self.best_loss:
            self.best_loss = val_loss
            self.counter = 0
            self.best_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}
            return False
        self.counter += 1
        return self.counter >= self.patience


# ---------------------------------------------------------------------------
# Plotting helpers
# ---------------------------------------------------------------------------

def save_confusion_matrix(y_true: np.ndarray, y_pred: np.ndarray, path: str) -> None:
    """Save a confusion matrix heatmap."""
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from sklearn.metrics import confusion_matrix, ConfusionMatrixDisplay
    except ImportError:
        print("  [WARN] matplotlib/sklearn not available, skipping confusion matrix plot")
        return

    cm = confusion_matrix(y_true, y_pred, labels=list(range(NUM_CLASSES)))
    disp = ConfusionMatrixDisplay(cm, display_labels=CLASSES)
    fig, ax = plt.subplots(figsize=(10, 8))
    disp.plot(ax=ax, cmap="Blues", values_format="d")
    ax.set_title("Confusion Matrix")
    plt.xticks(rotation=45, ha="right")
    plt.tight_layout()
    plt.savefig(path, dpi=150)
    plt.close()
    print(f"  Saved: {path}")


def save_training_curves(log: list[dict], path: str) -> None:
    """Save loss and accuracy curves."""
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("  [WARN] matplotlib not available, skipping training curves plot")
        return

    epochs = [r["epoch"] for r in log]
    train_loss = [r["train_loss"] for r in log]
    val_loss = [r["val_loss"] for r in log]
    train_acc = [r["train_acc"] for r in log]
    val_acc = [r["val_acc"] for r in log]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))

    ax1.plot(epochs, train_loss, label="Train Loss")
    ax1.plot(epochs, val_loss, label="Val Loss")
    ax1.set_xlabel("Epoch")
    ax1.set_ylabel("Loss")
    ax1.set_title("Loss Curves")
    ax1.legend()
    ax1.grid(True, alpha=0.3)

    ax2.plot(epochs, train_acc, label="Train Acc")
    ax2.plot(epochs, val_acc, label="Val Acc")
    ax2.set_xlabel("Epoch")
    ax2.set_ylabel("Accuracy")
    ax2.set_title("Accuracy Curves")
    ax2.legend()
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(path, dpi=150)
    plt.close()
    print(f"  Saved: {path}")


# ---------------------------------------------------------------------------
# Stratified split training
# ---------------------------------------------------------------------------

def train_stratified(X, y, subjects, filenames, model_type: str) -> None:
    seed_everything()
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"  Device: {device}")

    # Group by original video to prevent augmented leakage
    video_groups = build_video_groups(filenames)

    gss = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=RANDOM_SEED)
    train_idx, val_idx = next(gss.split(X, y, groups=video_groups))

    print(f"  Train: {len(train_idx)} samples")
    print(f"  Val:   {len(val_idx)} samples")

    # Print class distribution
    train_counts = Counter(y[train_idx])
    val_counts = Counter(y[val_idx])
    print(f"  Train class dist: { {CLASSES[k]: v for k, v in sorted(train_counts.items())} }")
    print(f"  Val   class dist: { {CLASSES[k]: v for k, v in sorted(val_counts.items())} }")

    train_ds = LandmarkDataset(X[train_idx], y[train_idx], augment=True)
    val_ds = LandmarkDataset(X[val_idx], y[val_idx], augment=False)

    train_loader = DataLoader(train_ds, batch_size=BATCH_SIZE, shuffle=True, drop_last=False)
    val_loader = DataLoader(val_ds, batch_size=BATCH_SIZE, shuffle=False)

    # Model
    if model_type == "light":
        model = LightBiLSTM().to(device)
    else:
        model = BiLSTMAttention().to(device)
    print(f"  Model: {model.__class__.__name__}  params: {count_parameters(model):,}")

    # Class weights + loss
    class_weights = compute_weights(y[train_idx], device)
    criterion = nn.CrossEntropyLoss(weight=class_weights)

    # Optimizer + scheduler
    optimizer = torch.optim.AdamW(model.parameters(), lr=LEARNING_RATE, weight_decay=WEIGHT_DECAY)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
        optimizer, T_max=COSINE_T_MAX, eta_min=COSINE_ETA_MIN
    )

    early_stop = EarlyStopping(patience=EARLY_STOP_PATIENCE)
    training_log = []

    print(f"\n{'Epoch':>5} {'TrainLoss':>10} {'TrainAcc':>9} {'ValLoss':>10} {'ValAcc':>9} {'LR':>10}")
    print("-" * 58)

    for epoch in range(1, MAX_EPOCHS + 1):
        train_loss, train_acc = train_one_epoch(model, train_loader, criterion, optimizer, device)
        val_loss, val_acc, val_preds, val_labels = evaluate(model, val_loader, criterion, device)
        scheduler.step()

        lr = optimizer.param_groups[0]["lr"]
        print(f"{epoch:5d} {train_loss:10.4f} {train_acc:9.4f} {val_loss:10.4f} {val_acc:9.4f} {lr:10.6f}")

        training_log.append({
            "epoch": epoch,
            "train_loss": round(train_loss, 5),
            "train_acc": round(train_acc, 5),
            "val_loss": round(val_loss, 5),
            "val_acc": round(val_acc, 5),
            "lr": round(lr, 8),
        })

        if early_stop.step(val_loss, model):
            print(f"\n  Early stopping at epoch {epoch} (patience={EARLY_STOP_PATIENCE})")
            break

    # Restore best model
    if early_stop.best_state is not None:
        model.load_state_dict(early_stop.best_state)

    # Final evaluation
    val_loss, val_acc, val_preds, val_labels = evaluate(model, val_loader, criterion, device)
    print(f"\n  Best val loss: {early_stop.best_loss:.4f}")
    print(f"  Best val acc:  {val_acc:.4f}")

    # Save model
    torch.save({
        "model_state_dict": model.state_dict(),
        "model_class": model.__class__.__name__,
        "val_acc": val_acc,
        "val_loss": early_stop.best_loss,
        "classes": CLASSES,
        "num_classes": NUM_CLASSES,
    }, BEST_MODEL_PATH)
    print(f"  Saved: {BEST_MODEL_PATH}")

    # Save training log CSV
    with open(TRAINING_LOG, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["epoch", "train_loss", "train_acc", "val_loss", "val_acc", "lr"])
        writer.writeheader()
        writer.writerows(training_log)
    print(f"  Saved: {TRAINING_LOG}")

    # Save plots
    cm_path = os.path.join(BASE_DIR, "confusion_matrix.png")
    curves_path = os.path.join(BASE_DIR, "training_curves.png")
    save_confusion_matrix(val_labels, val_preds, cm_path)
    save_training_curves(training_log, curves_path)


# ---------------------------------------------------------------------------
# LOSO cross-validation
# ---------------------------------------------------------------------------

def train_loso(X, y, subjects, filenames, model_type: str) -> None:
    seed_everything()
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"  Device: {device}")

    unique_subjects = sorted(set(subjects))
    print(f"  Unique subjects: {len(unique_subjects)}")
    print(f"  Subjects: {unique_subjects}")

    fold_results = []
    all_val_preds = []
    all_val_labels = []
    all_training_logs = []

    for fold_idx, held_out in enumerate(unique_subjects):
        print(f"\n{'=' * 50}")
        print(f"  LOSO Fold {fold_idx + 1}/{len(unique_subjects)} — held out subject: {held_out}")
        print(f"{'=' * 50}")

        seed_everything()  # reset seed each fold for reproducibility

        val_mask = subjects == held_out
        train_mask = ~val_mask

        if val_mask.sum() == 0:
            print(f"  [WARN] No samples for subject {held_out}, skipping")
            continue

        X_train, y_train = X[train_mask], y[train_mask]
        X_val, y_val = X[val_mask], y[val_mask]

        print(f"  Train: {len(X_train)}, Val: {len(X_val)}")

        train_ds = LandmarkDataset(X_train, y_train, augment=True)
        val_ds = LandmarkDataset(X_val, y_val, augment=False)

        train_loader = DataLoader(train_ds, batch_size=BATCH_SIZE, shuffle=True)
        val_loader = DataLoader(val_ds, batch_size=BATCH_SIZE, shuffle=False)

        # Fresh model each fold
        if model_type == "light":
            model = LightBiLSTM().to(device)
        else:
            model = BiLSTMAttention().to(device)

        class_weights = compute_weights(y_train, device)
        criterion = nn.CrossEntropyLoss(weight=class_weights)
        optimizer = torch.optim.AdamW(model.parameters(), lr=LEARNING_RATE, weight_decay=WEIGHT_DECAY)
        scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
            optimizer, T_max=COSINE_T_MAX, eta_min=COSINE_ETA_MIN
        )
        early_stop = EarlyStopping(patience=EARLY_STOP_PATIENCE)

        for epoch in range(1, MAX_EPOCHS + 1):
            train_loss, train_acc = train_one_epoch(model, train_loader, criterion, optimizer, device)
            val_loss, val_acc, _, _ = evaluate(model, val_loader, criterion, device)
            scheduler.step()

            if epoch % 10 == 0 or epoch == 1:
                print(f"    Epoch {epoch:3d}: train_acc={train_acc:.3f} val_acc={val_acc:.3f}")

            if early_stop.step(val_loss, model):
                print(f"    Early stop at epoch {epoch}")
                break

        # Restore best and evaluate
        if early_stop.best_state is not None:
            model.load_state_dict(early_stop.best_state)

        val_loss, val_acc, val_preds, val_labels = evaluate(model, val_loader, criterion, device)
        print(f"  Fold {fold_idx + 1} — Subject {held_out}: val_acc = {val_acc:.4f}")

        fold_results.append({"subject": held_out, "val_acc": val_acc, "val_loss": val_loss, "n_val": len(X_val)})
        all_val_preds.extend(val_preds)
        all_val_labels.extend(val_labels)

    # Summary
    accs = [r["val_acc"] for r in fold_results]
    print(f"\n{'=' * 50}")
    print(f"  LOSO Results ({len(fold_results)} folds)")
    print(f"  Mean accuracy: {np.mean(accs):.4f} ± {np.std(accs):.4f}")
    print(f"  Min: {np.min(accs):.4f}  Max: {np.max(accs):.4f}")

    for r in fold_results:
        print(f"    Subject {r['subject']}: acc={r['val_acc']:.4f}  n={r['n_val']}")

    # Overall confusion matrix
    cm_path = os.path.join(BASE_DIR, "confusion_matrix_loso.png")
    save_confusion_matrix(np.array(all_val_labels), np.array(all_val_preds), cm_path)

    # Save LOSO summary
    loso_log = os.path.join(BASE_DIR, "loso_results.csv")
    with open(loso_log, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["subject", "val_acc", "val_loss", "n_val"])
        writer.writeheader()
        writer.writerows(fold_results)
    print(f"  Saved: {loso_log}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Train ISL gesture recognition model")
    parser.add_argument(
        "--mode", type=str, default="stratified",
        choices=["stratified", "loso"],
        help="Split mode: 'stratified' (80/20) or 'loso' (leave-one-subject-out)",
    )
    parser.add_argument(
        "--model", type=str, default="main",
        choices=["main", "light"],
        help="Model variant: 'main' (BiLSTMAttention) or 'light' (LightBiLSTM)",
    )
    args = parser.parse_args()

    print("=" * 60)
    print("ISL Gesture Recognition — Training")
    print(f"  Mode:  {args.mode}")
    print(f"  Model: {args.model}")
    print("=" * 60)

    # Load landmarks
    if not os.path.isfile(LANDMARKS_FILE):
        print(f"[ERROR] Landmarks file not found: {LANDMARKS_FILE}")
        print("  Run extract_landmarks.py first.")
        sys.exit(1)

    data = np.load(LANDMARKS_FILE, allow_pickle=True)
    X = data["X"]                    # (N, 30, 126)
    y = data["y"]                    # (N,)
    subjects = data["subjects"]      # (N,) string
    filenames = data["filenames"]    # (N,) string

    print(f"  Loaded: {X.shape[0]} samples, shape {X.shape}")
    print(f"  Classes: {dict(Counter(y))}")
    print(f"  Unique subjects: {len(set(subjects))}")

    if args.mode == "loso":
        train_loso(X, y, subjects, filenames, model_type=args.model)
    else:
        train_stratified(X, y, subjects, filenames, model_type=args.model)


if __name__ == "__main__":
    main()
