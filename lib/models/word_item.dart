class WordItem {
  final String word;
  final String phonetic;
  final String definition;
  final String exampleEn;
  final String exampleCn;

  const WordItem({
    required this.word,
    required this.phonetic,
    required this.definition,
    required this.exampleEn,
    required this.exampleCn,
  });

  /// Factory constructor to create WordItem from CSV row list
  factory WordItem.fromCsvRow(List<dynamic> row) {
    String getCol(int index) {
      if (index < row.length) {
        return row[index]?.toString().trim() ?? '';
      }
      return '';
    }

    return WordItem(
      word: getCol(0),
      phonetic: getCol(1),
      definition: getCol(2),
      exampleEn: getCol(3),
      exampleCn: getCol(4),
    );
  }

  /// Extracts individual clean Chinese keyword candidates from the definition
  List<String> get cleanKeywords {
    final raw = definition;
    // Replace POS tags (n., v., adj., etc.) and human name annotations with delimiter
    final cleaned = raw
        .replaceAll(
          RegExp(
            r'(\b(n|v|vt|vi|adj|adv|prep|pron|conj|art|int|num|abbr)\b\.?|\[.*?\]|\(.*?\)|（.*?）)',
            caseSensitive: false,
          ),
          '；',
        )
        .replaceAll(RegExp(r'[…~_]'), '');

    final tokens = cleaned.split(RegExp(r'[；;,，/、\s\n]+'));
    final Set<String> keywords = {};

    for (final token in tokens) {
      final trimmed = token.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9]'), '').trim();
      if (trimmed.isNotEmpty) {
        keywords.add(trimmed);
      }
    }
    return keywords.toList();
  }

  /// Checks if user input matches the word's Chinese definition.
  bool checkAnswer(String userInput) {
    final input = userInput.trim();
    if (input.isEmpty) return false;

    // Normalize user input: remove Chinese/English punctuation and spaces
    final cleanInput = input
        .replaceAll(RegExp(r'[\s，。！？、；;：:"\u201c\u201d\u2018\u2019\(\)（）…~·_—\-]'), '')
        .toLowerCase();

    if (cleanInput.isEmpty) return false;

    // 1. Direct containment check in raw definition (ignoring symbols)
    final normalizedRawDef = definition
        .replaceAll(RegExp(r'[\s，。！？、；;：:"\u201c\u201d\u2018\u2019\(\)（）…~·_—\-]'), '')
        .toLowerCase();
    if (normalizedRawDef.contains(cleanInput)) {
      return true;
    }

    // 2. Match against extracted keywords
    final keywords = cleanKeywords;
    for (final kw in keywords) {
      final cleanKw = kw.toLowerCase();
      if (cleanKw == cleanInput) return true;

      // If user input is at least 1 character and keyword contains user input
      if (cleanKw.contains(cleanInput)) return true;

      // If keyword is at least 2 characters (or single char if input is short) and user input contains keyword
      if (cleanKw.length >= 2 && cleanInput.contains(cleanKw)) return true;
      if (cleanKw.length == 1 && cleanInput == cleanKw) return true;
    }

    return false;
  }
}

