import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/quiz_controller.dart';
import '../models/fsrs/fsrs_models.dart';
import '../widgets/login_dialog.dart';

class QuizScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDarkMode;

  const QuizScreen({
    super.key,
    required this.onToggleTheme,
    required this.isDarkMode,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late final QuizController _controller;
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  late final FocusNode _nextButtonFocusNode;

  DateTime? _lastSubmitTime;
  bool _ignoreEnterUntilKeyUp = false;
  static const int _minReviewDelayMs = 300;

  @override
  void initState() {
    super.initState();
    _controller = QuizController();
    _textController = TextEditingController();
    _focusNode = FocusNode();
    _nextButtonFocusNode = FocusNode();

    _controller.addListener(_onControllerUpdate);
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);

    _initAppAndCheckLogin();
  }

  Future<void> _initAppAndCheckLogin() async {
    await _controller.init();
    if (mounted && !_controller.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_controller.isLoggedIn) {
          LoginDialog.show(context, _controller);
        }
      });
    }
  }


  void _onControllerUpdate() {
    if (mounted) {
      if (!_controller.isSubmitted) {
        _textController.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_controller.isSubmitted) {
            _focusNode.requestFocus();
          }
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _controller.isSubmitted) {
            _nextButtonFocusNode.requestFocus();
          }
        });
      }
      setState(() {});
    }
  }


  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _controller.removeListener(_onControllerUpdate);
    _textController.dispose();
    _focusNode.dispose();
    _nextButtonFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Global Hardware Keyboard handler for Enter key across all platforms
  bool _handleHardwareKey(KeyEvent event) {
    final key = event.logicalKey;
    final isEnter = key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return false;

    // When Enter key is released, reset the ignore lock
    if (event is KeyUpEvent) {
      _ignoreEnterUntilKeyUp = false;
      return false;
    }

    if (event is KeyDownEvent) {
      // Avoid intercepting if a dialog or modal is open
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
        return false;
      }

      if (_controller.isSubmitted) {
        _goToNextWord();
        return true;
      } else {
        _submitAnswer();
        return true;
      }
    }
    return false;
  }

  /// Explicitly submit answer (from input field or submit button)
  void _submitAnswer() {
    if (_controller.isSubmitted) return;
    _lastSubmitTime = DateTime.now();
    _ignoreEnterUntilKeyUp = true;
    _focusNode.unfocus();
    _controller.submitAnswer(_textController.text);
  }

  /// Explicitly advance to next word (from next button or enter key when answer is displayed)
  void _goToNextWord() {
    if (!_controller.isSubmitted) return;
    if (_ignoreEnterUntilKeyUp) return;

    if (_lastSubmitTime != null) {
      final elapsed = DateTime.now().difference(_lastSubmitTime!).inMilliseconds;
      if (elapsed < _minReviewDelayMs) {
        return;
      }
    }

    _textController.clear();
    _controller.nextWord();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_controller.isSubmitted) {
        _focusNode.requestFocus();
      }
    });
  }


  void _showFsrsMemoryDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return _FsrsMemoryDialog(controller: _controller);
      },
    );
  }

  Widget _buildSyncIcon(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return const Icon(Icons.cloud_done_rounded, color: Colors.green, size: 22);
      case SyncStatus.syncing:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
        );
      case SyncStatus.offline:
        return const Icon(Icons.cloud_off_rounded, color: Colors.grey, size: 22);
      case SyncStatus.failed:
        return const Icon(Icons.cloud_sync_outlined, color: Colors.redAccent, size: 22);
    }
  }

  String _getSyncTooltip(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return '云端已同步 (点击手动同步)';
      case SyncStatus.syncing:
        return '正在与云端双向同步...';
      case SyncStatus.offline:
        return '离线模式 (点击配置服务器/重试)';
      case SyncStatus.failed:
        return '同步失败 (点击重试)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.menu_book_rounded, color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'WordN 考研记单词',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
              ),
            ],
          ),
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 2,
          actions: [
            // User Account Chip
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ActionChip(
                avatar: CircleAvatar(
                  backgroundColor: colorScheme.primaryContainer,
                  radius: 12,
                  child: Icon(Icons.person, size: 14, color: colorScheme.primary),
                ),
                label: Text(
                  _controller.currentUsername ?? '点击登录',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _controller.isLoggedIn ? colorScheme.onSurface : colorScheme.primary,
                  ),
                ),
                onPressed: () {
                  if (_controller.isLoggedIn) {
                    AccountInfoDialog.show(context, _controller);
                  } else {
                    LoginDialog.show(context, _controller);
                  }
                },
              ),
            ),
            const SizedBox(width: 4),

            // Cloud sync status button
            IconButton(
              tooltip: _getSyncTooltip(_controller.syncStatus),
              icon: _buildSyncIcon(_controller.syncStatus),
              onPressed: () {
                if (_controller.isLoggedIn) {
                  _controller.syncNow();
                } else {
                  LoginDialog.show(context, _controller);
                }
              },
            ),

            // FSRS Memory & Wrong Words notebook button
            IconButton(
              tooltip: 'FSRS 错题与记忆库',
              icon: Badge(
                isLabelVisible: _controller.dueReviewCount > 0 || _controller.criticalCount > 0,
                backgroundColor: _controller.criticalCount > 0 ? Colors.redAccent : Colors.orange,
                label: Text(
                  _controller.dueReviewCount > 0
                      ? '${_controller.dueReviewCount}'
                      : '${_controller.criticalCount}',
                ),
                child: const Icon(Icons.psychology_outlined),
              ),
              onPressed: _showFsrsMemoryDialog,
            ),

            // Theme toggle button
            IconButton(
              tooltip: widget.isDarkMode ? '切换至亮色模式' : '切换至暗色模式',
              icon: Icon(widget.isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
              onPressed: widget.onToggleTheme,
            ),
            const SizedBox(width: 8),
          ],
        ),

        body: _controller.isLoading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: colorScheme.primary),
                    const SizedBox(height: 16),
                    const Text('正在加载考研 4533 词库...', style: TextStyle(fontSize: 14)),
                  ],
                ),
              )
            : _controller.errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
                          const SizedBox(height: 12),
                          Text(_controller.errorMessage!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => _controller.init(),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  )
                : SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Top statistics and mode indicators
                              _buildStatsHeader(context),
                              const SizedBox(height: 16),

                              // Main Word Card
                              _buildMainWordCard(context),
                              const SizedBox(height: 20),

                              // Bottom Interactive Action Buttons
                              _buildBottomActions(context),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
      );
  }


  /// Top statistics chips bar with FSRS metrics
  Widget _buildStatsHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Mode chip
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _controller.totalTrackedCardsCount > 0
                ? _controller.toggleWrongReviewMode
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _controller.isWrongReviewMode
                    ? Colors.orange.withValues(alpha: 0.15)
                    : colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _controller.isWrongReviewMode ? Icons.replay_rounded : Icons.shuffle_rounded,
                    size: 14,
                    color: _controller.isWrongReviewMode ? Colors.orange[800] : colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _controller.isWrongReviewMode ? '错题专练' : '考研词库 (4533)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _controller.isWrongReviewMode ? Colors.orange[800] : colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Stats: total, due, accuracy, streak
          Row(
            children: [
              if (_controller.dueReviewCount > 0) ...[
                _buildStatItem(
                  icon: Icons.alarm_rounded,
                  label: '待复习 ${_controller.dueReviewCount}',
                  color: Colors.amber[800]!,
                ),
                const SizedBox(width: 10),
              ],
              _buildStatItem(
                icon: Icons.check_circle_outline_rounded,
                label: '已背 ${_controller.totalAnswered}',
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              _buildStatItem(
                icon: Icons.analytics_outlined,
                label: '${_controller.accuracy.toStringAsFixed(0)}%',
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              _buildStatItem(
                icon: Icons.local_fire_department_rounded,
                label: '${_controller.streak}',
                color: _controller.streak > 0 ? Colors.deepOrange : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
        ),
      ],
    );
  }

  /// Main Card containing the English Word, Color Feedback, Phonetic, Input, Definition and Hint
  Widget _buildMainWordCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final current = _controller.currentWord;
    final currentCard = _controller.currentCard;

    if (current == null) {
      return const SizedBox.shrink();
    }

    // Determine English Word color based on submission state and correctness
    final Color wordColor;
    if (_controller.isSubmitted) {
      wordColor = _controller.isCorrect == true
          ? const Color(0xFF10B981) // Crisp modern emerald green
          : const Color(0xFFEF4444); // Crisp modern coral red
    } else {
      wordColor = colorScheme.onSurface;
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _controller.isSubmitted
              ? (_controller.isCorrect == true
                  ? const Color(0xFF10B981).withValues(alpha: 0.35)
                  : const Color(0xFFEF4444).withValues(alpha: 0.35))
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: _controller.isSubmitted ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // FSRS Memory Status Tag (Review vs New Word)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_controller.isCurrentWordReview && currentCard != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.history_rounded, size: 13, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(
                        'FSRS复习 · 留存率 ${(currentCard.getRetrievability() * 100).toStringAsFixed(0)}% · 难度 ${currentCard.difficulty.toStringAsFixed(1)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.amber[900],
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 13, color: colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        '新词学习',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 1. English Word Display with Smooth Color Transition
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
            style: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              fontFamily: theme.textTheme.headlineLarge?.fontFamily,
              color: wordColor,
            ),
            child: Text(
              current.word,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),

          // 2. Phonetic symbol (if present)
          if (current.phonetic.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '/ ${current.phonetic} /',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                  fontFamily: 'monospace',
                ),
              ),
            ),

          const SizedBox(height: 24),

          // 3. User Input Field
          TextField(
            controller: _textController,
            focusNode: _focusNode,
            readOnly: _controller.isSubmitted,
            canRequestFocus: !_controller.isSubmitted,
            textAlign: TextAlign.center,
            textInputAction: TextInputAction.done,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: _controller.isSubmitted ? '已提交答案' : '输入中文释义（按回车提交）...',
              hintStyle: TextStyle(
                fontSize: 15,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              filled: true,
              fillColor: _controller.isSubmitted
                  ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.25)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: colorScheme.primary,
                  width: 1.8,
                ),
              ),
            ),
            onSubmitted: (_) => _submitAnswer(),
          ),

          // 4. Revealed Definition & Examples when submitted (Smooth animated expand)
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: _controller.isSubmitted
                ? Column(
                    children: [
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Standard Chinese definition
                            Row(
                              children: [
                                Icon(
                                  Icons.menu_book_outlined,
                                  size: 16,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '词典标准释义',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              current.definition,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.5,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),

                            // Example sentence and Chinese translation in answer view
                            if (current.exampleEn.isNotEmpty || current.exampleCn.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Divider(
                                height: 1,
                                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Icon(
                                    Icons.format_quote_rounded,
                                    size: 16,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '例句与中文翻译',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (current.exampleEn.isNotEmpty)
                                SelectableText(
                                  current.exampleEn,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.4,
                                    fontStyle: FontStyle.italic,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              if (current.exampleCn.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                SelectableText(
                                  current.exampleCn,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          // 5. Example Sentence Hint Area (ONLY English example, NO Chinese translation)
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: _controller.showHint
                ? Column(
                    children: [
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.lightbulb_outline_rounded,
                                  size: 16,
                                  color: Colors.amber,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '例句提示',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber[800],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (current.exampleEn.isNotEmpty)
                              SelectableText(
                                current.exampleEn,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  fontStyle: FontStyle.italic,
                                  color: colorScheme.onSurface,
                                ),
                              )
                            else
                              const Text(
                                '该词条暂无英文例句',
                                style: TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                          ],
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// Bottom action button area with smooth AnimatedSwitcher transition
  Widget _buildBottomActions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: _controller.isSubmitted
          // Result/Submitted view: Only single "下一个" (Next) button
          ? SizedBox(
              key: const ValueKey('next_button_layout'),
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                focusNode: _nextButtonFocusNode,
                autofocus: true,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
                onPressed: _goToNextWord,
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                label: const Text(
                  '下一个 (Enter)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            )
          // Unsubmitted view: "提示" (Hint) button and "答案提交" (Submit) button
          : Row(
              key: const ValueKey('unsubmitted_buttons_layout'),
              children: [
                // Hint button
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        side: BorderSide(
                          color: _controller.showHint
                              ? Colors.amber
                              : colorScheme.outlineVariant,
                          width: 1.2,
                        ),
                        backgroundColor: _controller.showHint
                            ? Colors.amber.withValues(alpha: 0.1)
                            : null,
                      ),
                      onPressed: _controller.toggleHint,
                      icon: Icon(
                        _controller.showHint
                            ? Icons.lightbulb_rounded
                            : Icons.lightbulb_outline_rounded,
                        size: 20,
                        color: _controller.showHint ? Colors.amber[800] : null,
                      ),
                      label: Text(
                        _controller.showHint ? '隐藏提示' : '提示',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _controller.showHint ? Colors.amber[800] : null,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Submit button
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 1,
                      ),
                      onPressed: _submitAnswer,
                      icon: const Icon(Icons.check_rounded, size: 20),
                      label: const Text(
                        '答案提交',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}


/// FSRS Memory & Wrong Words Dialog with 3 Health Categories Filter
class _FsrsMemoryDialog extends StatefulWidget {
  final QuizController controller;

  const _FsrsMemoryDialog({required this.controller});

  @override
  State<_FsrsMemoryDialog> createState() => _FsrsMemoryDialogState();
}

class _FsrsMemoryDialogState extends State<_FsrsMemoryDialog> {
  int _selectedTabIndex = 0; // 0: 全部, 1: 🔴 顽固高危, 2: 🟡 巩固中, 3: 🟢 趋于掌握

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final allCards = widget.controller.allCards;

    List<FsrsCard> filteredCards;
    switch (_selectedTabIndex) {
      case 1:
        filteredCards = allCards.where((c) => c.category == MemoryCategory.critical).toList();
        break;
      case 2:
        filteredCards = allCards.where((c) => c.category == MemoryCategory.consolidating).toList();
        break;
      case 3:
        filteredCards = allCards.where((c) => c.category == MemoryCategory.mastered).toList();
        break;
      default:
        filteredCards = allCards;
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_rounded, color: colorScheme.primary),
              const SizedBox(width: 8),
              const Text('FSRS 错题与记忆库', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          // Category Stats Bar / Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(0, '全部 (${allCards.length})', null),
                const SizedBox(width: 8),
                _buildFilterChip(1, '🔴 顽固难词 (${widget.controller.criticalCount})', Colors.red),
                const SizedBox(width: 8),
                _buildFilterChip(2, '🟡 巩固中 (${widget.controller.consolidatingCount})', Colors.orange),
                const SizedBox(width: 8),
                _buildFilterChip(3, '🟢 趋于掌握 (${widget.controller.masterCountSafe})', Colors.green),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 540,
        height: 400,
        child: filteredCards.isEmpty
            ? Center(
                child: Text(
                  allCards.isEmpty ? '目前尚未记录复习词条，多刷几道题吧！' : '该分类下暂无词条',
                  style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                ),
              )
            : ListView.separated(
                itemCount: filteredCards.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final card = filteredCards[index];
                  final wordItem = widget.controller.getWordItem(card.word);
                  final retrievability = (card.getRetrievability() * 100).toStringAsFixed(0);

                  final Color statusColor;
                  final String statusLabel;
                  if (card.category == MemoryCategory.mastered) {
                    statusColor = Colors.green;
                    statusLabel = '已掌握';
                  } else if (card.category == MemoryCategory.critical) {
                    statusColor = Colors.red;
                    statusLabel = '高危';
                  } else {
                    statusColor = Colors.orange;
                    statusLabel = '巩固中';
                  }

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    title: Row(
                      children: [
                        Text(
                          card.word,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (wordItem != null)
                          Text(
                            wordItem.definition,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                          ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '留存率: $retrievability%',
                              style: TextStyle(fontSize: 11, color: Colors.blueGrey[700]),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '失误: ${card.lapses}次',
                              style: TextStyle(fontSize: 11, color: card.lapses > 1 ? Colors.red : Colors.blueGrey[700]),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '稳定性: ${card.stability.toStringAsFixed(1)}天',
                              style: TextStyle(fontSize: 11, color: Colors.blueGrey[700]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        if (allCards.isNotEmpty)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              widget.controller.toggleWrongReviewMode();
            },
            icon: Icon(
              widget.controller.isWrongReviewMode ? Icons.shuffle : Icons.play_arrow_rounded,
            ),
            label: Text(widget.controller.isWrongReviewMode ? '返回全部随机' : '专练错题本'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildFilterChip(int index, String label, Color? color) {
    final isSelected = _selectedTabIndex == index;
    return ChoiceChip(
      selected: isSelected,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedTabIndex = index;
          });
        }
      },
    );
  }
}

extension on QuizController {
  int get masterCountSafe => masteredCount;
}
