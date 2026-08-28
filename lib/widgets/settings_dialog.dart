import 'package:flutter/material.dart';
import '../controllers/quiz_controller.dart';
import '../services/ai_service.dart';
import '../services/fsrs_repository.dart';

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

  bool _obscureApiKey = true;
  bool _isTestingApi = false;
  String? _testApiResult;
  bool? _testApiSuccess;

  @override
  void initState() {
    super.initState();
    _selectedThemeMode = widget.currentThemeMode;
    _selectedEvalMode = widget.controller.evalMode;
    _apiKeyController = TextEditingController(text: widget.controller.deepseekApiKey);
    _baseUrlController = TextEditingController(text: widget.controller.deepseekBaseUrl);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    super.dispose();
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

    setState(() {
      _isTestingApi = true;
      _testApiResult = null;
      _testApiSuccess = null;
    });

    final res = await DeepSeekService.testConnection(
      key,
      baseUrl: _baseUrlController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _isTestingApi = false;
      _testApiSuccess = res.success;
      _testApiResult = res.message;
    });
  }

  Future<void> _handleSave() async {
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
                      label: Text('DeepSeek AI 判定'),
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
                    : '🤖 DeepSeek AI 智能判定：调用大模型理解同义词、引申义及多样化中文表述，判定更精准。',
                style: TextStyle(fontSize: 12, height: 1.4, color: colorScheme.onSurfaceVariant),
              ),


              // -------------------------------------------------------------
              // 3. DeepSeek Config Box
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
                            'DeepSeek API 配置',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // API Key Field
                      TextField(
                        controller: _apiKeyController,
                        obscureText: _obscureApiKey,
                        decoration: InputDecoration(
                          labelText: 'DeepSeek API Key',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
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
                          helperText: 'API Key 将保存在本地，下次启动自动填充',
                          helperMaxLines: 2,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Base URL Field
                      TextField(
                        controller: _baseUrlController,
                        decoration: InputDecoration(
                          labelText: 'API Base URL (可选)',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          hintText: 'https://api.deepseek.com',
                          prefixIcon: const Icon(Icons.link_rounded, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Test Connection Button & Status
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _isTestingApi ? null : _testDeepSeekConnection,
                            icon: _isTestingApi
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.speed_rounded, size: 16),
                            label: Text(_isTestingApi ? '正在测试...' : '测试连通性'),
                          ),
                          const SizedBox(width: 10),
                          if (_testApiResult != null)
                            Expanded(
                              child: Row(
                                children: [
                                  Icon(
                                    _testApiSuccess == true ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                                    size: 16,
                                    color: _testApiSuccess == true ? Colors.green : Colors.redAccent,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _testApiResult!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _testApiSuccess == true ? Colors.green : Colors.redAccent,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                crossFadeState: _selectedEvalMode == EvaluationMode.deepseekAi
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 250),
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
