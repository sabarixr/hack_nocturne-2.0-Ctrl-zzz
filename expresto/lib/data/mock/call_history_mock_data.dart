import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/models/call_history_data.dart';

const CallHistoryData callHistoryMockData = CallHistoryData(
  title: 'History',
  filters: <CallHistoryFilter>[
    CallHistoryFilter(label: 'All', type: null),
    CallHistoryFilter(label: 'Emergency', type: CallHistoryType.emergency),
    CallHistoryFilter(label: 'Live Calls', type: CallHistoryType.live),
  ],
  entries: <CallHistoryEntry>[
    CallHistoryEntry(
      type: CallHistoryType.emergency,
      title: 'Emergency Call',
      dateTimeLabel: 'March 4, 2026 - 3:42 PM',
      badgeLabel: 'Resolved',
      badgeColor: AppColors.success,
      metadata: <CallHistoryMeta>[
        CallHistoryMeta(label: 'Type', value: 'Medical - Cardiac'),
        CallHistoryMeta(label: 'Duration', value: '4m 35s'),
        CallHistoryMeta(
          label: 'Peak urgency',
          value: '92%',
          valueColor: AppColors.emergency,
        ),
      ],
      actions: <String>['View Transcript', 'Share Report'],
    ),
    CallHistoryEntry(
      type: CallHistoryType.live,
      title: 'Live Call - Mom',
      dateTimeLabel: 'March 3, 2026 - 7:15 PM',
      badgeLabel: '94% quality',
      badgeColor: AppColors.blue,
      metadata: <CallHistoryMeta>[
        CallHistoryMeta(label: 'Duration', value: '12m 08s'),
      ],
      actions: <String>['View Details'],
    ),
    CallHistoryEntry(
      type: CallHistoryType.live,
      title: 'Live Call - Dr. Patel',
      dateTimeLabel: 'March 1, 2026 - 10:30 AM',
      badgeLabel: '91% quality',
      badgeColor: AppColors.blue,
      metadata: <CallHistoryMeta>[
        CallHistoryMeta(label: 'Duration', value: '8m 22s'),
      ],
      actions: <String>['View Details'],
    ),
  ],
);
