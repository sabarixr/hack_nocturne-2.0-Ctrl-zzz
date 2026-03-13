import 'package:flutter/material.dart';

class SilentModeData {
  const SilentModeData({
    required this.title,
    required this.cancelLabel,
    required this.brightnessLabel,
    required this.cameraStatus,
    required this.statusItems,
    required this.hapticTitle,
    required this.haptics,
    required this.exitHint,
  });

  final String title;
  final String cancelLabel;
  final String brightnessLabel;
  final String cameraStatus;
  final List<SilentStatusItem> statusItems;
  final String hapticTitle;
  final List<SilentHapticItem> haptics;
  final String exitHint;
}

class SilentStatusItem {
  const SilentStatusItem({
    required this.label,
    this.icon,
    this.isAccent = false,
    this.showDot = false,
  });

  final String label;
  final IconData? icon;
  final bool isAccent;
  final bool showDot;
}

class SilentHapticItem {
  const SilentHapticItem({
    required this.pattern,
    required this.label,
    this.isDanger = false,
  });

  final String pattern;
  final String label;
  final bool isDanger;
}
