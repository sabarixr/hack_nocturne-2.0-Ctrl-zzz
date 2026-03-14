"""
=============================================================================
Dataset Loader for MediaPipe Landmark + BiLSTM Sign Language Recognition
=============================================================================

Key improvement: Instead of 1 sample per video, we extract MULTIPLE
overlapping sliding windows from each video. This multiplies training data
from ~326 to ~1500+ samples, which is critical for preventing memorization.

Each sample:
    Input:  [seq_len, 126]  (21 landmarks x 3 coords x 2 hands)
    Label:  scalar int64 class index

Data Augmentation (training only):
    - Horizontal mirror (negate X)
    - Random Z-axis rotation
    - Random 3D translation
    - Landmark jitter (Gaussian noise)
    - Random scaling
    - Time warp (speed variation)
    - Landmark dropout (zero out random landmarks)
=============================================================================
"""

import os
import json
import numpy as np
import torch
from torch.utils.data import Dataset
from typing import Tuple, Optional, List
from config import TrainConfig
from label_map import getClassIndex


class SignLandmarkDataset(Dataset):
    """
    Loads landmark sequences from cached .npy files.
    For training: extracts multiple overlapping windows per video.
    For val/test: uses one center-cropped window per video.
    """

    def __init__(self, config: TrainConfig, split: str = "train",
                 manifestPath: Optional[str] = None):
        self.config = config
        self.split = split
        self.seqLen = config.sequenceLength
        self.augment = (split == "train")

        # Load manifest
        if manifestPath is None:
            manifestPath = os.path.join(config.cacheDir, "manifest.json")

        if not os.path.exists(manifestPath):
            raise FileNotFoundError(
                f"Manifest not found: {manifestPath}\nRun prepare_data.py first."
            )

        with open(manifestPath, "r") as f:
            fullManifest = json.load(f)

        entries = [e for e in fullManifest if e["split"] == split]

        # Build sample list: (npy_path, label, start_frame, end_frame)
        self.samples: List[Tuple[str, str, int, int]] = []

        for entry in entries:
            npyPath = entry["npy_path"]
            label = entry["label"]
            numFrames = entry["num_frames"]

            if split == "train" and numFrames > self.seqLen:
                # Extract multiple overlapping windows
                stride = config.trainWindowStride
                for start in range(0, numFrames - self.seqLen + 1, stride):
                    self.samples.append((npyPath, label, start, start + self.seqLen))
                # Always include the last window
                lastStart = numFrames - self.seqLen
                if lastStart % stride != 0:
                    self.samples.append((npyPath, label, lastStart, numFrames))
            else:
                # Val/test: single center crop (or full if shorter)
                self.samples.append((npyPath, label, -1, -1))  # -1 = use center crop

        if split == "train":
            origCount = len(entries)
            print(f"  Sliding window: {origCount} videos -> {len(self.samples)} training samples")

    def __len__(self) -> int:
        return len(self.samples)

    def __getitem__(self, idx: int) -> Tuple[torch.Tensor, torch.Tensor]:
        npyPath, label, startFrame, endFrame = self.samples[idx]

        # Load full landmark sequence: [num_frames, 126]
        fullData = np.load(npyPath).astype(np.float32)

        # Use only positions (first 126 dims), ignore velocities if present
        baseDim = self.config.baseLandmarkDim
        positions = fullData[:, :baseDim]

        # Extract the window
        if startFrame >= 0:
            positions = positions[startFrame:endFrame]
        else:
            # Center crop for val/test
            positions = self._centerCrop(positions)

        # Data augmentation (training only)
        if self.augment:
            positions = self._augment(positions)

        # Pad or truncate to exact sequence length
        positions = self._padOrTruncate(positions)

        featureTensor = torch.from_numpy(positions).float()
        labelTensor = torch.tensor(getClassIndex(label), dtype=torch.long)
        return featureTensor, labelTensor

    def _centerCrop(self, data: np.ndarray) -> np.ndarray:
        """Center-crop to seqLen, or return as-is if shorter."""
        n = data.shape[0]
        if n > self.seqLen:
            start = (n - self.seqLen) // 2
            return data[start:start + self.seqLen]
        return data

    def _augment(self, positions: np.ndarray) -> np.ndarray:
        """Apply data augmentation to landmark positions."""
        cfg = self.config

        # 1. Horizontal mirror (negate X coords)
        if cfg.augmentMirror and np.random.random() < 0.5:
            # Wrist-centered: mirror = negate X offset
            # X indices: 0, 3, 6, 9, ...
            positions = positions.copy()
            positions[:, 0::3] = -positions[:, 0::3]

        # 2. Random Z-axis rotation (camera-plane tilt)
        if cfg.augmentRotation > 0 and np.random.random() < 0.5:
            angle = np.random.uniform(-cfg.augmentRotation, cfg.augmentRotation)
            c, s = np.cos(angle), np.sin(angle)
            positions = positions.copy()
            xCols = positions[:, 0::3].copy()
            yCols = positions[:, 1::3].copy()
            positions[:, 0::3] = xCols * c - yCols * s
            positions[:, 1::3] = xCols * s + yCols * c

        # 3. Random 3D translation
        if cfg.augmentTranslation > 0 and np.random.random() < 0.5:
            shift = np.random.uniform(
                -cfg.augmentTranslation, cfg.augmentTranslation, size=(3,)
            ).astype(np.float32)
            positions = positions.copy()
            for i in range(3):
                positions[:, i::3] += shift[i]

        # 4. Time warp (speed variation)
        if cfg.augmentTimeWarp and positions.shape[0] > 3 and np.random.random() < 0.5:
            warpFactor = np.random.uniform(0.8, 1.2)
            origLen = positions.shape[0]
            newLen = max(3, int(origLen * warpFactor))
            oldIdx = np.linspace(0, origLen - 1, newLen)
            intIdx = np.arange(origLen)
            warped = np.zeros((newLen, positions.shape[1]), dtype=np.float32)
            for d in range(positions.shape[1]):
                warped[:, d] = np.interp(oldIdx, intIdx, positions[:, d])
            positions = warped

        # 5. Gaussian jitter
        if cfg.augmentJitter > 0:
            noise = np.random.normal(0, cfg.augmentJitter,
                                     size=positions.shape).astype(np.float32)
            positions = positions + noise

        # 6. Random scaling
        lo, hi = cfg.augmentScaleRange
        if lo != 1.0 or hi != 1.0:
            scale = np.random.uniform(lo, hi)
            positions = positions * scale

        # 7. Landmark dropout (zero out random landmarks)
        if cfg.augmentDropLandmark > 0:
            mask = np.random.random(size=positions.shape) < cfg.augmentDropLandmark
            positions = positions.copy()
            positions[mask] = 0.0

        return positions

    def _padOrTruncate(self, features: np.ndarray) -> np.ndarray:
        """Pad with zeros or center-crop to self.seqLen."""
        n = features.shape[0]
        dim = features.shape[1]

        if n == self.seqLen:
            return features
        elif n > self.seqLen:
            start = (n - self.seqLen) // 2
            return features[start:start + self.seqLen]
        else:
            padded = np.zeros((self.seqLen, dim), dtype=np.float32)
            padded[:n] = features
            return padded


def getClassWeights(config: TrainConfig,
                    manifestPath: Optional[str] = None) -> torch.Tensor:
    """Compute inverse frequency class weights for CrossEntropyLoss."""
    if manifestPath is None:
        manifestPath = os.path.join(config.cacheDir, "manifest.json")

    with open(manifestPath, "r") as f:
        manifest = json.load(f)

    trainEntries = [e for e in manifest if e["split"] == "train"]
    classCounts = np.zeros(config.numClasses, dtype=np.float32)

    for entry in trainEntries:
        classIdx = getClassIndex(entry["label"])
        classCounts[classIdx] += 1

    classCounts = np.maximum(classCounts, 1.0)
    totalSamples = classCounts.sum()
    weights = totalSamples / (config.numClasses * classCounts)

    return torch.from_numpy(weights).float()


if __name__ == "__main__":
    config = TrainConfig()
    manifestPath = os.path.join(config.cacheDir, "manifest.json")

    if not os.path.exists(manifestPath):
        print(f"Manifest not found at {manifestPath}")
        print("Run prepare_data.py first.")
    else:
        for split in ["train", "val", "test"]:
            ds = SignLandmarkDataset(config, split=split)
            print(f"{split}: {len(ds)} samples")

            if len(ds) > 0:
                seq, label = ds[0]
                print(f"  sequence shape: {seq.shape}")
                print(f"  label: {label.item()}")

        weights = getClassWeights(config)
        print(f"\nClass weights: {weights.numpy()}")
