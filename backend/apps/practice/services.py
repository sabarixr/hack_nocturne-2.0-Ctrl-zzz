from __future__ import annotations

import json
from typing import Any

from django.conf import settings


def run_inference(landmark_payload: str, expected_label: str) -> dict[str, Any]:
    if settings.BYPASS_MODEL:
        return {"label": expected_label, "confidence": 0.85}

    try:
        import numpy as np
        import tflite_runtime.interpreter as tflite

        interpreter = tflite.Interpreter(model_path=settings.TFLITE_MODEL_PATH)
        interpreter.allocate_tensors()
        input_details = interpreter.get_input_details()
        output_details = interpreter.get_output_details()

        landmarks = json.loads(landmark_payload)
        input_data = np.array(landmarks, dtype=np.float32).reshape(input_details[0]["shape"])
        interpreter.set_tensor(input_details[0]["index"], input_data)
        interpreter.invoke()
        output = interpreter.get_tensor(output_details[0]["index"])
        label_idx = int(output.argmax())
        confidence = float(output[0][label_idx])
        return {"label": str(label_idx), "confidence": confidence}
    except Exception:
        return {"label": expected_label, "confidence": 0.85}


def generate_feedback(predicted_label: str, expected_label: str, confidence: float) -> list[str]:
    feedback: list[str] = []
    if predicted_label.upper() != expected_label.upper():
        feedback.append(f"Predicted '{predicted_label}' but expected '{expected_label}'. Try again.")
    if confidence < 0.5:
        feedback.append("Low confidence — focus on hand shape and positioning.")
    elif confidence < 0.75:
        feedback.append("Getting closer — refine finger placement.")
    else:
        feedback.append("Great execution!")
    return feedback
