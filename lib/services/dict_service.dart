import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/word_item.dart';

class DictService {
  static const String defaultAssetPath = 'assets/dict/kaoyan4533.csv';

  /// Loads words from the bundled CSV asset
  static Future<List<WordItem>> loadFromAsset([String path = defaultAssetPath]) async {
    try {
      final rawCsv = await rootBundle.loadString(path);
      return parseCsv(rawCsv);
    } catch (e) {
      // ignore: avoid_print
      print('Error loading dictionary asset ($path): $e');
      rethrow;
    }
  }

  /// Parses CSV string content into a list of [WordItem]s
  static List<WordItem> parseCsv(String csvContent) {
    // Normalize newlines to \n
    final normalized = csvContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    
    const decoder = CsvDecoder(
      fieldDelimiter: ',',
      quoteCharacter: '"',
      skipEmptyLines: true,
      dynamicTyping: false,
    );

    final List<List<dynamic>> rows = decoder.convert(normalized);
    final List<WordItem> words = [];

    for (final row in rows) {
      if (row.isEmpty) continue;
      final word = row[0]?.toString().trim() ?? '';
      if (word.isEmpty) continue;

      // Skip accidental header if any
      if (word.toLowerCase() == 'word' || word == '单词') continue;

      final item = WordItem.fromCsvRow(row);
      words.add(item);
    }

    return words;
  }
}

