import 'package:flutter/material.dart';

class LessonFeedback {
  final IconData icon;
  final String text;

  const LessonFeedback({required this.icon, required this.text});
}

class LessonData {
  final String title;
  final String signWord;
  final int currentStep;
  final int totalSteps;
  final double progress;
  final IconData emojiDemonstration;
  final List<String> keyPoints;
  final List<LessonFeedback> feedback;
  final int confidenceScore;
  final int attemptNumber;
  final int totalAttempts;

  const LessonData({
    required this.title,
    required this.signWord,
    required this.currentStep,
    required this.totalSteps,
    required this.progress,
    required this.emojiDemonstration,
    required this.keyPoints,
    required this.feedback,
    required this.confidenceScore,
    required this.attemptNumber,
    required this.totalAttempts,
  });
}
