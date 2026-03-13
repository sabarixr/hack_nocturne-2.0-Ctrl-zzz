from __future__ import annotations

import tensorflow as tf
import numpy as np

from .config import DEFAULT_CLASSIFICATION_LEARNING_RATE, DEFAULT_DROPOUT, NUM_LANDMARKS
from .features import region_indices


@tf.keras.utils.register_keras_serializable(package="emotion_pipeline")
class RegionTokenStack(tf.keras.layers.Layer):
    def call(self, inputs: list[tf.Tensor]) -> tf.Tensor:
        return tf.stack(inputs, axis=1)

    def compute_output_shape(self, input_shape):
        if not input_shape:
            return input_shape
        batch = input_shape[0][0]
        feature_dim = input_shape[0][1]
        return (batch, len(input_shape), feature_dim)


@tf.keras.utils.register_keras_serializable(package="emotion_pipeline")
class ClassBalancedFocalLoss(tf.keras.losses.Loss):
    def __init__(self, alpha, gamma: float = 2.0, name: str = "class_balanced_focal_loss"):
        super().__init__(name=name)
        self.alpha = [float(value) for value in alpha]
        self.gamma = float(gamma)

    def call(self, y_true: tf.Tensor, y_pred: tf.Tensor) -> tf.Tensor:
        y_true = tf.cast(y_true, tf.float32)
        y_pred = tf.cast(y_pred, tf.float32)
        y_pred = tf.clip_by_value(y_pred, 1e-7, 1.0 - 1e-7)

        alpha = tf.constant(self.alpha, dtype=tf.float32)
        alpha_factor = tf.reduce_sum(y_true * alpha, axis=-1)
        p_t = tf.reduce_sum(y_true * y_pred, axis=-1)
        focal_factor = tf.pow(1.0 - p_t, self.gamma)
        ce = -tf.reduce_sum(y_true * tf.math.log(y_pred), axis=-1)
        return alpha_factor * focal_factor * ce

    def get_config(self):
        return {"alpha": self.alpha, "gamma": self.gamma, **super().get_config()}


def landmark_residual_block(x: tf.Tensor, filters: int, kernel_size: int, dropout_rate: float, block_name: str) -> tf.Tensor:
    shortcut = x
    y = tf.keras.layers.SeparableConv1D(filters, kernel_size, padding="same", use_bias=False, name=f"{block_name}_sepconv1")(x)
    y = tf.keras.layers.BatchNormalization(name=f"{block_name}_bn1")(y)
    y = tf.keras.layers.ReLU(name=f"{block_name}_relu1")(y)
    y = tf.keras.layers.Dropout(dropout_rate, name=f"{block_name}_drop1")(y)
    y = tf.keras.layers.SeparableConv1D(filters, kernel_size, padding="same", use_bias=False, name=f"{block_name}_sepconv2")(y)
    y = tf.keras.layers.BatchNormalization(name=f"{block_name}_bn2")(y)

    if shortcut.shape[-1] != filters:
        shortcut = tf.keras.layers.Dense(filters, use_bias=False, name=f"{block_name}_proj")(shortcut)
        shortcut = tf.keras.layers.BatchNormalization(name=f"{block_name}_proj_bn")(shortcut)

    y = tf.keras.layers.Add(name=f"{block_name}_add")([shortcut, y])
    y = tf.keras.layers.ReLU(name=f"{block_name}_relu2")(y)
    return y


def region_branch(region_input: tf.Tensor, filters: int, block_prefix: str, dropout_rate: float) -> tf.Tensor:
    x = tf.keras.layers.LayerNormalization(name=f"{block_prefix}_norm")(region_input)
    x = tf.keras.layers.Dense(filters, activation="relu", name=f"{block_prefix}_proj")(x)
    x = landmark_residual_block(x, filters=filters, kernel_size=3, dropout_rate=dropout_rate, block_name=f"{block_prefix}_block1")
    x = landmark_residual_block(x, filters=filters, kernel_size=3, dropout_rate=dropout_rate, block_name=f"{block_prefix}_block2")
    avg_pool = tf.keras.layers.GlobalAveragePooling1D(name=f"{block_prefix}_avg")(x)
    max_pool = tf.keras.layers.GlobalMaxPooling1D(name=f"{block_prefix}_max")(x)
    pooled = tf.keras.layers.Concatenate(name=f"{block_prefix}_pool_concat")([avg_pool, max_pool])
    return tf.keras.layers.Dense(128, activation="relu", name=f"{block_prefix}_summary")(pooled)


def build_emotion_model(
    num_classes: int,
    engineered_dim: int,
    learning_rate: float = DEFAULT_CLASSIFICATION_LEARNING_RATE,
    dropout_rate: float = DEFAULT_DROPOUT,
    focal_alpha: list[float] | tuple[float, ...] | np.ndarray | None = None,
    focal_gamma: float = 2.0,
) -> tf.keras.Model:
    regions = region_indices()
    landmarks_input = tf.keras.Input(shape=(NUM_LANDMARKS, 3), name="landmarks")
    engineered_input = tf.keras.Input(shape=(engineered_dim,), name="engineered_features")
    left_eye_brow_input = tf.keras.Input(shape=(len(regions["left_eye_brow"]), 3), name="left_eye_brow")
    right_eye_brow_input = tf.keras.Input(shape=(len(regions["right_eye_brow"]), 3), name="right_eye_brow")
    mouth_input = tf.keras.Input(shape=(len(regions["mouth"]), 3), name="mouth")
    nose_input = tf.keras.Input(shape=(len(regions["nose"]), 3), name="nose")

    x = tf.keras.layers.LayerNormalization(name="landmark_norm")(landmarks_input)
    x = tf.keras.layers.Dense(64, activation="relu", name="point_projection")(x)
    x = landmark_residual_block(x, filters=64, kernel_size=5, dropout_rate=dropout_rate, block_name="block1")
    x = landmark_residual_block(x, filters=128, kernel_size=5, dropout_rate=dropout_rate, block_name="block2")

    attention = tf.keras.layers.MultiHeadAttention(num_heads=4, key_dim=32, dropout=dropout_rate, name="self_attention")(x, x)
    x = tf.keras.layers.Add(name="attention_add")([x, attention])
    x = tf.keras.layers.LayerNormalization(name="attention_norm")(x)
    x = landmark_residual_block(x, filters=128, kernel_size=3, dropout_rate=dropout_rate, block_name="block3")

    avg_pool = tf.keras.layers.GlobalAveragePooling1D(name="avg_pool")(x)
    max_pool = tf.keras.layers.GlobalMaxPooling1D(name="max_pool")(x)
    left_region = region_branch(left_eye_brow_input, filters=64, block_prefix="left_region", dropout_rate=dropout_rate)
    right_region = region_branch(right_eye_brow_input, filters=64, block_prefix="right_region", dropout_rate=dropout_rate)
    mouth_region = region_branch(mouth_input, filters=96, block_prefix="mouth_region", dropout_rate=dropout_rate)
    nose_region = region_branch(nose_input, filters=64, block_prefix="nose_region", dropout_rate=dropout_rate)
    geometry = tf.keras.layers.Dense(64, activation="relu", name="geometry_dense")(engineered_input)
    geometry = tf.keras.layers.Dropout(dropout_rate * 0.5, name="geometry_dropout")(geometry)

    region_tokens = RegionTokenStack(name="region_token_stack")([left_region, right_region, mouth_region, nose_region])
    cross_region_attention = tf.keras.layers.MultiHeadAttention(
        num_heads=4,
        key_dim=32,
        dropout=dropout_rate,
        name="cross_region_attention",
    )(region_tokens, region_tokens)
    cross_region_attention = tf.keras.layers.Add(name="cross_region_add")([region_tokens, cross_region_attention])
    cross_region_attention = tf.keras.layers.LayerNormalization(name="cross_region_norm")(cross_region_attention)
    cross_region_summary = tf.keras.layers.GlobalAveragePooling1D(name="cross_region_avg")(cross_region_attention)

    x = tf.keras.layers.Concatenate(
        name="fusion_concat"
    )([avg_pool, max_pool, left_region, right_region, mouth_region, nose_region, cross_region_summary, geometry])
    x = tf.keras.layers.Dense(384, activation="relu", name="fusion_dense1")(x)
    x = tf.keras.layers.Dropout(dropout_rate, name="fusion_dropout1")(x)
    x = tf.keras.layers.Dense(192, activation="relu", name="fusion_dense2")(x)
    x = tf.keras.layers.Dropout(dropout_rate * 0.5, name="fusion_dropout2")(x)
    outputs = tf.keras.layers.Dense(num_classes, activation="softmax", dtype="float32", name="emotion_probabilities")(x)

    model = tf.keras.Model(
        inputs={
            "landmarks": landmarks_input,
            "engineered_features": engineered_input,
            "left_eye_brow": left_eye_brow_input,
            "right_eye_brow": right_eye_brow_input,
            "mouth": mouth_input,
            "nose": nose_input,
        },
        outputs=outputs,
        name="emotion_landmark_multibranch_encoder",
    )
    if focal_alpha is None:
        focal_alpha = np.ones(num_classes, dtype=np.float32).tolist()
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=learning_rate, clipnorm=1.0),
        loss=ClassBalancedFocalLoss(alpha=focal_alpha, gamma=focal_gamma),
        metrics=["accuracy"],
        jit_compile=False,
    )
    return model
