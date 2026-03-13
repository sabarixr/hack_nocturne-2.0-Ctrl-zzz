from pathlib import Path

NUM_LANDMARKS = 478
COORDINATES_PER_LANDMARK = 3
RAW_FEATURE_SIZE = NUM_LANDMARKS * COORDINATES_PER_LANDMARK

CLASSIFICATION_LABELS = [
    "neutral",
    "happy",
    "sad",
    "surprise",
    "afraid",
    "disgust",
    "angry",
]
LABEL_ALIASES = {
    "neutral": "neutral",
    "happy": "happy",
    "sad": "sad",
    "surprise": "surprise",
    "fear": "afraid",
    "afraid": "afraid",
    "disgust": "disgust",
    "anger": "angry",
    "angry": "angry",
}

RAF_DB_LABEL_MAP = {
    1: "surprise",
    2: "afraid",
    3: "disgust",
    4: "happy",
    5: "sad",
    6: "angry",
    7: "neutral",
}

DEFAULT_AFFECTNET_DIR = Path("AffectNet")
DEFAULT_RAF_DB_DIR = Path("RAF-DB")
DEFAULT_SFEW_DIR = Path("SFEW")
DEFAULT_FACE_LANDMARKER_TASK = Path("face_landmarker.task")

DEFAULT_DATA_DIR = Path("data")
DEFAULT_ARTIFACT_DIR = Path("artifacts")
DEFAULT_MODEL_PATH = DEFAULT_ARTIFACT_DIR / "emotion_landmark_model.keras"
DEFAULT_TFLITE_PATH = DEFAULT_ARTIFACT_DIR / "emotion_landmark_model.tflite"
DEFAULT_LABEL_MAP_PATH = DEFAULT_ARTIFACT_DIR / "label_map.json"
DEFAULT_PREPROCESSOR_PATH = DEFAULT_ARTIFACT_DIR / "preprocessor_stats.npz"
DEFAULT_FEATURE_CONFIG_PATH = DEFAULT_ARTIFACT_DIR / "feature_config.json"

DEFAULT_BATCH_SIZE = 32
DEFAULT_EPOCHS = 40
DEFAULT_CLASSIFICATION_LEARNING_RATE = 1e-5
DEFAULT_DROPOUT = 0.3
DEFAULT_RANDOM_SEED = 42
