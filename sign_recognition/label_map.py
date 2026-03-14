"""
Simple label mapping for the 8 ISL emergency gesture classes.
Folder names in the dataset ARE the labels.
"""

from config import CLASSES, CLASS_TO_IDX, IDX_TO_CLASS


# Keep backward-compatible names
GESTURE_CLASSES = CLASSES
NUM_CLASSES = len(CLASSES)


def get_class_index(label: str) -> int:
    """Convert class name to integer index."""
    return CLASS_TO_IDX[label.strip().lower()]


def get_class_name(idx: int) -> str:
    """Convert integer index to class name."""
    return IDX_TO_CLASS[idx]


# Backward compatible aliases
getClassIndex = get_class_index
getClassName = get_class_name
getNumClasses = lambda: len(CLASSES)


if __name__ == "__main__":
    print(f"Label mapping ({NUM_CLASSES} classes):")
    for i, c in enumerate(CLASSES):
        print(f"  {i}: {c}")
