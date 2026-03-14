"""
Small BiLSTM + Simple Attention model for ISL gesture classification.

Architecture:
  Input (batch, 30, 126)
    → LayerNorm(126)
    → BiLSTM(hidden=64, bidirectional) → output (batch, 30, 128)
    → BiLSTM(hidden=32, bidirectional) → output (batch, 30, 64)
    → SimpleAttention → (batch, 64)
    → Dropout(0.5)
    → FC(64 → 32) → ReLU → Dropout(0.3)
    → FC(32 → 8)

Also includes LightBiLSTM with hidden=32/16 as a fallback.

Total params ~100K (main) / ~30K (light) — deliberately small to prevent
overfitting on ~421-1200 video dataset.
"""

import torch
import torch.nn as nn

from config import (
    TOTAL_FEATURES,
    NUM_CLASSES,
    LSTM_HIDDEN_1,
    LSTM_HIDDEN_2,
    LSTM_DROPOUT,
    FC_HIDDEN,
    FC_DROPOUT_1,
    FC_DROPOUT_2,
    LIGHT_LSTM_HIDDEN_1,
    LIGHT_LSTM_HIDDEN_2,
)


class SimpleAttention(nn.Module):
    """
    Simple additive attention over the time dimension.
    Input:  (batch, T, D)
    Output: (batch, D) — weighted sum across T.
    """

    def __init__(self, input_dim: int):
        super().__init__()
        self.attn = nn.Linear(input_dim, 1, bias=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: (batch, T, D)
        scores = self.attn(x)  # (batch, T, 1)
        weights = torch.softmax(scores, dim=1)  # (batch, T, 1)
        context = (x * weights).sum(dim=1)  # (batch, D)
        return context


class BiLSTMAttention(nn.Module):
    """
    Main model: BiLSTM(64) → BiLSTM(32) → Attention → FC → 8 classes.
    ~100K parameters.
    """

    def __init__(
        self,
        input_dim: int = TOTAL_FEATURES,
        hidden_1: int = LSTM_HIDDEN_1,
        hidden_2: int = LSTM_HIDDEN_2,
        num_classes: int = NUM_CLASSES,
        lstm_dropout: float = LSTM_DROPOUT,
        fc_hidden: int = FC_HIDDEN,
        fc_dropout_1: float = FC_DROPOUT_1,
        fc_dropout_2: float = FC_DROPOUT_2,
    ):
        super().__init__()

        self.layer_norm = nn.LayerNorm(input_dim)

        self.lstm1 = nn.LSTM(
            input_size=input_dim,
            hidden_size=hidden_1,
            batch_first=True,
            bidirectional=True,
            dropout=0.0,  # no dropout between layers of a single LSTM
        )

        self.lstm2 = nn.LSTM(
            input_size=hidden_1 * 2,  # bidirectional doubles output
            hidden_size=hidden_2,
            batch_first=True,
            bidirectional=True,
            dropout=0.0,
        )

        self.lstm_drop = nn.Dropout(lstm_dropout)

        attn_dim = hidden_2 * 2  # bidirectional
        self.attention = SimpleAttention(attn_dim)

        self.classifier = nn.Sequential(
            nn.Dropout(fc_dropout_1),
            nn.Linear(attn_dim, fc_hidden),
            nn.ReLU(inplace=True),
            nn.Dropout(fc_dropout_2),
            nn.Linear(fc_hidden, num_classes),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        x: (batch, T, 126)
        returns: (batch, num_classes) logits
        """
        x = self.layer_norm(x)

        out1, _ = self.lstm1(x)       # (batch, T, hidden_1*2)
        out1 = self.lstm_drop(out1)

        out2, _ = self.lstm2(out1)     # (batch, T, hidden_2*2)
        out2 = self.lstm_drop(out2)

        context = self.attention(out2)  # (batch, hidden_2*2)
        logits = self.classifier(context)  # (batch, num_classes)

        return logits


class LightBiLSTM(nn.Module):
    """
    Lighter fallback: BiLSTM(32) → BiLSTM(16) → Attention → FC → 8 classes.
    ~30K parameters. Use if the main model still overfits.
    """

    def __init__(
        self,
        input_dim: int = TOTAL_FEATURES,
        hidden_1: int = LIGHT_LSTM_HIDDEN_1,
        hidden_2: int = LIGHT_LSTM_HIDDEN_2,
        num_classes: int = NUM_CLASSES,
    ):
        super().__init__()

        self.layer_norm = nn.LayerNorm(input_dim)

        self.lstm1 = nn.LSTM(
            input_size=input_dim,
            hidden_size=hidden_1,
            batch_first=True,
            bidirectional=True,
        )

        self.lstm2 = nn.LSTM(
            input_size=hidden_1 * 2,
            hidden_size=hidden_2,
            batch_first=True,
            bidirectional=True,
        )

        attn_dim = hidden_2 * 2
        self.attention = SimpleAttention(attn_dim)

        self.classifier = nn.Sequential(
            nn.Dropout(0.4),
            nn.Linear(attn_dim, num_classes),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.layer_norm(x)
        out1, _ = self.lstm1(x)
        out2, _ = self.lstm2(out1)
        context = self.attention(out2)
        logits = self.classifier(context)
        return logits


def count_parameters(model: nn.Module) -> int:
    """Count total trainable parameters."""
    return sum(p.numel() for p in model.parameters() if p.requires_grad)


if __name__ == "__main__":
    # Quick sanity check
    batch = torch.randn(4, 30, 126)

    model_main = BiLSTMAttention()
    out = model_main(batch)
    print(f"BiLSTMAttention:  output={out.shape}  params={count_parameters(model_main):,}")

    model_light = LightBiLSTM()
    out = model_light(batch)
    print(f"LightBiLSTM:      output={out.shape}  params={count_parameters(model_light):,}")
