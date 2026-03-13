import 'package:flutter/material.dart';

class DetectedChange {
  final String label;
  final String value;
  final Color valueColor;

  const DetectedChange({
    required this.label,
    required this.value,
    required this.valueColor,
  });
}

class CalibrationData {
  final int currentStep;
  final int totalSteps;
  final double progress;
  final String progressText;
  final String instructionText;

  final IconData audioStateIcon;
  final String audioStateText;
  final List<double> audioBars;

  final String signPromptLabel;
  final String signWord;

  final IconData detectionStatusIcon;
  final String detectionStatusText;

  final String changesCardTitle;
  final List<DetectedChange> detectedChanges;

  const CalibrationData({
    required this.currentStep,
    required this.totalSteps,
    required this.progress,
    required this.progressText,
    required this.instructionText,
    required this.audioStateIcon,
    required this.audioStateText,
    required this.audioBars,
    required this.signPromptLabel,
    required this.signWord,
    required this.detectionStatusIcon,
    required this.detectionStatusText,
    required this.changesCardTitle,
    required this.detectedChanges,
  });
}
