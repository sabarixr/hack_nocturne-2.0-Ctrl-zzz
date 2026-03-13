from __future__ import annotations

import argparse
import tempfile
from pathlib import Path

import tensorflow as tf

from .config import DEFAULT_ARTIFACT_DIR, DEFAULT_MODEL_PATH, DEFAULT_TFLITE_PATH
from .model import RegionTokenStack


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Convert the trained Keras landmark emotion model to TFLite")
    parser.add_argument("--artifacts-dir", default=str(DEFAULT_ARTIFACT_DIR))
    parser.add_argument("--model-path", default=None)
    parser.add_argument("--output-path", default=None)
    parser.add_argument("--float16", action="store_true", help="Enable float16 weight quantization")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    artifacts_dir = Path(args.artifacts_dir)
    model_path = Path(args.model_path) if args.model_path else artifacts_dir / DEFAULT_MODEL_PATH.name
    output_path = Path(args.output_path) if args.output_path else artifacts_dir / DEFAULT_TFLITE_PATH.name

    model = tf.keras.models.load_model(
        model_path,
        safe_mode=False,
        custom_objects={"RegionTokenStack": RegionTokenStack},
        compile=False,
    )
    inference_model = tf.keras.Model(inputs=model.inputs, outputs=model.outputs, name=f"{model.name}_inference")

    def build_converter_from_keras() -> tf.lite.TFLiteConverter:
        converter = tf.lite.TFLiteConverter.from_keras_model(inference_model)
        if args.float16:
            converter.optimizations = [tf.lite.Optimize.DEFAULT]
            converter.target_spec.supported_types = [tf.float16]
        return converter

    def build_converter_from_saved_model(tmp_dir: str) -> tf.lite.TFLiteConverter:
        tf.saved_model.save(inference_model, tmp_dir)
        converter = tf.lite.TFLiteConverter.from_saved_model(tmp_dir)
        if args.float16:
            converter.optimizations = [tf.lite.Optimize.DEFAULT]
            converter.target_spec.supported_types = [tf.float16]
        return converter

    try:
        tflite_model = build_converter_from_keras().convert()
    except Exception as keras_error:
        print(f"Direct Keras conversion failed: {keras_error}")
        print("Retrying export via SavedModel fallback...")
        with tempfile.TemporaryDirectory(prefix="emotion_tflite_") as tmp_dir:
            tflite_model = build_converter_from_saved_model(tmp_dir).convert()

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(tflite_model)
    print(f"Wrote TFLite model to {output_path}")


if __name__ == "__main__":
    main()
