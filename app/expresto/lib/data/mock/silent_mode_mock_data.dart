import 'package:expresto/models/silent_mode_data.dart';
import 'package:flutter/material.dart';

const SilentModeData silentModeMockData = SilentModeData(
  title: 'SILENT MODE',
  cancelLabel: 'Cancel',
  brightnessLabel: 'Screen brightness : 10%',
  cameraStatus: 'CAMERA ACTIVE - LOW LIGHT',
  statusItems: <SilentStatusItem>[
    SilentStatusItem(label: 'POLICE NOTIFIED', isAccent: true, showDot: true),
    SilentStatusItem(label: 'GPS SHARED', icon: Icons.location_on_rounded),
    SilentStatusItem(label: 'ALL AUDIO OFF', icon: Icons.volume_off_rounded),
    SilentStatusItem(label: 'STAY HIDDEN', isAccent: true),
    SilentStatusItem(label: 'HELP COMING', isAccent: true),
  ],
  hapticTitle: 'HAPTIC FEEDBACK GUIDE',
  haptics: <SilentHapticItem>[
    SilentHapticItem(pattern: '.  .', label: 'Message received'),
    SilentHapticItem(pattern: '.  .  .', label: 'Help dispatched'),
    SilentHapticItem(pattern: '.  .  .  .', label: 'Stay where you are'),
    SilentHapticItem(
      pattern: '.  .  .  .  .',
      label: 'DANGER - MOVE NOW',
      isDanger: true,
    ),
  ],
  exitHint: 'Triple-tap screen to exit',
);
