class BystanderData {
  const BystanderData({
    required this.title,
    required this.alertMessage,
    required this.summaryTitle,
    required this.summaryItems,
    required this.arrivalMessage,
    required this.instructionsTitle,
    required this.instructions,
    required this.quickPhrasesTitle,
    required this.quickPhrases,
    required this.inputHint,
    required this.operatorLabel,
    required this.operatorMessage,
    required this.showAvatarLabel,
  });

  final String title;
  final String alertMessage;
  final String summaryTitle;
  final List<BystanderSummaryItem> summaryItems;
  final String arrivalMessage;
  final String instructionsTitle;
  final List<String> instructions;
  final String quickPhrasesTitle;
  final List<BystanderQuickPhrase> quickPhrases;
  final String inputHint;
  final String operatorLabel;
  final String operatorMessage;
  final String showAvatarLabel;
}

class BystanderSummaryItem {
  const BystanderSummaryItem({required this.label, required this.value});

  final String label;
  final String value;
}

class BystanderQuickPhrase {
  const BystanderQuickPhrase({required this.label, required this.sentiment});

  final String label;
  final QuickPhraseSentiment sentiment;
}

enum QuickPhraseSentiment { positive, warning, danger }
