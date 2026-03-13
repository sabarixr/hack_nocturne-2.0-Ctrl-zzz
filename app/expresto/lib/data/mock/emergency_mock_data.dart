import 'package:expresto/models/emergency_session_data.dart';
import 'package:flutter/material.dart';

const EmergencySessionData emergencyMockData = EmergencySessionData(
  headerTag: 'EMERGENCY',
  callState: 'Active Call',
  timer: '01:23',
  liveIndicator: 'LIVE - RECOGNIZING',
  cameraHint: 'Keep hands in frame',
  urgencyLabel: 'URGENCY LEVEL',
  urgencyPercent: 88,
  urgencyStatus: 'CRITICAL',
  urgencyBars: <int>[1, 3, 1, 6, 6, 4, 6, 8, 4],
  operatorTitle: 'AMBULANCE\nCOMING',
  operatorEta: '4 MINUTES',
  actionsTitle: 'ACTIONS TAKEN',
  actions: <EmergencyActionItem>[
    EmergencyActionItem(
      icon: Icons.contact_phone_rounded,
      label: 'Emergency contacts notified',
    ),
    EmergencyActionItem(
      icon: Icons.location_on_rounded,
      label: 'GPS location shared',
    ),
    EmergencyActionItem(
      icon: Icons.emergency_rounded,
      label: 'Ambulance dispatched 45s ago',
    ),
  ],
);
