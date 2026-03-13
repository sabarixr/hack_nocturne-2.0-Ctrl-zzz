import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/models/live_call_data.dart';
import 'package:flutter/material.dart';

const LiveCallData liveCallMockData = LiveCallData(
  title: 'Live Call',
  contactName: 'Mom',
  duration: '05:23',
  cameraLabel: 'YOUR SIGNING',
  transcriptTitle: 'CONVERSATION',
  messages: <LiveCallMessage>[
    LiveCallMessage(
      speaker: 'YOU',
      mode: 'signing',
      message: 'How are you feeling today?',
      confidenceLabel: '92% confidence',
      statusColor: AppColors.success,
    ),
    LiveCallMessage(
      speaker: 'MOM',
      mode: 'speaking -> signing via avatar',
      message: "I'm feeling much better, thanks for checking!",
      statusLabel: 'Avatar translating...',
      statusColor: AppColors.blue,
    ),
  ],
  metrics: <LiveCallMetric>[
    LiveCallMetric(value: '0.8s', label: 'Latency', color: AppColors.success),
    LiveCallMetric(value: 'High', label: 'Quality', color: AppColors.success),
    LiveCallMetric(
      value: 'Active',
      label: 'Translation',
      color: AppColors.success,
      icon: Icons.task_alt_rounded,
    ),
  ],
);
