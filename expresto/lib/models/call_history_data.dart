import 'package:flutter/material.dart';

class CallHistoryData {
  const CallHistoryData({
    required this.title,
    required this.filters,
    required this.entries,
  });

  final String title;
  final List<CallHistoryFilter> filters;
  final List<CallHistoryEntry> entries;
}

class CallHistoryFilter {
  const CallHistoryFilter({required this.label, required this.type});

  final String label;
  final CallHistoryType? type;
}

enum CallHistoryType { emergency, live }

class CallHistoryEntry {
  const CallHistoryEntry({
    required this.type,
    required this.title,
    required this.dateTimeLabel,
    required this.badgeLabel,
    required this.badgeColor,
    required this.metadata,
    required this.actions,
  });

  final CallHistoryType type;
  final String title;
  final String dateTimeLabel;
  final String badgeLabel;
  final Color badgeColor;
  final List<CallHistoryMeta> metadata;
  final List<String> actions;
}

class CallHistoryMeta {
  const CallHistoryMeta({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;
}
