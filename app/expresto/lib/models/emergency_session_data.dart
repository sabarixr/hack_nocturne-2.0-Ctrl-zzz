import 'package:flutter/material.dart';

class EmergencySessionData {
  const EmergencySessionData({
    required this.headerTag,
    required this.callState,
    required this.timer,
    required this.liveIndicator,
    required this.cameraHint,
    required this.urgencyLabel,
    required this.urgencyPercent,
    required this.urgencyStatus,
    required this.urgencyBars,
    required this.operatorTitle,
    required this.operatorEta,
    required this.actionsTitle,
    required this.actions,
  });

  final String headerTag;
  final String callState;
  final String timer;
  final String liveIndicator;
  final String cameraHint;
  final String urgencyLabel;
  final int urgencyPercent;
  final String urgencyStatus;
  final List<int> urgencyBars;
  final String operatorTitle;
  final String operatorEta;
  final String actionsTitle;
  final List<EmergencyActionItem> actions;
}

class EmergencyActionItem {
  const EmergencyActionItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}
