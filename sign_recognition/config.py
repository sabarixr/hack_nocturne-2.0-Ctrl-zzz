"""
Central configuration for the ISL gesture recognition pipeline.
All paths, hyperparameters, and constants in one place.
"""

import os

# ============================================================================
# Paths
# ============================================================================
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATASET_DIR = os.path.join(BASE_DIR, "dataset")
AUGMENTED_DIR = os.path.join(BASE_DIR, "dataset_augmented")
LANDMARKS_FILE = os.path.join(BASE_DIR, "landmarks.npz")
DETECTION_LOG = os.path.join(BASE_DIR, "detection_log.csv")
BEST_MODEL_PATH = os.path.join(BASE_DIR, "best_model.pth")
TRAINING_LOG = os.path.join(BASE_DIR, "training_log.csv")

# ============================================================================
# Classes (folder names = labels, sorted alphabetically)
# ============================================================================
CLASSES = ["accident", "call", "doctor", "help", "hot", "lose", "pain", "thief"]
NUM_CLASSES = len(CLASSES)
CLASS_TO_IDX = {c: i for i, c in enumerate(CLASSES)}
IDX_TO_CLASS = {i: c for i, c in enumerate(CLASSES)}

# ============================================================================
# MediaPipe settings (Tasks API — mp.solutions not available on Python 3.13+)
# ============================================================================
MODELS_DIR = os.path.join(BASE_DIR, "models")
HAND_LANDMARKER_PATH = os.path.join(MODELS_DIR, "hand_landmarker.task")
MP_MAX_HANDS = 2
MP_MIN_DETECTION_CONF = 0.4
MP_MIN_PRESENCE_CONF = 0.4
MP_MIN_TRACKING_CONF = 0.4

# ============================================================================
# Landmark extraction
# ============================================================================
NUM_LANDMARKS_PER_HAND = 21
LANDMARK_DIMS = 3  # x, y, z
FEATURES_PER_HAND = NUM_LANDMARKS_PER_HAND * LANDMARK_DIMS  # 63
TOTAL_FEATURES = FEATURES_PER_HAND * MP_MAX_HANDS  # 126
TARGET_SEQ_LEN = 30  # resample all videos to this many frames
MIN_DETECTION_RATE = 0.40  # skip videos with < 40% valid frames

# ============================================================================
# Video augmentation
# ============================================================================
ROTATION_ANGLES = [15, -15]
BRIGHTNESS_DELTA = 0.30  # ± 30%
SPEED_SLOW = 0.75
SPEED_FAST = 1.25

# ============================================================================
# Model architecture
# ============================================================================
LSTM_HIDDEN_1 = 64
LSTM_HIDDEN_2 = 32
LSTM_DROPOUT = 0.3
FC_HIDDEN = 32
FC_DROPOUT_1 = 0.5
FC_DROPOUT_2 = 0.3

# Light variant (fallback if overfitting)
LIGHT_LSTM_HIDDEN_1 = 32
LIGHT_LSTM_HIDDEN_2 = 16

# ============================================================================
# Training
# ============================================================================
BATCH_SIZE = 16
MAX_EPOCHS = 100
LEARNING_RATE = 1e-3
WEIGHT_DECAY = 1e-3
COSINE_T_MAX = 60
COSINE_ETA_MIN = 1e-5
EARLY_STOP_PATIENCE = 20
RANDOM_SEED = 42

# ============================================================================
# Landmark-space augmentation probabilities
# ============================================================================
AUG_PROB = 0.4
GAUSS_NOISE_SIGMA = 0.005
RANDOM_SCALE_RANGE = 0.05
TIME_WARP_SIGMA = 0.15
FRAME_DROP_RATE = 0.08
