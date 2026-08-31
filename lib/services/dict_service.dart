import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/dict_info.dart';
import '../models/word_item.dart';

/// Result of custom CSV dictionary validation and parsing
class CustomDictValidationResult {
  final bool isValid;
  final int wordCount;
  final List<WordItem> sampleWords;
  final String? errorMessage;
  final List<WordItem> allWords;

  const CustomDictValidationResult({
    required this.isValid,
    this.wordCount = 0,
    this.sampleWords = const [],
    this.errorMessage,
    this.allWords = const [],
  });
}

class DictService {
  static const String defaultDictId = 'kaoyan4533';
  static const String defaultAssetPath = 'assets/dict/kaoyan4533.csv';
  static const String _customDictsMetaKey = 'wordn_custom_dicts_meta';
  static String _customDictContentKey(String dictId) => 'wordn_custom_dict_csv_$dictId';

  static const List<DictInfo> builtInDicts = [
    DictInfo(
      id: 'kaoyan4533',
      name: '考研 4533',
      shortName: '考研',
      description: '教育部考研英语大纲核心 4533 词汇，完整覆盖基础与重点考点',
      assetPath: 'assets/dict/kaoyan4533.csv',
      estimatedCount: 4533,
      icon: Icons.school_rounded,
    ),
    DictInfo(
      id: 'gyq',
      name: 'gyq',
      shortName: 'gyq',
      description: '考研高频重点词汇库，精选高频核心词与双语例句',
      assetPath: 'assets/dict/gyq.csv',
      estimatedCount: 1854,
      icon: Icons.local_fire_department_rounded,
    ),
  ];

  /// Loads all available dictionaries (built-in + user custom imported)
  static Future<List<DictInfo>> loadAllDicts() async {
    final customList = await loadCustomDicts();
    return [...builtInDicts, ...customList];
  }

  /// Loads only user custom imported dictionaries from SharedPreferences
  static Future<List<DictInfo>> loadCustomDicts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_customDictsMetaKey);
      if (rawList == null || rawList.isEmpty) return [];

      final List<DictInfo> result = [];
      for (final itemStr in rawList) {
        try {
          final decoded = jsonDecode(itemStr) as Map<String, dynamic>;
          final info = DictInfo.fromJson(decoded);
          // Verify that the custom CSV content exists in local storage
          final content = prefs.getString(_customDictContentKey(info.id));
          if (content != null && content.trim().isNotEmpty) {
            result.add(info);
          }
        } catch (_) {}
      }
      return result;
    } catch (e) {
      debugPrint('Error loading custom dicts: $e');
      return [];
    }
  }

  /// Retrieves DictInfo by ID from available dictionaries
  static DictInfo getDictInfo(String? id, [List<DictInfo>? availableList]) {
    final list = availableList ?? builtInDicts;
    if (id == null || id.trim().isEmpty) return list.first;
    return list.firstWhere(
      (d) => d.id.toLowerCase() == id.trim().toLowerCase(),
      orElse: () => list.first,
    );
  }

  /// Loads words for a specific DictInfo (from local storage if custom, or asset if built-in)
  static Future<List<WordItem>> loadWords(DictInfo dict) async {
    if (dict.isCustom) {
      final prefs = await SharedPreferences.getInstance();
      final rawCsv = prefs.getString(_customDictContentKey(dict.id));
      if (rawCsv == null || rawCsv.trim().isEmpty) {
        throw Exception('自定义词库「${dict.name}」数据丢失或为空');
      }
      return parseCsv(rawCsv);
    } else {
      return loadFromAsset(dict.assetPath.isNotEmpty ? dict.assetPath : defaultAssetPath);
    }
  }

  /// Loads words from the bundled CSV asset
  static Future<List<WordItem>> loadFromAsset([String path = defaultAssetPath]) async {
    try {
      final rawCsv = await rootBundle.loadString(path);
      return parseCsv(rawCsv);
    } catch (e) {
      debugPrint('Error loading dictionary asset ($path): $e');
      rethrow;
    }
  }

  /// Validates and parses raw CSV content for custom dictionary import
  static CustomDictValidationResult validateAndParseCsv(String csvContent) {
    if (csvContent.trim().isEmpty) {
      return const CustomDictValidationResult(
        isValid: false,
        errorMessage: 'CSV 文件内容为空',
      );
    }

    try {
      final words = parseCsv(csvContent);
      if (words.isEmpty) {
        return const CustomDictValidationResult(
          isValid: false,
          errorMessage: '未能从 CSV 中解析出有效单词（请确保包含单词与中文释义）',
        );
      }

      return CustomDictValidationResult(
        isValid: true,
        wordCount: words.length,
        sampleWords: words.take(3).toList(),
        allWords: words,
      );
    } catch (e) {
      return CustomDictValidationResult(
        isValid: false,
        errorMessage: 'CSV 解析失败: $e',
      );
    }
  }

  /// Saves a new custom dictionary to universal storage (Web / Android / Windows / iOS / Desktop)
  static Future<DictInfo> saveCustomDict({
    required String name,
    String? description,
    required String csvContent,
  }) async {
    final validation = validateAndParseCsv(csvContent);
    if (!validation.isValid) {
      throw Exception(validation.errorMessage ?? 'CSV 数据无效');
    }

    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw Exception('词库名称不能为空');
    }

    final dictId = 'custom_${DateTime.now().millisecondsSinceEpoch}';

    // 1. Save CSV content to universal SharedPreferences (Web localStorage / Native storage)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customDictContentKey(dictId), csvContent);

    // 2. Create DictInfo metadata
    final newDict = DictInfo(
      id: dictId,
      name: cleanName,
      shortName: cleanName.length > 6 ? '${cleanName.substring(0, 5)}…' : cleanName,
      description: description?.trim() ?? '用户自导入词库（共 ${validation.wordCount} 词）',
      assetPath: '',
      estimatedCount: validation.wordCount,
      isCustom: true,
      createdAt: DateTime.now(),
      icon: Icons.folder_special_rounded,
    );

    // 3. Save metadata entry to SharedPreferences
    final currentCustomList = prefs.getStringList(_customDictsMetaKey) ?? [];
    currentCustomList.add(jsonEncode(newDict.toJson()));
    await prefs.setStringList(_customDictsMetaKey, currentCustomList);

    return newDict;
  }

  /// Deletes a custom dictionary by ID
  static Future<void> deleteCustomDict(String dictId) async {
    final cleanId = dictId.trim().toLowerCase();
    final prefs = await SharedPreferences.getInstance();

    // 1. Remove raw CSV content
    await prefs.remove(_customDictContentKey(cleanId));

    // 2. Remove metadata entry
    final currentCustomList = prefs.getStringList(_customDictsMetaKey) ?? [];
    final List<String> updatedList = [];
    for (final itemStr in currentCustomList) {
      try {
        final decoded = jsonDecode(itemStr) as Map<String, dynamic>;
        final id = (decoded['id'] as String?)?.toLowerCase();
        if (id != cleanId) {
          updatedList.add(itemStr);
        }
      } catch (_) {
        updatedList.add(itemStr);
      }
    }
    await prefs.setStringList(_customDictsMetaKey, updatedList);
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
    final Set<String> seenWords = {};

    for (final row in rows) {
      if (row.isEmpty) continue;
      final word = row[0]?.toString().trim() ?? '';
      if (word.isEmpty) continue;

      // Skip accidental header if any
      final lower = word.toLowerCase();
      if (lower == 'word' || lower == 'words' || word == '单词' || word == '词汇') continue;

      if (seenWords.contains(lower)) continue;
      seenWords.add(lower);

      final item = WordItem.fromCsvRow(row);
      words.add(item);
    }

    return words;
  }
}
