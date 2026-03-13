import 'package:flutter/material.dart';

class PracticeCategory {
  final IconData icon;
  final String title;
  final String subtitle;
  final double progress;
  final Color progressColor;
  final Color? borderColor;
  final Color? iconBgColor;
  final Color? arrowColor;
  final String routeKey;

  const PracticeCategory({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.progressColor,
    this.borderColor,
    this.iconBgColor,
    this.arrowColor,
    required this.routeKey,
  });
}

class PracticeDashboardData {
  final int overallProgress;
  final int currentStreak;
  final int signsLearned;
  final int totalSigns;
  final int averageAccuracy;
  final List<PracticeCategory> categories;

  const PracticeDashboardData({
    required this.overallProgress,
    required this.currentStreak,
    required this.signsLearned,
    required this.totalSigns,
    required this.averageAccuracy,
    required this.categories,
  });
}
