"""
Export trained BiLSTM + Attention model to TFLite for Flutter.

Conversion path (no accuracy loss with float32):
    PyTorch (.pth) -> ONNX (.onnx) -> TFLite (.tflite)

Output files (saved to models/flutter_export/):
    1. sign_language_model.onnx     -- Intermediate ONNX (for debugging)
    2. sign_language_model.tflite   -- Final TFLite model for Flutter
    3. model_meta.json              -- Class labels, input/output shapes, config

Requirements (install before running):
    pip install onnx onnxruntime onnx-tf tensorflow

Usage:
    python export_tflite.py
    python export_tflite.py --checkpoint path/to/best_model.pth
    python export_tflite.py --model light
    python export_tflite.py --quantize   # optional int8 quantization
"""

import os
import sys
import json
import shutil
import argparse

import numpy as np
import torch
import torch.nn as nn

from config import (
    BEST_MODEL_PATH,
    CLASSES,
    NUM_CLASSES,
    TOTAL_FEATURES,
    TARGET_SEQ_LEN,
    MP_MAX_HANDS,
    NUM_LANDMARKS_PER_HAND,
    LANDMARK_DIMS,
    BASE_DIR,
    LSTM_HIDDEN_1,
    LSTM_HIDDEN_2,
    LSTM_DROPOUT,
    FC_HIDDEN,
    FC_DROPOUT_1,
    FC_DROPOUT_2,
    LIGHT_LSTM_HIDDEN_1,
    LIGHT_LSTM_HIDDEN_2,
)
from model import BiLSTMAttention, LightBiLSTM, count_parameters


# ---------------------------------------------------------------------------
# Output directory
# ---------------------------------------------------------------------------
EXPORT_DIR = os.path.join(BASE_DIR, "models", "flutter_export")


# ---------------------------------------------------------------------------
# Step 1: PyTorch -> ONNX
# ---------------------------------------------------------------------------

def export_to_onnx(model: nn.Module, onnx_path: str, device: torch.device) -> np.ndarray:
    """Export PyTorch model to ONNX format. Returns dummy input for later verification."""
    model.eval()

    # Fixed input shape: (1, 30, 126)
    dummy_input = torch.randn(1, TARGET_SEQ_LEN, TOTAL_FEATURES).to(device)

    print(f"  Exporting to ONNX: {onnx_path}")
    torch.onnx.export(
        model,
        dummy_input,
        onnx_path,
        export_params=True,
        opset_version=13,
        do_constant_folding=True,
        input_names=["input"],
        output_names=["output"],
        dynamic_axes=None,  # Fixed shape for TFLite compatibility
    )

    # Verify ONNX model structure
    import onnx
    onnx_model = onnx.load(onnx_path)
    onnx.checker.check_model(onnx_model)
    print(f"  ONNX model structure verified OK")

    # Compare outputs: PyTorch vs ONNX Runtime
    import onnxruntime as ort
    ort_session = ort.InferenceSession(onnx_path)

    dummy_np = dummy_input.cpu().numpy()
    with torch.no_grad():
        pytorch_out = model(dummy_input).cpu().numpy()

    ort_out = ort_session.run(None, {"input": dummy_np})[0]

    max_diff = np.max(np.abs(pytorch_out - ort_out))
    print(f"  PyTorch vs ONNX max diff: {max_diff:.8f}")

    if max_diff > 1e-4:
        print(f"  [WARN] Difference is larger than expected!")
    else:
        print(f"  PASS: ONNX output matches PyTorch")

    return dummy_np


# ---------------------------------------------------------------------------
# Step 2: ONNX -> TFLite
#
# Strategy: Rebuild the model natively in TensorFlow/Keras by reading the
# ONNX weights, then convert via tf.lite.  This avoids broken onnx-tf /
# onnx2tf bridges on TF 2.21 + onnx 1.20.
# ---------------------------------------------------------------------------

def _rebuild_in_tf(pytorch_model: nn.Module):
    """
    Rebuild the BiLSTM+Attention architecture directly in TensorFlow/Keras
    and copy weights from the PyTorch model. This is the most reliable
    conversion method — no third-party ONNX-to-TF bridges needed.
    """
    import tensorflow as tf

    is_light = isinstance(pytorch_model, LightBiLSTM)
    sd = pytorch_model.state_dict()

    # --- helpers -----------------------------------------------------------
    def pt2np(key):
        return sd[key].cpu().numpy()

    def set_lstm_weights(keras_lstm, prefix):
        """
        PyTorch LSTM stores:  weight_ih_l0, weight_hh_l0, bias_ih_l0, bias_hh_l0
                              weight_ih_l0_reverse, weight_hh_l0_reverse, ...
        Keras Bidirectional(LSTM) expects for each direction:
            kernel      (input_dim, 4*units)   — transposed from PyTorch weight_ih
            recurrent_kernel (units, 4*units)   — transposed from PyTorch weight_hh
            bias        (4*units,)              — bias_ih + bias_hh (PyTorch splits them)

        Gate order: PyTorch = [i, f, g, o],  Keras = [i, f, c, o]  (g == c)
        So the ordering is actually the same — no gate reordering needed.
        """
        def _get_weights_for_direction(suffix):
            W_ih = pt2np(f"{prefix}.weight_ih_l0{suffix}")   # (4*h, input)
            W_hh = pt2np(f"{prefix}.weight_hh_l0{suffix}")   # (4*h, h)
            b_ih = pt2np(f"{prefix}.bias_ih_l0{suffix}")      # (4*h,)
            b_hh = pt2np(f"{prefix}.bias_hh_l0{suffix}")      # (4*h,)

            kernel = W_ih.T              # (input, 4*h)
            rec_kernel = W_hh.T          # (h, 4*h)
            bias = b_ih + b_hh           # Keras uses single bias

            return kernel, rec_kernel, bias

        fwd_k, fwd_rk, fwd_b = _get_weights_for_direction("")
        bwd_k, bwd_rk, bwd_b = _get_weights_for_direction("_reverse")

        # Keras Bidirectional stores: [fwd_kernel, fwd_rec, fwd_bias,
        #                              bwd_kernel, bwd_rec, bwd_bias]
        keras_lstm.set_weights([fwd_k, fwd_rk, fwd_b,
                                bwd_k, bwd_rk, bwd_b])

    # --- Build Keras model -------------------------------------------------
    # NOTE: unroll=True avoids TensorList ops (FlexTensorListReserve) so the
    # TFLite model works with standard TFLITE_BUILTINS — no Flex delegate.
    # Safe because sequence length is fixed at TARGET_SEQ_LEN=30.
    inp = tf.keras.Input(shape=(TARGET_SEQ_LEN, TOTAL_FEATURES), name="input")

    # LayerNorm
    x = tf.keras.layers.LayerNormalization(epsilon=1e-5, name="layer_norm")(inp)

    # BiLSTM 1
    h1 = LIGHT_LSTM_HIDDEN_1 if is_light else LSTM_HIDDEN_1
    x = tf.keras.layers.Bidirectional(
        tf.keras.layers.LSTM(h1, return_sequences=True, unroll=True, name="lstm1_fwd"),
        backward_layer=tf.keras.layers.LSTM(h1, return_sequences=True, unroll=True, go_backwards=True, name="lstm1_bwd"),
        name="bilstm1",
    )(x)

    if not is_light:
        x = tf.keras.layers.Dropout(LSTM_DROPOUT, name="lstm_drop1")(x)

    # BiLSTM 2
    h2 = LIGHT_LSTM_HIDDEN_2 if is_light else LSTM_HIDDEN_2
    x = tf.keras.layers.Bidirectional(
        tf.keras.layers.LSTM(h2, return_sequences=True, unroll=True, name="lstm2_fwd"),
        backward_layer=tf.keras.layers.LSTM(h2, return_sequences=True, unroll=True, go_backwards=True, name="lstm2_bwd"),
        name="bilstm2",
    )(x)

    if not is_light:
        x = tf.keras.layers.Dropout(LSTM_DROPOUT, name="lstm_drop2")(x)

    # Simple Attention: scores = x @ W  (W is attn_dim x 1, no bias)
    attn_dim = h2 * 2
    scores = tf.keras.layers.Dense(1, use_bias=False, name="attention")(x)  # (B, T, 1)
    weights = tf.keras.layers.Softmax(axis=1, name="attn_softmax")(scores)
    x = tf.keras.layers.Multiply(name="attn_mul")([x, weights])
    x = tf.keras.layers.Lambda(lambda t: tf.reduce_sum(t, axis=1), name="attn_sum")(x)

    # Classifier head
    if is_light:
        x = tf.keras.layers.Dropout(0.4, name="cls_drop")(x)
        out = tf.keras.layers.Dense(NUM_CLASSES, name="classifier")(x)
    else:
        x = tf.keras.layers.Dropout(FC_DROPOUT_1, name="cls_drop1")(x)
        x = tf.keras.layers.Dense(FC_HIDDEN, activation="relu", name="fc1")(x)
        x = tf.keras.layers.Dropout(FC_DROPOUT_2, name="cls_drop2")(x)
        out = tf.keras.layers.Dense(NUM_CLASSES, name="fc2")(x)

    keras_model = tf.keras.Model(inputs=inp, outputs=out, name="bilstm_attention")

    # --- Copy weights from PyTorch -----------------------------------------
    # LayerNorm
    ln = keras_model.get_layer("layer_norm")
    ln.set_weights([pt2np("layer_norm.weight"), pt2np("layer_norm.bias")])

    # LSTMs
    set_lstm_weights(keras_model.get_layer("bilstm1"), "lstm1")
    set_lstm_weights(keras_model.get_layer("bilstm2"), "lstm2")

    # Attention
    attn_layer = keras_model.get_layer("attention")
    attn_layer.set_weights([pt2np("attention.attn.weight").T])  # (1, D) -> (D, 1)

    # Classifier
    if is_light:
        cls = keras_model.get_layer("classifier")
        cls.set_weights([pt2np("classifier.1.weight").T, pt2np("classifier.1.bias")])
    else:
        fc1 = keras_model.get_layer("fc1")
        fc1.set_weights([pt2np("classifier.1.weight").T, pt2np("classifier.1.bias")])
        fc2 = keras_model.get_layer("fc2")
        fc2.set_weights([pt2np("classifier.4.weight").T, pt2np("classifier.4.bias")])

    return keras_model


def export_to_tflite(
    onnx_path: str,
    tflite_path: str,
    pytorch_model: nn.Module,
    device: torch.device,
    quantize: bool = False,
) -> float:
    """
    Convert to TFLite by rebuilding the model in native TF/Keras and
    copying PyTorch weights directly. No onnx-tf / onnx2tf needed.
    """
    import tensorflow as tf

    print(f"  Rebuilding model in TensorFlow/Keras...")
    keras_model = _rebuild_in_tf(pytorch_model)
    keras_model.summary(print_fn=lambda s: print(f"    {s}"))

    # --- Verify Keras vs PyTorch match before TFLite conversion -------------
    dummy = np.random.randn(1, TARGET_SEQ_LEN, TOTAL_FEATURES).astype(np.float32)

    pytorch_model.eval()
    with torch.no_grad():
        pt_out = pytorch_model(torch.from_numpy(dummy).to(device)).cpu().numpy()

    keras_out = keras_model(dummy, training=False).numpy()
    max_diff = np.max(np.abs(pt_out - keras_out))
    print(f"  PyTorch vs Keras max diff: {max_diff:.8f}")

    if max_diff > 1e-3:
        print(f"  [WARN] Large difference — check weight transfer!")
    else:
        print(f"  PASS: Keras output matches PyTorch")

    # --- Save as TF SavedModel then convert to TFLite ----------------------
    saved_model_dir = tflite_path.replace(".tflite", "_saved_model")
    keras_model.export(saved_model_dir)
    print(f"  Saved TF SavedModel: {saved_model_dir}")

    print(f"  Converting SavedModel -> TFLite...")
    converter = tf.lite.TFLiteConverter.from_saved_model(saved_model_dir)

    # Only TFLITE_BUILTINS — no Flex delegate needed because LSTMs are
    # unrolled (no TensorList ops).  This makes the .tflite portable to
    # Flutter / Android / iOS without extra dependencies.
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
    ]

    if quantize:
        print(f"  Applying dynamic range quantization (int8 weights)...")
        converter.optimizations = [tf.lite.Optimize.DEFAULT]

    tflite_model = converter.convert()

    with open(tflite_path, "wb") as f:
        f.write(tflite_model)

    size_mb = os.path.getsize(tflite_path) / (1024 * 1024)
    print(f"  Saved TFLite: {tflite_path} ({size_mb:.2f} MB)")

    # Clean up SavedModel
    if os.path.isdir(saved_model_dir):
        shutil.rmtree(saved_model_dir)

    return size_mb


# ---------------------------------------------------------------------------
# Step 3: Verify TFLite model
# ---------------------------------------------------------------------------

def verify_tflite(tflite_path: str, model: nn.Module, device: torch.device) -> bool:
    """Verify TFLite model produces same output as PyTorch."""
    import tensorflow as tf

    interpreter = tf.lite.Interpreter(model_path=tflite_path)
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    print(f"\n  TFLite model info:")
    print(f"    Input:  {input_details[0]['shape']} {input_details[0]['dtype']}")
    print(f"    Output: {output_details[0]['shape']} {output_details[0]['dtype']}")

    # Test with random input
    dummy = np.random.randn(1, TARGET_SEQ_LEN, TOTAL_FEATURES).astype(np.float32)

    # PyTorch output
    model.eval()
    with torch.no_grad():
        pytorch_out = model(torch.from_numpy(dummy).to(device)).cpu().numpy()

    # TFLite output
    interpreter.set_tensor(input_details[0]["index"], dummy)
    interpreter.invoke()
    tflite_out = interpreter.get_tensor(output_details[0]["index"])

    max_diff = np.max(np.abs(pytorch_out - tflite_out))
    print(f"    PyTorch vs TFLite max diff: {max_diff:.6f}")

    # Check predictions match
    pytorch_pred = np.argmax(pytorch_out, axis=1)
    tflite_pred = np.argmax(tflite_out, axis=1)
    preds_match = np.array_equal(pytorch_pred, tflite_pred)

    print(f"    PyTorch prediction: {CLASSES[pytorch_pred[0]]} (logit={pytorch_out[0][pytorch_pred[0]]:.4f})")
    print(f"    TFLite  prediction: {CLASSES[tflite_pred[0]]} (logit={tflite_out[0][tflite_pred[0]]:.4f})")
    print(f"    Predictions match: {preds_match}")

    if max_diff > 1e-3:
        if preds_match:
            print(f"    [WARN] Numerical difference is noticeable but predictions still match")
        else:
            print(f"    [ERROR] Predictions differ! Export may be inaccurate.")
        return preds_match

    print(f"    PASS: TFLite output matches PyTorch")
    return True


# ---------------------------------------------------------------------------
# Save metadata JSON
# ---------------------------------------------------------------------------

def save_metadata(tflite_path: str, model: nn.Module, val_acc: float, size_mb: float, quantized: bool) -> str:
    meta = {
        "model_format": "tflite",
        "model_file": os.path.basename(tflite_path),
        "architecture": model.__class__.__name__,

        "input_shape": [1, TARGET_SEQ_LEN, TOTAL_FEATURES],
        "input_description": (
            f"Sequence of {TARGET_SEQ_LEN} frames of MediaPipe hand landmarks. "
            f"Shape: [1, {TARGET_SEQ_LEN}, {TOTAL_FEATURES}]. "
            f"Each frame has {TOTAL_FEATURES} features: "
            f"{NUM_LANDMARKS_PER_HAND} landmarks x {LANDMARK_DIMS} coords x {MP_MAX_HANDS} hands. "
            "Normalization: wrist-centered + scaled by max pairwise distance per hand. "
            "Zero-pad second hand if only one hand detected."
        ),

        "output_shape": [1, NUM_CLASSES],
        "output_description": (
            "Raw logits for each gesture class. Apply softmax to get probabilities. "
            "Use argmax to get predicted class index."
        ),

        "classes": CLASSES,
        "num_classes": NUM_CLASSES,
        "class_index_map": {str(i): cls for i, cls in enumerate(CLASSES)},

        "preprocessing": {
            "hand_detection": "MediaPipe HandLandmarker",
            "num_hands": MP_MAX_HANDS,
            "landmarks_per_hand": NUM_LANDMARKS_PER_HAND,
            "landmark_dimensions": LANDMARK_DIMS,
            "feature_dim": TOTAL_FEATURES,
            "sequence_length": TARGET_SEQ_LEN,
            "normalization": "wrist-centered + scale by max landmark distance",
            "missing_hand": "zero-pad to 63 dims",
            "hand_ordering": "sorted by wrist x-coordinate (left first)",
        },

        "training": {
            "val_accuracy": round(val_acc, 4) if val_acc else None,
        },

        "export": {
            "quantized": quantized,
            "precision": "int8_weights_float32_activations" if quantized else "float32",
            "file_size_mb": round(size_mb, 2),
            "total_parameters": count_parameters(model),
        },

        "flutter_integration": {
            "package": "tflite_flutter: ^0.10.4",
            "usage": (
                "final interpreter = await Interpreter.fromAsset('sign_language_model.tflite');\n"
                "var input = [landmarks]; // shape [1, 30, 126]\n"
                "var output = List.filled(1 * 8, 0.0).reshape([1, 8]);\n"
                "interpreter.run(input, output);\n"
                "// Apply softmax to output[0] to get probabilities"
            ),
        },
    }

    meta_path = os.path.join(EXPORT_DIR, "model_meta.json")
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)
    print(f"  Saved: {meta_path}")
    return meta_path


def save_labels() -> str:
    """Save class labels in index order, one label per line."""
    labels_path = os.path.join(EXPORT_DIR, "labels.txt")
    with open(labels_path, "w", encoding="utf-8") as f:
        for cls in CLASSES:
            f.write(f"{cls}\n")
    print(f"  Saved: {labels_path}")
    return labels_path


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Export BiLSTM model to TFLite for Flutter")
    parser.add_argument("--checkpoint", type=str, default=None,
                        help=f"Path to model checkpoint (default: {BEST_MODEL_PATH})")
    parser.add_argument("--model", type=str, default=None, choices=["main", "light"],
                        help="Model variant (auto-detected from checkpoint)")
    parser.add_argument("--quantize", action="store_true",
                        help="Apply dynamic range quantization (smaller model, minor accuracy loss)")
    args = parser.parse_args()

    ckpt_path = args.checkpoint or BEST_MODEL_PATH

    if not os.path.isfile(ckpt_path):
        print(f"[ERROR] Checkpoint not found: {ckpt_path}")
        print("  Run train.py first.")
        sys.exit(1)

    os.makedirs(EXPORT_DIR, exist_ok=True)
    device = torch.device("cpu")  # Export always on CPU

    # =========================================================================
    # Load model
    # =========================================================================
    print("=" * 60)
    print("Export BiLSTM -> TFLite for Flutter")
    print("=" * 60)

    ckpt = torch.load(ckpt_path, map_location=device, weights_only=False)
    model_class_name = ckpt.get("model_class", "BiLSTMAttention")
    val_acc = ckpt.get("val_acc", None)

    if args.model == "light" or model_class_name == "LightBiLSTM":
        model = LightBiLSTM().to(device)
    else:
        model = BiLSTMAttention().to(device)

    model.load_state_dict(ckpt["model_state_dict"])
    model.eval()

    print(f"  Model:      {model.__class__.__name__}")
    print(f"  Parameters: {count_parameters(model):,}")
    print(f"  Val acc:    {val_acc}")
    print(f"  Quantize:   {args.quantize}")

    # =========================================================================
    # Step 1: PyTorch -> ONNX
    # =========================================================================
    print(f"\n--- Step 1: PyTorch -> ONNX ---")
    onnx_path = os.path.join(EXPORT_DIR, "sign_language_model.onnx")
    export_to_onnx(model, onnx_path, device)

    # =========================================================================
    # Step 2: ONNX -> TFLite
    # =========================================================================
    print(f"\n--- Step 2: ONNX -> TFLite ---")
    tflite_path = os.path.join(EXPORT_DIR, "sign_language_model.tflite")
    size_mb = export_to_tflite(onnx_path, tflite_path, model, device, quantize=args.quantize)

    # =========================================================================
    # Step 3: Verify
    # =========================================================================
    print(f"\n--- Step 3: Verify TFLite ---")
    try:
        verify_tflite(tflite_path, model, device)
    except Exception as e:
        print(f"  [WARN] Verification failed: {e}")
        print(f"  The model was still exported -- test it manually in Flutter.")

    # =========================================================================
    # Step 4: Save metadata
    # =========================================================================
    print(f"\n--- Step 4: Save metadata ---")
    meta_path = save_metadata(tflite_path, model, val_acc, size_mb, args.quantize)

    # =========================================================================
    # Step 5: Save labels
    # =========================================================================
    print(f"\n--- Step 5: Save labels ---")
    labels_path = save_labels()

    # =========================================================================
    # Summary
    # =========================================================================
    print(f"\n{'=' * 60}")
    print(f"EXPORT COMPLETE")
    print(f"{'=' * 60}")
    print(f"\nFiles for Flutter (copy to assets/):")
    print(f"  1. {tflite_path}")
    print(f"     -> {size_mb:.2f} MB, {'quantized' if args.quantize else 'float32'}")
    print(f"  2. {meta_path}")
    print(f"     -> Class labels, preprocessing config")
    print(f"  3. {labels_path}")
    print(f"     -> One class label per line (index-aligned)")
    print(f"\nFlutter pubspec.yaml:")
    print(f"  dependencies:")
    print(f"    tflite_flutter: ^0.10.4")
    print(f"  flutter:")
    print(f"    assets:")
    print(f"      - assets/sign_language_model.tflite")
    print(f"      - assets/model_meta.json")
    print(f"      - assets/labels.txt")
    print(f"\nClass mapping:")
    for i, cls in enumerate(CLASSES):
        print(f"  {i}: {cls}")
    print()


if __name__ == "__main__":
    main()
