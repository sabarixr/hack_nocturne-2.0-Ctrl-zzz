"""
=============================================================================
Data Preparation: Extract MediaPipe hand landmarks from videos
=============================================================================

Extracts:
    1. Hand landmark positions (21 landmarks x 3 coords x 2 hands = 126)
    2. Velocity features (frame-to-frame deltas of positions = 126)
    -> Total: 252 features per frame

Saves landmark sequences as .npy files and creates manifest.json with splits.

Usage:
    python prepare_data.py
=============================================================================
"""

import os
import sys
import json
import random
import numpy as np
import cv2
from typing import Optional
from config import TrainConfig
from label_map import GESTURE_CLASSES


def createHandLandmarker(config: TrainConfig, mode: str = "VIDEO"):
    """
    Create a fresh MediaPipe HandLandmarker instance.
    A new instance is needed per video in VIDEO mode because
    detect_for_video requires strictly increasing timestamps.
    """
    import mediapipe as mp
    from mediapipe.tasks.python import BaseOptions
    from mediapipe.tasks.python.vision import (
        HandLandmarkerOptions, HandLandmarker, RunningMode
    )

    handModelPath = os.path.join(config.modelsDir, "hand_landmarker.task")
    if not os.path.exists(handModelPath):
        print(f"ERROR: MediaPipe hand model not found at {handModelPath}")
        print("Download from: https://storage.googleapis.com/mediapipe-models/"
              "hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task")
        sys.exit(1)

    runMode = RunningMode.VIDEO if mode == "VIDEO" else RunningMode.IMAGE

    opts = HandLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=handModelPath),
        running_mode=runMode,
        num_hands=config.numHands,
        min_hand_detection_confidence=0.3,
        min_hand_presence_confidence=0.3,
        min_tracking_confidence=0.3,
    )
    return HandLandmarker.create_from_options(opts)


def extractLandmarkVector(result, config: TrainConfig) -> np.ndarray:
    """Extract 126-dim wrist-centered landmark vector from a MediaPipe result."""
    landmarkVector = np.zeros(config.baseLandmarkDim, dtype=np.float32)

    if result.hand_landmarks:
        for handIdx, handLandmarks in enumerate(result.hand_landmarks[:config.numHands]):
            offset = handIdx * config.numHandLandmarks * config.landmarkDimensions

            wristX = handLandmarks[0].x
            wristY = handLandmarks[0].y
            wristZ = handLandmarks[0].z

            for lmIdx, lm in enumerate(handLandmarks):
                base = offset + lmIdx * config.landmarkDimensions
                landmarkVector[base] = lm.x - wristX
                landmarkVector[base + 1] = lm.y - wristY
                landmarkVector[base + 2] = lm.z - wristZ

    return landmarkVector


def extractLandmarksFromVideo(videoPath: str, config: TrainConfig) -> Optional[np.ndarray]:
    """
    Extract hand landmarks from a video file using MediaPipe.
    Creates a fresh HandLandmarker per video to avoid timestamp issues.

    Returns: np.ndarray of shape [num_frames, feature_dim] (float32)
        With velocity: [num_frames, 252]
        Without:       [num_frames, 126]
        Returns None if the video cannot be read or has too few frames.
    """
    import mediapipe as mp

    cap = cv2.VideoCapture(videoPath)
    if not cap.isOpened():
        print(f"    Cannot open video: {videoPath}")
        return None

    videoFps = cap.get(cv2.CAP_PROP_FPS)
    if videoFps <= 0:
        videoFps = 25.0  # Default fallback

    # Do NOT check totalFrames -- many .avi files report 0 or -1
    # even though they have valid frames. Just read until EOF.

    skipFactor = max(1, round(videoFps / config.targetFps))

    # Try VIDEO mode first. If it fails, fall back to IMAGE mode.
    handLandmarker = None
    useVideoMode = True

    try:
        handLandmarker = createHandLandmarker(config, mode="VIDEO")
    except Exception as e:
        print(f"    VIDEO mode init failed, using IMAGE mode: {e}")
        useVideoMode = False
        handLandmarker = createHandLandmarker(config, mode="IMAGE")

    allLandmarks = []
    frameIdx = 0
    timestampMs = 0
    videoModeFailCount = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        if frameIdx % skipFactor == 0:
            rgbFrame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mpImage = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgbFrame)

            result = None

            if useVideoMode:
                try:
                    result = handLandmarker.detect_for_video(mpImage, timestampMs)
                except Exception:
                    videoModeFailCount += 1
                    # If VIDEO mode keeps failing, switch to IMAGE mode
                    if videoModeFailCount >= 3:
                        try:
                            handLandmarker.close()
                        except Exception:
                            pass
                        useVideoMode = False
                        handLandmarker = createHandLandmarker(config, mode="IMAGE")
                        try:
                            result = handLandmarker.detect(mpImage)
                        except Exception:
                            pass

            if not useVideoMode and result is None:
                try:
                    result = handLandmarker.detect(mpImage)
                except Exception:
                    pass

            if result is not None:
                landmarkVector = extractLandmarkVector(result, config)
            else:
                landmarkVector = np.zeros(config.baseLandmarkDim, dtype=np.float32)

            allLandmarks.append(landmarkVector)

        frameIdx += 1
        # Timestamp must always increase for VIDEO mode
        timestampMs += max(1, int(1000 / videoFps))

    cap.release()

    try:
        handLandmarker.close()
    except Exception:
        pass

    if len(allLandmarks) < config.minFramesRequired:
        return None

    positions = np.array(allLandmarks, dtype=np.float32)  # [num_frames, 126]

    if config.useVelocityFeatures:
        velocities = np.zeros_like(positions)
        velocities[1:] = positions[1:] - positions[:-1]
        features = np.concatenate([positions, velocities], axis=1)
    else:
        features = positions

    return features


def prepareData(config: TrainConfig):
    os.makedirs(config.cacheDir, exist_ok=True)
    os.makedirs(config.checkpointDir, exist_ok=True)

    # Scan dataset
    allVideos = []
    for label in sorted(os.listdir(config.datasetDir)):
        labelDir = os.path.join(config.datasetDir, label)
        if not os.path.isdir(labelDir):
            continue
        if label not in GESTURE_CLASSES:
            print(f"Warning: skipping unknown label folder '{label}'")
            continue
        for fname in sorted(os.listdir(labelDir)):
            if fname.lower().endswith(('.avi', '.mp4', '.mov', '.mkv')):
                allVideos.append((label, os.path.join(labelDir, fname)))

    print(f"Found {len(allVideos)} videos across {len(set(v[0] for v in allVideos))} classes")

    classCounts = {}
    for label, _ in allVideos:
        classCounts[label] = classCounts.get(label, 0) + 1
    for cls in sorted(classCounts):
        print(f"  {cls}: {classCounts[cls]} videos")

    # Quick diagnostic: check first video's properties
    if allVideos:
        testLabel, testPath = allVideos[0]
        testCap = cv2.VideoCapture(testPath)
        if testCap.isOpened():
            fps = testCap.get(cv2.CAP_PROP_FPS)
            frameCount = int(testCap.get(cv2.CAP_PROP_FRAME_COUNT))
            w = int(testCap.get(cv2.CAP_PROP_FRAME_WIDTH))
            h = int(testCap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            # Actually try to read frames
            actualFrames = 0
            while True:
                ret, _ = testCap.read()
                if not ret:
                    break
                actualFrames += 1
            testCap.release()
            print(f"\nDiagnostic (first video: {os.path.basename(testPath)}):")
            print(f"  FPS: {fps}, Reported frames: {frameCount}, Actual frames: {actualFrames}")
            print(f"  Resolution: {w}x{h}")
            skipFactor = max(1, round(fps / config.targetFps)) if fps > 0 else 1
            print(f"  Skip factor: {skipFactor} (sample every {skipFactor} frames)")
            print(f"  Expected sampled frames: ~{actualFrames // skipFactor}")
        else:
            testCap.release()
            print(f"\nWARNING: Cannot open first video: {testPath}")

    # Stratified split
    videosByClass = {}
    for label, path in allVideos:
        if label not in videosByClass:
            videosByClass[label] = []
        videosByClass[label].append(path)

    splitAssignments = []
    random.seed(42)
    for label in sorted(videosByClass):
        paths = videosByClass[label][:]
        random.shuffle(paths)
        n = len(paths)
        nTrain = max(1, int(n * config.trainSplit))
        nVal = max(1, int(n * config.valSplit))
        for i, p in enumerate(paths):
            if i < nTrain:
                splitAssignments.append((label, p, "train"))
            elif i < nTrain + nVal:
                splitAssignments.append((label, p, "val"))
            else:
                splitAssignments.append((label, p, "test"))

    splitCounts = {"train": 0, "val": 0, "test": 0}
    for _, _, s in splitAssignments:
        splitCounts[s] += 1
    print(f"\nSplit: train={splitCounts['train']}, val={splitCounts['val']}, test={splitCounts['test']}")
    print(f"Feature dim: {config.featureInputDim} "
          f"({'positions + velocities' if config.useVelocityFeatures else 'positions only'})")

    # Extract landmarks
    manifest = []
    totalProcessed = 0
    totalFailed = 0
    totalNoHands = 0

    for idx, (label, videoPath, split) in enumerate(splitAssignments):
        videoName = os.path.splitext(os.path.basename(videoPath))[0]
        npyFilename = f"{label}_{videoName}.npy"
        npyPath = os.path.join(config.cacheDir, npyFilename)

        # Skip if cached
        if os.path.exists(npyPath):
            features = np.load(npyPath)
            manifest.append({
                "key": f"{label}_{videoName}",
                "label": label,
                "npy_path": npyPath,
                "num_frames": features.shape[0],
                "feature_dim": features.shape[1],
                "split": split,
            })
            totalProcessed += 1
            if totalProcessed % 50 == 0:
                print(f"  [{idx+1}/{len(splitAssignments)}] Cached: {totalProcessed}")
            continue

        try:
            features = extractLandmarksFromVideo(videoPath, config)
        except Exception as e:
            print(f"  [{idx+1}/{len(splitAssignments)}] ERROR: {videoPath}: {e}")
            totalFailed += 1
            continue

        if features is None:
            totalFailed += 1
            print(f"  [{idx+1}/{len(splitAssignments)}] FAILED (too few frames): {videoPath}")
            continue

        # Check if any frames had hands detected
        nonZeroFrames = np.any(features[:, :config.baseLandmarkDim] != 0, axis=1).sum()
        if nonZeroFrames < config.minFramesRequired:
            totalNoHands += 1
            print(f"  [{idx+1}/{len(splitAssignments)}] LOW HANDS "
                  f"({nonZeroFrames}/{features.shape[0]}): {os.path.basename(videoPath)}")

        np.save(npyPath, features)
        totalProcessed += 1

        manifest.append({
            "key": f"{label}_{videoName}",
            "label": label,
            "npy_path": npyPath,
            "num_frames": features.shape[0],
            "feature_dim": features.shape[1],
            "split": split,
        })

        if totalProcessed % 20 == 0:
            print(f"  [{idx+1}/{len(splitAssignments)}] Processed: {totalProcessed}, "
                  f"Failed: {totalFailed}")
            # Periodic save
            manifestPath = os.path.join(config.cacheDir, "manifest.json")
            with open(manifestPath, "w") as f:
                json.dump(manifest, f, indent=2)

    # Save manifest
    manifestPath = os.path.join(config.cacheDir, "manifest.json")
    with open(manifestPath, "w") as f:
        json.dump(manifest, f, indent=2)

    if manifest:
        splitCounts = {"train": 0, "val": 0, "test": 0}
        for entry in manifest:
            splitCounts[entry["split"]] += 1

        frameCounts = [e["num_frames"] for e in manifest]
        print(f"\nDone. Processed: {totalProcessed}, Failed: {totalFailed}, Low hands: {totalNoHands}")
        print(f"Split: {splitCounts}")
        print(f"Frame counts - min: {min(frameCounts)}, max: {max(frameCounts)}, "
              f"avg: {np.mean(frameCounts):.1f}")
        print(f"Manifest: {manifestPath}")
    else:
        print(f"\nDone. ALL {totalFailed} videos failed. No manifest entries created.")
        print("Check the diagnostic output above for video format issues.")


if __name__ == "__main__":
    config = TrainConfig()
    prepareData(config)
