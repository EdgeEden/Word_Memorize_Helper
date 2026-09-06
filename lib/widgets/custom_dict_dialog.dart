import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../controllers/quiz_controller.dart';
import '../models/dict_info.dart';
import '../services/dict_service.dart';

/// Modal dialog for managing and importing custom CSV vocabulary dictionaries
class CustomDictDialog extends StatefulWidget {
  final QuizController controller;

  const CustomDictDialog({super.key, required this.controller});

  @override
  State<CustomDictDialog> createState() => _CustomDictDialogState();
}

class _CustomDictDialogState extends State<CustomDictDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  String? _selectedFileName;
  String? _selectedFileContent;
  CustomDictValidationResult? _validationResult;
  bool _isReadingFile = false;
  bool _isSaving = false;
  String? _formError;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  /// Pick and parse CSV file cross-platform (Web, Android, iOS, Windows, macOS, Linux)
  Future<void> _pickCsvFile() async {
    setState(() {
      _formError = null;
      _isReadingFile = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
        withData: true, // Crucial for Web and universal in-memory byte access
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isReadingFile = false);
        return;
      }

      final file = result.files.single;
      _selectedFileName = file.name;

      String rawContent = '';
      Uint8List? byteData = file.bytes;

      if (byteData == null && file.readStream != null) {
        final chunks = await file.readStream!.toList();
        byteData = Uint8List.fromList(chunks.expand((b) => b).toList());
      }

      if (byteData != null && byteData.isNotEmpty) {
        try {
          rawContent = utf8.decode(byteData);
        } catch (_) {
          try {
            rawContent = utf8.decode(byteData, allowMalformed: true);
          } catch (_) {
            rawContent = latin1.decode(byteData);
          }
        }
      }

      if (rawContent.trim().isEmpty) {
        setState(() {
          _isReadingFile = false;
          _validationResult = const CustomDictValidationResult(
            isValid: false,
            errorMessage: '文件内容为空或无法解码，请选择有效的 CSV 词库文件',
          );
        });
        return;
      }

      // Auto-fill dictionary name from filename if name is empty
      if (_nameController.text.trim().isEmpty) {
        final autoName = file.name.replaceAll(RegExp(r'\.csv$', caseSensitive: false), '');
        if (autoName.isNotEmpty) {
          _nameController.text = autoName;
        }
      }

      final validation = DictService.validateAndParseCsv(rawContent);
      setState(() {
        _selectedFileContent = rawContent;
        _validationResult = validation;
        _isReadingFile = false;
      });
    } catch (e) {
      setState(() {
        _isReadingFile = false;
        _validationResult = CustomDictValidationResult(
          isValid: false,
          errorMessage: '选择或读取文件失败: $e',
        );
      });
    }
  }

  /// Handle saving and importing custom dictionary
  Future<void> _handleImport({required bool switchImmediately}) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _formError = '请输入词库名称');
      return;
    }

    if (name.length > 20) {
      setState(() => _formError = '词库名称不能超过 20 个字');
      return;
    }

    // Check duplicate name
    final isDuplicate = widget.controller.availableDicts.any(
      (d) => d.name.toLowerCase() == name.toLowerCase(),
    );
    if (isDuplicate) {
      setState(() => _formError = '已存在名为「$name」的词库，请设定其他名称');
      return;
    }

    if (_selectedFileContent == null || _validationResult?.isValid != true) {
      setState(() => _formError = '请先选择并解析有效的 CSV 词库文件');
      return;
    }

    setState(() {
      _isSaving = true;
      _formError = null;
    });

    try {
      final desc = _descController.text.trim();
      final newDict = await widget.controller.importCustomDict(
        name: name,
        description: desc.isNotEmpty ? desc : null,
        csvContent: _selectedFileContent!,
        switchImmediately: switchImmediately,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              switchImmediately
                  ? '已成功导入并切换至「${newDict.name}」（共 ${newDict.estimatedCount} 词）'
                  : '已成功导入「${newDict.name}」（共 ${newDict.estimatedCount} 词）',
            ),
            backgroundColor: Colors.teal,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
        _formError = '导入失败: $e';
      });
    }
  }

  /// Confirm delete custom dictionary
  Future<void> _confirmDeleteDict(DictInfo dict) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 22),
            const SizedBox(width: 8),
            Text('删除「${dict.name}」', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '确定要删除此自定义词库吗？\n该词库的所有本地数据及对应的错题记录将一并删除。',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await widget.controller.deleteCustomDict(dict.id);
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已删除词库「${dict.name}」'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final customDicts = widget.controller.availableDicts.where((d) => d.isCustom).toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.library_add_rounded, color: colorScheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          const Text(
            '自定义词库管理与导入',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // -------------------------------------------------------------
              // 1. Existing Custom Dictionaries Section
              // -------------------------------------------------------------
              if (customDicts.isNotEmpty) ...[
                Text(
                  '已导入的自定义词库 (${customDicts.length})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: customDicts.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, index) {
                      final dict = customDicts[index];
                      final isCurrent = dict.id == widget.controller.currentDictId;

                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.folder_special_rounded,
                            color: isCurrent ? colorScheme.primary : colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                          title: Row(
                            children: [
                              Text(
                                dict.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isCurrent ? colorScheme.primary : null,
                                ),
                              ),
                              if (isCurrent) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '当前使用',
                                    style: TextStyle(fontSize: 10, color: colorScheme.primary, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            '${dict.estimatedCount} 词 · ${dict.description}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isCurrent)
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () async {
                                    await widget.controller.switchDict(dict.id);
                                    setState(() {});
                                  },
                                  child: const Text('切换', style: TextStyle(fontSize: 12)),
                                ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                                tooltip: '删除词库',
                                onPressed: () => _confirmDeleteDict(dict),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                const Divider(height: 1),
                const SizedBox(height: 14),
              ],

              // -------------------------------------------------------------
              // 2. Import New Dictionary Form
              // -------------------------------------------------------------
              Text(
                '导入新词库',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),

              // Dictionary Name
              Text(
                '词库辨识名称 *',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                maxLength: 20,
                decoration: InputDecoration(
                  hintText: '如: 雅思核心 3000 / 托福听力词汇',
                  prefixIcon: const Icon(Icons.label_outline_rounded, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onChanged: (_) {
                  if (_formError != null) setState(() => _formError = null);
                },
              ),
              const SizedBox(height: 10),

              // Dictionary Description
              Text(
                '词库描述 (选填)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _descController,
                maxLength: 40,
                decoration: InputDecoration(
                  hintText: '如: 个人高频生词整理',
                  prefixIcon: const Icon(Icons.notes_rounded, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 14),

              // File Picker Section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _validationResult?.isValid == true
                        ? Colors.green.withValues(alpha: 0.5)
                        : colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _isReadingFile ? null : _pickCsvFile,
                          icon: _isReadingFile
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.file_upload_outlined, size: 18),
                          label: Text(_selectedFileName != null ? '重新选择 CSV 文件' : '选择 CSV 文件'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selectedFileName ?? '未选择文件 (支持 Web / Android / Windows)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: _selectedFileName != null ? FontWeight.bold : FontWeight.normal,
                              color: _selectedFileName != null ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    // Validation & Preview
                    if (_validationResult != null) ...[
                      const SizedBox(height: 10),
                      if (_validationResult!.isValid) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    '成功解析 ${_validationResult!.wordCount} 个有效单词',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              if (_validationResult!.sampleWords.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '词汇示例: ${_validationResult!.sampleWords.map((w) => '${w.word} (${w.definition.length > 8 ? '${w.definition.substring(0, 8)}…' : w.definition})').join('、 ')}',
                                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, color: colorScheme.error, size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _validationResult!.errorMessage ?? 'CSV 解析失败',
                                  style: TextStyle(fontSize: 12, color: colorScheme.error),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // CSV Format Specification Collapsible Card
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  collapsedBackgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  collapsedShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  leading: Icon(Icons.help_outline_rounded, size: 18, color: colorScheme.primary),
                  title: Text(
                    '查看 CSV 格式规范与示例',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.surface.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '📌 支持的列结构 (2 ~ 5 列，以英文逗号分隔)：',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '• 2 列格式: [ 单词, 释义 ]\n'
                            '• 3 列格式: [ 单词, 音标, 释义 ]\n'
                            '• 4 列格式: [ 单词, 音标, 释义, 英文例句 ]\n'
                            '• 5 列格式: [ 单词, 音标, 释义, 英文例句, 中文例句 ]',
                            style: TextStyle(fontSize: 11.5, height: 1.5, color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '📝 标准 CSV 内容示例：',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: SelectableText(
                              '单词,音标,释义,英文例句,中文例句\n'
                              'apple,/ˈæpl/,苹果,I eat an apple.,我吃了一个苹果。\n'
                              'abandon,/əˈbændən/,"放弃, 抛弃",Never abandon hope.,绝不放弃希望。',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                height: 1.4,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '💡 导入说明：\n'
                            '1. 文件编码推荐 UTF-8（已兼容 GBK/ANSI 编码）；\n'
                            '2. 首行如果是英文或中文表头（如 word/单词 等），系统将自动识别并跳过；\n'
                            '3. 释义或例句中若含有逗号，请使用英文双引号 " " 包裹；\n'
                            '4. 单词自动剔除空格并忽略大小写去重。',
                            style: TextStyle(fontSize: 11, height: 1.45, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Form Error Banner
              if (_formError != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: colorScheme.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(_formError!, style: TextStyle(fontSize: 12, color: colorScheme.error)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: (_isSaving || _validationResult?.isValid != true)
              ? null
              : () => _handleImport(switchImmediately: false),
          child: const Text('仅导入'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: (_isSaving || _validationResult?.isValid != true)
              ? null
              : () => _handleImport(switchImmediately: true),
          icon: _isSaving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_rounded, size: 16),
          label: Text(_isSaving ? '正在导入...' : '导入并立即切换'),
        ),
      ],
    );
  }
}
