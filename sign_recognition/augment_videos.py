"""
Video-level augmentation: expand the dataset from ~421 originals to ~1200+ videos.

Augmentations applied per original video:
  1. HorizontalFlip
  2. Rotation (+15°)
  3. Rotation (-15°)
  4. BrightnessJitter (+30% / -30%, randomly chosen per video)
  5. SpeedChange (0.75x slow-mo)
  6. SpeedChange (1.25x fast-forward)

Output structure mirrors the original:
  dataset_augmented/<class_name>/<class_name>_Crop_<subject>_<rep>_<aug_tag>.avi

Subject IDs are preserved in filenames so LOSO grouping works correctly.

Usage:
    python augment_videos.py
"""

import os
import sys
import random
import time

import cv2
import numpy as np

from config import (
    DATASET_DIR,
    AUGMENTED_DIR,
    CLASSES,
    ROTATION_ANGLES,
    BRIGHTNESS_DELTA,
    SPEED_SLOW,
    SPEED_FAST,
    RANDOM_SEED,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def read_video(path: str) -> list[np.ndarray]:
    """Read all frames from a video file. Returns list of BGR frames."""
    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        print(f"  [WARN] Cannot open {path}")
        return []
    frames = []
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        frames.append(frame)
    cap.release()
    return frames


def write_video(frames: list[np.ndarray], path: str, fps: float = 30.0) -> None:
    """Write frames to an AVI file using XVID codec."""
    if not frames:
        return
    h, w = frames[0].shape[:2]
    fourcc = cv2.VideoWriter_fourcc(*"XVID")
    writer = cv2.VideoWriter(path, fourcc, fps, (w, h))
    for f in frames:
        # Ensure frame matches expected size (resize if rotated/cropped differently)
        if f.shape[:2] != (h, w):
            f = cv2.resize(f, (w, h))
        writer.write(f)
    writer.release()


def get_fps(path: str) -> float:
    """Read the FPS of a video file."""
    cap = cv2.VideoCapture(path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    cap.release()
    return fps if fps > 0 else 30.0


# ---------------------------------------------------------------------------
# Augmentation functions — each takes frames list, returns new frames list
# ---------------------------------------------------------------------------

def horizontal_flip(frames: list[np.ndarray]) -> list[np.ndarray]:
    return [cv2.flip(f, 1) for f in frames]


def vertical_flip(frames: list[np.ndarray]) -> list[np.ndarray]:
    return [cv2.flip(f, 0) for f in frames]


def rotate(frames: list[np.ndarray], angle: float) -> list[np.ndarray]:
    """Rotate frames around center, keep same dimensions, fill border black."""
    if not frames:
        return frames
    h, w = frames[0].shape[:2]
    center = (w / 2, h / 2)
    M = cv2.getRotationMatrix2D(center, angle, 1.0)
    return [cv2.warpAffine(f, M, (w, h), borderValue=(0, 0, 0)) for f in frames]


def brightness_jitter(frames: list[np.ndarray], delta: float) -> list[np.ndarray]:
    """
    Adjust brightness by a factor of (1 + delta).
    delta > 0 brightens, delta < 0 darkens.
    """
    factor = 1.0 + delta
    out = []
    for f in frames:
        adjusted = np.clip(f.astype(np.float32) * factor, 0, 255).astype(np.uint8)
        out.append(adjusted)
    return out


def speed_change(frames: list[np.ndarray], factor: float) -> list[np.ndarray]:
    """
    Resample frames to simulate speed change.
    factor < 1 → slow-mo (more frames from same content via interpolation)
    factor > 1 → speed-up (fewer frames, subsample)
    
    We resample to int(len(frames) / factor) frames using linear index mapping.
    """
    n = len(frames)
    if n == 0:
        return frames
    new_n = max(2, int(n / factor))
    indices = np.linspace(0, n - 1, new_n)
    out = []
    for idx in indices:
        lower = int(np.floor(idx))
        upper = min(lower + 1, n - 1)
        alpha = idx - lower
        if alpha < 1e-6:
            out.append(frames[lower])
        else:
            blended = cv2.addWeighted(frames[lower], 1.0 - alpha, frames[upper], alpha, 0)
            out.append(blended)
    return out


# ---------------------------------------------------------------------------
# Main augmentation pipeline
# ---------------------------------------------------------------------------

def augment_single_video(src_path: str, dst_dir: str, base_name: str, fps: float) -> int:
    """
    Apply all augmentations to one video, write results to dst_dir.
    Returns number of augmented files written.
    """
    frames = read_video(src_path)
    if not frames:
        return 0

    written = 0
    augmentations = []

    # 1. Horizontal flip
    augmentations.append(("hflip", horizontal_flip(frames)))

    # 2 & 3. Rotation ±15°
    for angle in ROTATION_ANGLES:
        tag = f"rot{angle:+d}".replace("+", "p").replace("-", "n")
        augmentations.append((tag, rotate(frames, angle)))

    # 4. Brightness jitter — pick either +delta or -delta randomly
    b_delta = random.choice([BRIGHTNESS_DELTA, -BRIGHTNESS_DELTA])
    b_tag = "bright" if b_delta > 0 else "dark"
    augmentations.append((b_tag, brightness_jitter(frames, b_delta)))

    # 5. Speed slow
    augmentations.append(("slow", speed_change(frames, SPEED_SLOW)))

    # 6. Speed fast
    augmentations.append(("fast", speed_change(frames, SPEED_FAST)))

    for tag, aug_frames in augmentations:
        out_name = f"{base_name}_{tag}.avi"
        out_path = os.path.join(dst_dir, out_name)
        write_video(aug_frames, out_path, fps=fps)
        written += 1

    return written


def run_augmentation() -> None:
    random.seed(RANDOM_SEED)
    np.random.seed(RANDOM_SEED)

    print("=" * 60)
    print("Video-level augmentation")
    print(f"  Source:  {DATASET_DIR}")
    print(f"  Output:  {AUGMENTED_DIR}")
    print("=" * 60)

    if not os.path.isdir(DATASET_DIR):
        print(f"[ERROR] Dataset directory not found: {DATASET_DIR}")
        sys.exit(1)

    total_originals = 0
    total_augmented = 0
    t0 = time.time()

    for cls in CLASSES:
        src_cls_dir = os.path.join(DATASET_DIR, cls)
        dst_cls_dir = os.path.join(AUGMENTED_DIR, cls)
        os.makedirs(dst_cls_dir, exist_ok=True)

        if not os.path.isdir(src_cls_dir):
            print(f"  [WARN] Missing class folder: {src_cls_dir}")
            continue

        videos = sorted([
            f for f in os.listdir(src_cls_dir)
            if f.lower().endswith((".avi", ".mp4"))
        ])

        cls_originals = 0
        cls_augmented = 0

        for vname in videos:
            src_path = os.path.join(src_cls_dir, vname)
            fps = get_fps(src_path)
            base_name = os.path.splitext(vname)[0]

            # Copy original to augmented dir as well
            orig_frames = read_video(src_path)
            if orig_frames:
                write_video(orig_frames, os.path.join(dst_cls_dir, vname), fps=fps)
                cls_originals += 1

                # Generate augmentations
                n_aug = augment_single_video(src_path, dst_cls_dir, base_name, fps)
                cls_augmented += n_aug

        total_originals += cls_originals
        total_augmented += cls_augmented
        total_cls = cls_originals + cls_augmented
        print(f"  {cls:>10s}: {cls_originals} originals + {cls_augmented} augmented = {total_cls} total")

    elapsed = time.time() - t0
    grand_total = total_originals + total_augmented
    print("-" * 60)
    print(f"  TOTAL: {total_originals} originals + {total_augmented} augmented = {grand_total} videos")
    print(f"  Time:  {elapsed:.1f}s")
    print("=" * 60)


if __name__ == "__main__":
    run_augmentation()
