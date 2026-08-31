import 'package:flutter/material.dart';
import '../controllers/quiz_controller.dart';
import '../services/ai_service.dart';
import '../services/fsrs_repository.dart';
import '../services/update_service.dart';
import '../widgets/custom_dict_dialog.dart';
import '../widgets/update_dialog.dart';

/// Unified Settings Dialog for Appearance Theme & Answer Evaluation Methods
class SettingsDialog extends StatefulWidget {
  final QuizController controller;
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  const SettingsDialog({
    super.key,
    required this.controller,
    required this.currentThemeMode,
    required this.onThemeChanged,
  });

  static Future<void> show(
    BuildContext context,
    QuizController controller, {
    required ThemeMode currentThemeMode,
    required ValueChanged<ThemeMode> onThemeChanged,
  }) {
    return showDialog(
      context: context,
      builder: (context) => SettingsDialog(
        controller: controller,
        currentThemeMode: currentThemeMode,
        onThemeChanged: onThemeChanged,
      ),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late ThemeMode _selectedThemeMode;
  late EvaluationMode _selectedEvalMode;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _baseUrlController;

  String _selectedModel = '';
  List<String> _availableModels = [];
  bool _isFetchingModels = false;
  String? _fetchModelsResult;
  bool? _fetchModelsSuccess;

  bool _obscureApiKey = true;
  bool _isTestingApi = false;
  String? _testApiResult;
  bool? _testApiSuccess;

  String _currentAppVersion = '1.0.0';
  int _currentBuildNumber = 1;
  bool _isCheckingUpdate = false;

  String _lastApiKeyText = '';
  String _lastBaseUrlText = '';

  @override
  void initState() {
    super.initState();
    _selectedThemeMode = widget.currentThemeMode;
    _selectedEvalMode = widget.controller.evalMode;
    _apiKeyController = TextEditingController(text: widget.controller.deepseekApiKey);
    _baseUrlController = TextEditingController(text: widget.controller.deepseekBaseUrl);

    final savedKey = widget.controller.deepseekApiKey.trim();
    final savedModel = widget.controller.deepseekModel.trim();
    if (savedKey.isNotEmpty && savedModel.isNotEmpty) {
      _selectedModel = savedModel;
      _availableModels = [savedModel];
    } else {
      _selectedModel = '';
      _availableModels = [];
    }

    _lastApiKeyText = _apiKeyController.text;
    _lastBaseUrlText = _baseUrlController.text;
    _apiKeyController.addListener(_onApiConfigChanged);
    _baseUrlController.addListener(_onApiConfigChanged);

    _loadAppVersion();
  }

  void _onApiConfigChanged() {
    final currentKey = _apiKeyController.text;
    final currentBase = _baseUrlController.text;
    if (currentKey != _lastApiKeyText || currentBase != _lastBaseUrlText) {
      _lastApiKeyText = currentKey;
      _lastBaseUrlText = currentBase;
      if (_selectedModel.isNotEmpty || _availableModels.isNotEmpty || _fetchModelsResult != null) {
        setState(() {
          _selectedModel = '';
          _availableModels = [];
          _fetchModelsResult = null;
          _fetchModelsSuccess = null;
          _testApiResult = null;
          _testApiSuccess = null;
        });
      }
    }
  }

  Future<void> _loadAppVersion() async {
    final info = await UpdateService.getCurrentAppVersion();
    if (mounted) {
      setState(() {
        _currentAppVersion = info['version'] as String? ?? '1.0.0';
        _currentBuildNumber = info['buildNumber'] as int? ?? 1;
      });
    }
  }

  @override
  void dispose() {
    _apiKeyController.removeListener(_onApiConfigChanged);
    _baseUrlController.removeListener(_onApiConfigChanged);
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _fetchAvailableModels() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _fetchModelsSuccess = false;
        _fetchModelsResult = '请先输入 API Key 再获取模型列表';
      });
      return;
    }

    setState(() {
      _isFetchingModels = true;
      _fetchModelsResult = null;
      _fetchModelsSuccess = null;
    });

    final models = await DeepSeekService.fetchAvailableModels(
      key,
      baseUrl: _baseUrlController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _isFetchingModels = false;
      if (models.isNotEmpty) {
        _availableModels = models;
        _selectedModel = models.first; // Default to first in the list
        _fetchModelsSuccess = true;
        _fetchModelsResult = '已获取 ${models.length} 个可用模型，已默认选中首项';
      } else {
        _fetchModelsSuccess = false;
        _fetchModelsResult = '未能自动获取到模型，请检查网络或 Base URL';
      }
    });
  }

  Future<void> _testDeepSeekConnection() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _testApiSuccess = false;
        _testApiResult = '请输入 API Key 后再进行连通性测试';
      });
      return;
    }

    String modelToTest = _selectedModel.trim();
    if (modelToTest.isEmpty) {
      if (_availableModels.isEmpty) {
        await _fetchAvailableModels();
        modelToTest = _selectedModel.trim();
      }
      if (modelToTest.isEmpty) {
        modelToTest = DeepSeekService.defaultModel;
      }
    }

    setState(() {
      _isTestingApi = true;
      _testApiResult = null;
      _testApiSuccess = null;
    });

    final res = await DeepSeekService.testConnection(
      key,
      baseUrl: _baseUrlController.text.trim(),
      model: modelToTest,
    );

    if (!mounted) return;

    setState(() {
      _isTestingApi = false;
      _testApiSuccess = res.success;
      _testApiResult = res.message;
    });
  }

  Future<void> _showAlertDialog({required String title, required String message}) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Colors.orangeAccent, size: 22),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 13, height: 1.5)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSave() async {
    // If AI mode is selected, validate API key and model selection
    if (_selectedEvalMode == EvaluationMode.deepseekAi) {
      final key = _apiKeyController.text.trim();
      if (key.isEmpty) {
        await _showAlertDialog(
          title: '请配置 API Key',
          message: '您选择了 AI 判定模式，但尚未输入 API Key。请先填写 API Key 并获取选择模型。',
        );
        return;
      }

      if (_selectedModel.trim().isEmpty) {
        await _showAlertDialog(
          title: '请选择 AI 模型',
          message: '当前尚未选择要使用的 AI 模型。请点击【获取模型】按钮获取可用模型列表，并选择使用的模型。',
        );
        return;
      }
    }

    // 1. Save Theme
    widget.onThemeChanged(_selectedThemeMode);
    final themeString = _selectedThemeMode == ThemeMode.dark
        ? 'dark'
        : (_selectedThemeMode == ThemeMode.light ? 'light' : 'system');
    await FsrsRepository.setThemeMode(themeString);

    // 2. Save Eval Mode
    await widget.controller.setEvalMode(_selectedEvalMode);

    // 3. Save DeepSeek Config
    await widget.controller.updateDeepSeekConfig(
      apiKey: _apiKeyController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      model: _selectedModel.trim(),
    );

    if (mounted) {
      Navigator.of(context).pop();
    }
  }



  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.tune_rounded, color: colorScheme.primary, size: 24),
          ),
          const SizedBox(width: 12),
          const Text(
            '偏好设置',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // -------------------------------------------------------------
              // 1. Theme Selection
              // -------------------------------------------------------------
              _buildSectionTitle(context, Icons.palette_outlined, '外观与颜色主题'),
              const SizedBox(height: 10),
              Center(
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_rounded, size: 18),
                      label: Text('亮色'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_rounded, size: 18),
                      label: Text('暗色'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_rounded, size: 18),
                      label: Text('跟随系统'),
                    ),
                  ],
                  selected: {_selectedThemeMode},
                  onSelectionChanged: (Set<ThemeMode> newSelection) {
                    setState(() {
                      _selectedThemeMode = newSelection.first;
                    });
                  },
                ),
              ),

              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 18),

              // -------------------------------------------------------------
              // 2. Answer Evaluation Method Selection
              // -------------------------------------------------------------
              _buildSectionTitle(context, Icons.psychology_outlined, '答案判定方式'),
              const SizedBox(height: 10),

              Center(
                child: SegmentedButton<EvaluationMode>(
                  segments: const [
                    ButtonSegment(
                      value: EvaluationMode.localMatcher,
                      icon: Icon(Icons.flash_on_rounded, size: 18),
                      label: Text('词典本地匹配'),
                    ),
                    ButtonSegment(
                      value: EvaluationMode.deepseekAi,
                      icon: Icon(Icons.auto_awesome_rounded, size: 18),
                      label: Text('AI 判定'),
                    ),
                  ],
                  selected: {_selectedEvalMode},
                  onSelectionChanged: (Set<EvaluationMode> newSelection) {
                    setState(() {
                      _selectedEvalMode = newSelection.first;
                    });
                  },
                ),
              ),

              const SizedBox(height: 10),
              Text(
                _selectedEvalMode == EvaluationMode.localMatcher
                    ? '⚡ 本地词典匹配：通过离线词库分词和关键词包含快速判定，无网络延迟。'
                    : '🤖 AI 智能判定：调用大模型理解同义词、引申义及多样化中文表述，判定更精准。',
                style: TextStyle(fontSize: 12, height: 1.4, color: colorScheme.onSurfaceVariant),
              ),

              // -------------------------------------------------------------
              // 3. AI Config Box
              // -------------------------------------------------------------
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.key_rounded, size: 16, color: colorScheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            'AI API 与模型配置',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // API Key Field
                      Text(
                        'API Key',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _apiKeyController,
                        obscureText: _obscureApiKey,
                        decoration: InputDecoration(
                          hintText: 'sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
                          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureApiKey ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureApiKey = !_obscureApiKey;
                              });
                            },
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          helperText: 'API Key将保存在本地',
                          helperMaxLines: 2,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Base URL Field
                      Text(
                        'API Base URL',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _baseUrlController,
                        decoration: InputDecoration(
                          hintText: 'https://api.deepseek.com',
                          prefixIcon: const Icon(Icons.link_rounded, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Model Dropdown Selection
                      Text(
                        '选择使用的 AI 模型',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        key: ValueKey('$_selectedModel-${_availableModels.length}'),
                        initialValue: _availableModels.contains(_selectedModel) && _selectedModel.isNotEmpty
                            ? _selectedModel
                            : null,
                        hint: Text(
                          _availableModels.isEmpty ? '请先点击下方按钮获取模型' : '请选择模型',
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.smart_toy_outlined, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        isExpanded: true,
                        items: _availableModels.map((m) {
                          return DropdownMenuItem<String>(
                            value: m,
                            child: Text(
                              m,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedModel = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),

                      // Action Buttons Row: Fetch Models & Test Connection
                      Row(
                        children: [
                          // Button 1: 获取模型 (Primary Tonal)
                          Expanded(
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _isFetchingModels ? null : _fetchAvailableModels,
                              icon: _isFetchingModels
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.sync_rounded, size: 16),
                              label: Text(_isFetchingModels ? '获取中...' : '获取模型'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Button 2: 测试连通性 (Tertiary Tonal with distinct color)
                          Expanded(
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                backgroundColor: colorScheme.tertiaryContainer.withValues(alpha: 0.7),
                                foregroundColor: colorScheme.onTertiaryContainer,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _isTestingApi ? null : _testDeepSeekConnection,
                              icon: _isTestingApi
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.speed_rounded, size: 16),
                              label: Text(_isTestingApi ? '测试中...' : '测试连通性'),
                            ),
                          ),
                        ],
                      ),

                      // Status & Result feedback
                      if (_fetchModelsResult != null || _testApiResult != null) ...[
                        const SizedBox(height: 8),
                        if (_fetchModelsResult != null)
                          Row(
                            children: [
                              Icon(
                                _fetchModelsSuccess == true ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                size: 14,
                                color: _fetchModelsSuccess == true ? Colors.green : Colors.orangeAccent,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _fetchModelsResult!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _fetchModelsSuccess == true ? Colors.green : Colors.orangeAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (_fetchModelsResult != null && _testApiResult != null)
                          const SizedBox(height: 4),
                        if (_testApiResult != null)
                          Row(
                            children: [
                              Icon(
                                _testApiSuccess == true ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                                size: 14,
                                color: _testApiSuccess == true ? Colors.green : Colors.redAccent,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _testApiResult!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _testApiSuccess == true ? Colors.green : Colors.redAccent,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ],
                  ),
                ),
                crossFadeState: _selectedEvalMode == EvaluationMode.deepseekAi
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 250),
              ),

              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 18),

              // -------------------------------------------------------------
              // 4. About and App Update
              // -------------------------------------------------------------
              _buildSectionTitle(context, Icons.info_outline_rounded, '关于与软件更新'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'WordN 考研词汇助手',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '当前版本: v$_currentAppVersion (Build $_currentBuildNumber)',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isCheckingUpdate ? null : _handleManualCheckUpdate,
                      icon: _isCheckingUpdate
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 16),
                      label: Text(_isCheckingUpdate ? '检查中...' : '检查更新'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // -------------------------------------------------------------
              // 5. Advanced Options (Collapsible)
              // -------------------------------------------------------------
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  collapsedBackgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  collapsedShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  leading: Icon(Icons.tune_rounded, size: 20, color: colorScheme.primary),
                  title: const Text(
                    '高级选项',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '自定义词库导入、本地与云端错题本重置',
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    // Item 1: Custom Dictionary Management
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.library_add_rounded, size: 20, color: colorScheme.primary),
                      ),
                      title: const Text('自定义词库管理与导入', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '导入自定义 CSV 词库文件，支持多端增量同步',
                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                      ),
                      trailing: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _handleOpenCustomDictManagement,
                        icon: const Icon(Icons.settings_outlined, size: 16),
                        label: const Text('管理与导入', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const Divider(height: 20),

                    // Item 2: Clear Wrong Book Data
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.delete_sweep_rounded, size: 20, color: colorScheme.error),
                      ),
                      title: const Text('清除错题本与复习数据', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '重置当前词库或所有词库的 FSRS 记忆曲线与错题记录（同步删除云端）',
                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                      ),
                      trailing: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.error,
                          side: BorderSide(color: colorScheme.error.withValues(alpha: 0.6)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _showClearWrongBookDialog,
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        label: const Text('清除数据', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _handleSave,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('保存并应用'),
        ),
      ],
    );
  }

  Future<void> _handleManualCheckUpdate() async {
    setState(() {
      _isCheckingUpdate = true;
    });

    final res = await widget.controller.checkForUpdates();

    if (!mounted) return;
    setState(() {
      _isCheckingUpdate = false;
    });

    if (res.hasUpdate && res.latestInfo != null) {
      UpdateDialog.show(
        context,
        info: res.latestInfo!,
        currentVersion: res.currentVersion,
      );
    } else if (res.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.errorMessage!),
          backgroundColor: Colors.redAccent,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已是最新版本 (v${res.currentVersion})，无需更新'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _handleOpenCustomDictManagement() async {
    await showDialog(
      context: context,
      builder: (_) => CustomDictDialog(controller: widget.controller),
    );
    if (mounted) setState(() {});
  }

  Future<void> _showClearWrongBookDialog() async {
    final currentDict = widget.controller.currentDict;
    int selectedOption = 1; // 1: current dict, 2: all dicts

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final theme = Theme.of(dialogCtx);
            final colorScheme = theme.colorScheme;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
                  const SizedBox(width: 8),
                  const Text('清除错题本与复习数据', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '该操作将彻底重置您在所选词库中的 FSRS 记忆曲线、熟练度等级与所有错题记录，并同步清除云端对应的已同步数据。',
                      style: TextStyle(fontSize: 13, height: 1.4, color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),
                    const Text('请选择清除范围：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setDialogState(() => selectedOption = 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              selectedOption == 1 ? Icons.radio_button_checked : Icons.radio_button_off,
                              size: 20,
                              color: selectedOption == 1 ? colorScheme.primary : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('仅清除当前词库 (${currentDict.name})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  Text('仅重置「${currentDict.name}」的错题本，不影响其他词库', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setDialogState(() => selectedOption = 2),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              selectedOption == 2 ? Icons.radio_button_checked : Icons.radio_button_off,
                              size: 20,
                              color: selectedOption == 2 ? Colors.redAccent : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('清除所有词库（全部重置）', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.redAccent)),
                                  Text('重置所有内置与自定义词库的记忆记录', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.of(dialogCtx).pop(true),
                  child: const Text('确认清除'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true && mounted) {
      final success = await widget.controller.clearWrongBookData(clearAll: selectedOption == 2);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (selectedOption == 2 ? '已成功清除所有词库的错题本数据' : '已成功清除「${currentDict.name}」的错题本数据')
                : '清除错题本数据失败，请重试',
          ),
          backgroundColor: success ? Colors.teal : Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildSectionTitle(BuildContext context, IconData icon, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
