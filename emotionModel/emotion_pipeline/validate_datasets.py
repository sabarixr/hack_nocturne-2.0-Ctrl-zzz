from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd

from .config import DEFAULT_AFFECTNET_DIR, DEFAULT_RAF_DB_DIR, DEFAULT_SFEW_DIR, RAF_DB_LABEL_MAP
from .dataset import build_affectnet_frame, build_rafdb_frame, build_sfew_frame


def duplicate_sfew_basenames(sfew_dir: Path) -> dict[str, int]:
    train_dir = sfew_dir / "Train"
    if not train_dir.exists():
        return {}
    files = [path.name for path in train_dir.glob("*") if path.is_file()]
    counts = pd.Series(files).value_counts()
    duplicates = counts[counts > 1]
    return {str(name): int(count) for name, count in duplicates.items()}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate AffectNet, RAF-DB, and SFEW dataset paths and labels")
    parser.add_argument("--affectnet-dir", default=str(DEFAULT_AFFECTNET_DIR))
    parser.add_argument("--rafdb-dir", default=str(DEFAULT_RAF_DB_DIR))
    parser.add_argument("--sfew-dir", default=str(DEFAULT_SFEW_DIR))
    parser.add_argument("--min-label-confidence", type=float, default=0.0)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    affectnet_dir = Path(args.affectnet_dir)
    rafdb_dir = Path(args.rafdb_dir)
    sfew_dir = Path(args.sfew_dir)

    print("Checking RAF-DB label mapping...")
    raf_preview = pd.read_csv(rafdb_dir / "train_labels.csv").head(3)
    print(raf_preview.to_string(index=False))
    print("RAF-DB numeric map:", RAF_DB_LABEL_MAP)

    print("\nBuilding manifests...")
    affectnet = build_affectnet_frame(affectnet_dir, min_label_confidence=args.min_label_confidence)
    rafdb = build_rafdb_frame(rafdb_dir)
    sfew = build_sfew_frame(sfew_dir)

    for dataset_name, frame in [("AffectNet", affectnet), ("RAF-DB", rafdb), ("SFEW", sfew)]:
        print(f"\n{dataset_name} summary")
        print(f"samples: {len(frame):,}")
        if frame.empty:
            continue
        print(frame["target_label"].value_counts().sort_index().to_string())
        missing_files = int((~frame["image_path"].map(lambda p: Path(p).exists())).sum())
        print(f"missing image paths in manifest: {missing_files}")

    duplicates = duplicate_sfew_basenames(sfew_dir)
    print("\nSFEW flattened basename duplicates:", len(duplicates))
    if duplicates:
        preview = list(duplicates.items())[:10]
        print("sample duplicates:", preview)


if __name__ == "__main__":
    main()
