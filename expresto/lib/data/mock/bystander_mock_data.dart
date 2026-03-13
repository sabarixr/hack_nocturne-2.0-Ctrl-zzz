import 'package:expresto/models/bystander_data.dart';

const BystanderData bystanderMockData = BystanderData(
  title: 'Bystander',
  alertMessage: 'Helping a deaf person in emergency',
  summaryTitle: 'Emergency Summary',
  summaryItems: <BystanderSummaryItem>[
    BystanderSummaryItem(label: 'Type', value: 'MEDICAL - Cardiac'),
    BystanderSummaryItem(label: 'Patient', value: 'Mother, ~62 yrs'),
    BystanderSummaryItem(label: 'Symptoms', value: 'Chest pain'),
    BystanderSummaryItem(label: 'Status', value: 'Conscious, lying flat'),
  ],
  arrivalMessage: 'Ambulance arriving in 3 minutes',
  instructionsTitle: 'INSTRUCTIONS FOR YOU',
  instructions: <String>[
    'Keep patient lying flat',
    'Loosen tight clothing',
    'Monitor breathing',
    'Stay calm, reassure patient',
    'Do NOT move patient unless necessary',
  ],
  quickPhrasesTitle: 'QUICK PHRASES',
  quickPhrases: <BystanderQuickPhrase>[
    BystanderQuickPhrase(
      label: 'Patient conscious',
      sentiment: QuickPhraseSentiment.positive,
    ),
    BystanderQuickPhrase(
      label: 'Breathing OK',
      sentiment: QuickPhraseSentiment.positive,
    ),
    BystanderQuickPhrase(
      label: 'Pain worsening',
      sentiment: QuickPhraseSentiment.warning,
    ),
    BystanderQuickPhrase(
      label: 'Unconscious',
      sentiment: QuickPhraseSentiment.danger,
    ),
  ],
  inputHint: 'Patient says pain is worsening...',
  operatorLabel: 'MESSAGE TO OPERATOR',
  operatorMessage:
      'Patient is conscious and breathing. Chest pain is increasing.',
  showAvatarLabel: 'Show avatar for deaf person',
);
