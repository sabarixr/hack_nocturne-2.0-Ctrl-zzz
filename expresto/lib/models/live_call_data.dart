import 'package:flutter/material.dart';

class LiveCallData {
  const LiveCallData({
    required this.title,
    required this.contactName,
    required this.duration,
    required this.cameraLabel,
    required this.transcriptTitle,
    required this.messages,
    required this.metrics,
  });

  final String title;
  final String contactName;
  final String duration;
  final String cameraLabel;
  final String transcriptTitle;
  final List<LiveCallMessage> messages;
  final List<LiveCallMetric> metrics;
}

class LiveCallMessage {
  const LiveCallMessage({
    required this.speaker,
    required this.mode,
    required this.message,
    this.confidenceLabel,
    this.statusLabel,
    this.statusColor,
  });

  final String speaker;
  final String mode;
  final String message;
  final String? confidenceLabel;
  final String? statusLabel;
  final Color? statusColor;
}

class LiveCallMetric {
  const LiveCallMetric({
    required this.value,
    required this.label,
    required this.color,
    this.icon,
  });

  final String value;
  final String label;
  final Color color;
  final IconData? icon;
}
