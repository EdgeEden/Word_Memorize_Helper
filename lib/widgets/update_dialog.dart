import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/android_download_service.dart';
import '../services/update_service.dart';

/// Modal dialog that alerts the user about a newly available version
class UpdateDialog extends StatelessWidget {
  final AppVersionInfo info;
  final String currentVersion;
  final VoidCallback? onDismiss;

  const UpdateDialog({
    super.key,
    required this.info,
    required this.currentVersion,
    this.onDismiss,
  });

  /// Show the Update Dialog
  static Future<void> show(
    BuildContext context, {
    required AppVersionInfo info,
    required String currentVersion,
    VoidCallback? onDismiss,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (ctx) => PopScope(
        canPop: !info.forceUpdate,
        child: UpdateDialog(
          info: info,
          currentVersion: currentVersion,
          onDismiss: onDismiss,
        ),
      ),
    );
  }

  void _handleUpdate(BuildContext context) async {
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    if (isAndroid) {
      // Android: launch OTA update with progress dialog
      Navigator.of(context).pop();
      OtaDownloadDialog.show(
        context,
        apkUrl: info.apkUrl,
        title: info.title,
        versionInfo: info,
        currentVersion: currentVersion,
      );
    } else {
      // Windows or Web: launch external browser download
      final downloadUrl = (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)
          ? (info.windowsUrl.isNotEmpty ? info.windowsUrl : info.apkUrl)
          : info.apkUrl;

      if (downloadUrl.isNotEmpty) {
        final uri = Uri.parse(downloadUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('下载地址: $downloadUrl')),
            );
          }
        }
      }
      if (context.mounted && !info.forceUpdate) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: colorScheme.surface,
      elevation: 6,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with Icon and Version Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.system_update_alt_rounded,
                      color: colorScheme.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                'v$currentVersion ➔ v${info.version}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                            if (info.forceUpdate) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '重要更新',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.redAccent,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              const Divider(height: 1),
              const SizedBox(height: 14),

              // Release Notes Title
              Row(
                children: [
                  Icon(Icons.notes_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '更新日志',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Release Notes Content Box
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.25)),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    info.releaseNotes,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: colorScheme.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Bottom Actions
              Row(
                children: [
                  if (!info.forceUpdate) ...[
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          onDismiss?.call();
                        },
                        child: const Text('稍后再说'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: info.forceUpdate ? 1 : 1,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 1,
                      ),
                      onPressed: () => _handleUpdate(context),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text(
                        '立即更新',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Download and installation progress dialog for Android OTA
class OtaDownloadDialog extends StatefulWidget {
  final String apkUrl;
  final String title;
  final AppVersionInfo? versionInfo;
  final String? currentVersion;

  const OtaDownloadDialog({
    super.key,
    required this.apkUrl,
    required this.title,
    this.versionInfo,
    this.currentVersion,
  });

  static Future<void> show(
    BuildContext context, {
    required String apkUrl,
    required String title,
    AppVersionInfo? versionInfo,
    String? currentVersion,
  }) {
    final info = versionInfo ?? UpdateService.currentVersionInfo;
    final isMandatory = info?.forceUpdate ?? false;
    return showDialog(
      context: context,
      barrierDismissible: !isMandatory,
      builder: (ctx) => PopScope(
        canPop: !isMandatory,
        child: OtaDownloadDialog(
          apkUrl: apkUrl,
          title: title,
          versionInfo: info,
          currentVersion: currentVersion ?? UpdateService.currentAppVersion,
        ),
      ),
    );
  }

  @override
  State<OtaDownloadDialog> createState() => _OtaDownloadDialogState();
}

class _OtaDownloadDialogState extends State<OtaDownloadDialog> with WidgetsBindingObserver {
  int _progress = 0;
  bool _isInstalling = false;
  String? _errorMessage;
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _progress = UpdateService.currentOtaProgress;
    _isInstalling = UpdateService.isOtaInstalling;
    _errorMessage = UpdateService.currentOtaError;

    UpdateService.otaProgressNotifier.addListener(_onProgressUpdated);
    UpdateService.isOtaInstallingNotifier.addListener(_onInstallingUpdated);
    UpdateService.otaErrorNotifier.addListener(_onErrorUpdated);

    _startDownload();
    _startHeartbeatTimer();
  }

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _syncProgress();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncProgress();
    }
  }

  Future<void> _syncProgress() async {
    if (!mounted) return;
    final prog = await AndroidDownloadService.getProgress();
    if (prog != null && mounted) {
      setState(() {
        _progress = prog.progress;
        if (prog.status == AndroidDownloadStatus.successful) {
          _isInstalling = true;
        } else if (prog.status == AndroidDownloadStatus.failed) {
          _errorMessage = '下载失败 (错误代码: ${prog.reason})';
        }
      });
    }
  }

  void _onProgressUpdated() {
    if (mounted) {
      setState(() {
        _progress = UpdateService.otaProgressNotifier.value;
      });
    }
  }

  void _onInstallingUpdated() {
    if (mounted) {
      setState(() {
        _isInstalling = UpdateService.isOtaInstallingNotifier.value;
      });
    }
  }

  void _onErrorUpdated() {
    if (mounted) {
      setState(() {
        _errorMessage = UpdateService.otaErrorNotifier.value;
      });
    }
  }

  void _startDownload() {
    setState(() {
      _errorMessage = null;
    });

    UpdateService.startAndroidOtaUpdate(
      apkUrl: widget.apkUrl,
      versionInfo: widget.versionInfo,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    UpdateService.otaProgressNotifier.removeListener(_onProgressUpdated);
    UpdateService.isOtaInstallingNotifier.removeListener(_onInstallingUpdated);
    UpdateService.otaErrorNotifier.removeListener(_onErrorUpdated);
    super.dispose();
  }

  void _handleBackgroundDownload() {
    final info = widget.versionInfo ?? UpdateService.currentVersionInfo;
    final isMandatory = info?.forceUpdate ?? false;

    if (isMandatory) {
      // 强制更新拦截弹窗：告知用户可自由切换应用，等待下载完成后安装新版本，点击确定回到下载窗口，阻止用户进入主界面进行答题
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.info_outline_rounded, color: Colors.blueAccent, size: 36),
          title: const Text('强制更新提示', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          content: const Text(
            '当前为重要强制更新版本。\n\n在后台下载期间，您可以自由切换到手机其他应用。等待下载完成后将自动提示安装。\n\n点击“确定”返回下载进度窗口。',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(dialogCtx).pop(); // 关闭提示窗口，保留在当前 OtaDownloadDialog
              },
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return;
    }

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已转入后台继续下载，下载完成后将自动提示安装'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _handleCancelDownload() {
    final info = widget.versionInfo ?? UpdateService.currentVersionInfo;
    final isMandatory = info?.forceUpdate ?? false;

    UpdateService.cancelAndroidOtaUpdate();
    Navigator.of(context).pop();

    if (isMandatory && info != null) {
      // 强制更新时，点击“取消下载”只能回退到新版本介绍窗口，不能进入主界面进行答题
      UpdateDialog.show(
        context,
        info: info,
        currentVersion: widget.currentVersion ?? UpdateService.currentAppVersion ?? '1.0.0',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: colorScheme.surface,
      elevation: 6,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _errorMessage != null
                      ? Colors.redAccent.withValues(alpha: 0.12)
                      : colorScheme.primaryContainer.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _errorMessage != null
                      ? Icons.error_outline_rounded
                      : (_isInstalling ? Icons.install_mobile_rounded : Icons.cloud_download_rounded),
                  size: 36,
                  color: _errorMessage != null ? Colors.redAccent : colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                _errorMessage != null
                    ? '更新出错'
                    : (_isInstalling ? '下载完成，正在安装...' : '正在下载新版本安装包'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Subtitle / Error
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(fontSize: 13, color: Colors.redAccent[700]),
                    textAlign: TextAlign.center,
                  ),
                )
              else ...[
                Text(
                  _isInstalling ? '请在系统弹窗中确认完成应用安装' : '支持应用后台继续下载，下载完成后自动提示安装',
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _isInstalling ? null : (_progress / 100.0),
                    minHeight: 10,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),

                // Percentage
                if (!_isInstalling)
                  Text(
                    '$_progress%',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
              ],

              const SizedBox(height: 20),

              // Action Buttons
              if (_errorMessage != null)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _startDownload,
                        child: const Text('重试'),
                      ),
                    ),
                  ],
                )
              else if (!_isInstalling)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _handleCancelDownload,
                        child: const Text('取消下载'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _handleBackgroundDownload,
                        icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                        label: const Text('后台下载'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

