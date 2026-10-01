import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/locale_provider.dart';
import '../services/update_service.dart';

class AppUpdateSettings extends StatefulWidget {
  final bool allowed;
  const AppUpdateSettings({super.key, this.allowed = true});
  @override
  State<AppUpdateSettings> createState() => _AppUpdateSettingsState();
}

class _AppUpdateSettingsState extends State<AppUpdateSettings> {
  final _service = UpdateService();
  bool _busy = false;
  String _message = '';
  bool _play = false;

  @override
  void initState() {
    super.initState();
    _loadDistribution();
  }

  Future<void> _loadDistribution() async {
    try {
      final play = await _service.isPlayDistribution();
      if (mounted) setState(() => _play = play);
    } catch (_) {
      // Native methods also enforce channel separation.
    }
  }

  Future<void> _check(bool zh) async {
    if (!widget.allowed || _busy) return;
    setState(() {
      _busy = true;
      _message = zh ? '正在检查…' : 'Checking…';
    });
    try {
      if (await _service.isPlayDistribution()) {
        final opened = await _service.openStore();
        if (mounted) {
          setState(
            () => _message = opened
                ? (zh
                      ? '请在 Google Play 中检查和安装更新'
                      : 'Check and install updates in Google Play')
                : (zh
                      ? '无法打开 Google Play，请检查设备是否支持商店'
                      : 'Cannot open Google Play on this device'),
          );
        }
        return;
      }
      final current = await _service.installedVersion();
      final update = await _service.check(current);
      if (!mounted) return;
      if (update == null) {
        setState(
          () => _message = zh
              ? '当前版本 $current 已是最新正式版'
              : '$current is the latest stable version',
        );
        return;
      }
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            zh
                ? '发现新版 ${update.version}'
                : 'Update ${update.version} available',
          ),
          content: Text(
            zh
                ? '下载约 ${(update.size / 1024 / 1024).ceil()} MB。校验后由 Android 确认覆盖安装，保留商品与设置。请先完成当前订单，不要卸载旧版。'
                : 'Download about ${(update.size / 1024 / 1024).ceil()} MB. Android confirms the verified in-place upgrade, preserving items and settings. Finish the current sale first; do not uninstall.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(zh ? '稍后' : 'Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(zh ? '下载更新' : 'Download update'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      setState(
        () => _message = zh
            ? '正在下载并校验，请稍候…'
            : 'Downloading and verifying. Please wait…',
      );
      final opened = await _service.install(update);
      if (mounted) {
        setState(
          () => _message = opened
              ? (zh
                    ? '已打开 Android 安装确认；取消后可重新检查更新'
                    : 'Android install confirmation opened; check again if cancelled')
              : (zh
                    ? '请允许此应用安装更新，然后再次点击检查更新'
                    : 'Allow this app to install updates, then check again'),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = zh
              ? '更新未完成，请检查网络或稍后重试。原版本与数据保留。'
              : 'Update not completed. Check network or retry later. Your installed app and data remain available.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zh = context.watch<LocaleProvider>().tr('settings') == '设置';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              zh ? '应用更新' : 'App updates',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              _play
                  ? (zh
                        ? '此版本通过 Google Play 更新。断网不影响本地收银与打印。'
                        : 'Updates are managed by Google Play. Offline cashier and local printing remain available.')
                  : zh
                  ? '仅手动检查时联网；从公司 GitHub 获取正式版。断网不影响本地收银与打印。'
                  : 'Manual checks only. Stable releases from company GitHub. Offline cashier and local printing remain available.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || !widget.allowed ? null : () => _check(zh),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update),
              label: Text(
                _play
                    ? (zh ? '前往 Google Play' : 'Open Google Play')
                    : (zh ? '检查更新' : 'Check for updates'),
              ),
            ),
            if (!widget.allowed)
              Text(
                zh
                    ? '请先完成或清空当前购物车，再更新应用'
                    : 'Finish or clear the current cart before updating',
              ),
            if (_message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_message),
              ),
          ],
        ),
      ),
    );
  }
}
