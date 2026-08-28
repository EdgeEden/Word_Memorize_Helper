import 'package:flutter/material.dart';
import '../controllers/quiz_controller.dart';
import '../services/fsrs_repository.dart';

/// Modern Material 3 Login & User Registration Dialog
class LoginDialog extends StatefulWidget {
  final QuizController controller;
  final bool isSwitchAccount;

  const LoginDialog({
    super.key,
    required this.controller,
    this.isSwitchAccount = false,
  });

  static Future<bool?> show(
    BuildContext context,
    QuizController controller, {
    bool isSwitchAccount = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: isSwitchAccount,
      builder: (context) => LoginDialog(
        controller: controller,
        isSwitchAccount: isSwitchAccount,
      ),
    );
  }

  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
  late final TextEditingController _usernameController;
  late final TextEditingController _serverController;
  List<String> _userHistory = [];
  bool _showServerConfig = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  late final FocusNode _usernameFocusNode;

  @override
  void initState() {
    super.initState();
    _usernameFocusNode = FocusNode();
    _usernameController = TextEditingController(text: widget.controller.currentUsername ?? '');
    _serverController = TextEditingController(text: widget.controller.serverUrl);
    _loadUserHistory();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _usernameFocusNode.requestFocus();
      }
    });
  }

  Future<void> _loadUserHistory() async {
    final list = await FsrsRepository.getUserHistory();
    if (mounted) {
      setState(() {
        _userHistory = list;
      });
    }
  }

  @override
  void dispose() {
    _usernameFocusNode.dispose();
    _usernameController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      setState(() {
        _errorMessage = '请输入用户名';
      });
      return;
    }

    if (username.length < 2) {
      setState(() {
        _errorMessage = '用户名长度至少为 2 个字符';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    // Update server URL if changed
    final customServer = _serverController.text.trim();
    if (customServer.isNotEmpty && customServer != widget.controller.serverUrl) {
      await widget.controller.updateServerUrl(customServer);
    }

    final success = await widget.controller.login(username);
    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _errorMessage = '登录/注册失败，请检查输入或服务器连接';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: widget.isSwitchAccount,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.account_circle_rounded, color: colorScheme.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Text(
              widget.isSwitchAccount ? '切换用户账户' : '欢迎使用 WordN',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isSwitchAccount
                      ? '请输入要切换的用户名。错题本与 FSRS 记忆状态将与该账户独立绑定。'
                      : '请输入唯一用户名进行登录/注册。错题本与复习进度将实时同步至 Python 云端后端。',
                  style: TextStyle(fontSize: 13, height: 1.4, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),

                // Username input field
                TextField(
                  controller: _usernameController,
                  focusNode: _usernameFocusNode,
                  decoration: InputDecoration(
                    labelText: '用户名称 (Username)',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    hintText: '如: alex, study_2026',
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    errorText: _errorMessage,
                  ),
                  onSubmitted: (_) => _handleLogin(),
                ),

                if (_userHistory.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '已保存的历史登录账户:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _userHistory.map((u) {
                      final isCurrent = u.toLowerCase() == _usernameController.text.toLowerCase();
                      return ActionChip(
                        avatar: Icon(
                          Icons.person,
                          size: 14,
                          color: isCurrent ? colorScheme.primary : null,
                        ),
                        label: Text(
                          u,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        onPressed: () {
                          _usernameController.text = u;
                          _handleLogin();
                        },
                      );
                    }).toList(),
                  ),
                ],

                const SizedBox(height: 12),

                // Toggle Server Configuration
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    setState(() {
                      _showServerConfig = !_showServerConfig;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showServerConfig ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                        Text(
                          _showServerConfig ? '隐藏服务器配置' : '高级：配置后端服务器地址',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_showServerConfig) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _serverController,
                    decoration: InputDecoration(
                      labelText: '后端 API 地址',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      hintText: 'http://127.0.0.1:8000',
                      prefixIcon: const Icon(Icons.dns_outlined, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      helperText: 'Windows/Web 默认 127.0.0.1:8000，Android 模拟器 10.0.2.2:8000',
                      helperMaxLines: 2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (widget.isSwitchAccount)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
          FilledButton.icon(
            onPressed: _isSubmitting ? null : _handleLogin,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.login_rounded, size: 18),
            label: Text(_isSubmitting ? '同步中...' : '进入学习 (开启云同步)'),
          ),
        ],
      ),
    );
  }
}

/// Account details & Cloud Sync Status Modal Dialog
class AccountInfoDialog extends StatefulWidget {
  final QuizController controller;

  const AccountInfoDialog({super.key, required this.controller});

  static Future<void> show(BuildContext context, QuizController controller) {
    return showDialog(
      context: context,
      builder: (context) => AccountInfoDialog(controller: controller),
    );
  }

  @override
  State<AccountInfoDialog> createState() => _AccountInfoDialogState();
}

class _AccountInfoDialogState extends State<AccountInfoDialog> {
  late final TextEditingController _serverController;
  bool _isEditingServer = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: widget.controller.serverUrl);
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  Widget _buildSyncStatusBadge(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_done_rounded, color: Colors.green, size: 18),
            SizedBox(width: 6),
            Text('已与云端同步', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        );
      case SyncStatus.syncing:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber)),
            SizedBox(width: 6),
            Text('正在双向同步...', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        );
      case SyncStatus.offline:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: Colors.grey, size: 18),
            SizedBox(width: 6),
            Text('离线运行模式', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        );
      case SyncStatus.failed:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
            SizedBox(width: 6),
            Text('同步出错 (离线保存中)', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final controller = widget.controller;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: Icon(Icons.person_rounded, color: colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                controller.currentUsername ?? '未登录',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              _buildSyncStatusBadge(controller.syncStatus),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Statistics Summary
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem('已追踪词条', '${controller.totalTrackedCardsCount}'),
                    _buildStatItem('待复习', '${controller.dueReviewCount}', color: Colors.orange),
                    _buildStatItem('高危顽固', '${controller.criticalCount}', color: Colors.redAccent),
                    _buildStatItem('趋于掌握', '${controller.masteredCount}', color: Colors.green),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Server Address config
              Text('后端服务地址', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary)),
              const SizedBox(height: 6),
              if (_isEditingServer)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _serverController,
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () async {
                        await controller.updateServerUrl(_serverController.text);
                        setState(() {
                          _isEditingServer = false;
                        });
                      },
                      child: const Text('保存'),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        controller.serverUrl,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _isEditingServer = true;
                        });
                      },
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('修改'),
                    ),
                  ],
                ),

              const SizedBox(height: 16),

              // Force Sync Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isSyncing
                      ? null
                      : () async {
                          setState(() {
                            _isSyncing = true;
                          });
                          await controller.syncNow();
                          if (mounted) {
                            setState(() {
                              _isSyncing = false;
                            });
                          }
                        },
                  icon: _isSyncing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync_rounded),
                  label: Text(_isSyncing ? '正在同步...' : '立即与云端双向同步'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            Navigator.of(context).pop();
            await LoginDialog.show(context, controller, isSwitchAccount: true);
          },
          icon: const Icon(Icons.switch_account_rounded, size: 18),
          label: const Text('切换用户'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}
