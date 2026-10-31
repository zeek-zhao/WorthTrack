import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:worthtrack/core/module/module_providers.dart';
import 'package:worthtrack/core/pin/pin_lock.dart';
import 'package:worthtrack/core/providers.dart';
import 'package:worthtrack/ui/settings/backup_section.dart';
import 'package:worthtrack/ui/settings/pin_dialogs.dart';
import 'package:worthtrack/ui/settings/settings_section.dart';

/// 系统设置页（#45 拆分后）。
///
/// 只有两类内容：
/// 1. **core 系统设置**——PIN 锁、整库备份恢复、模块管理；
/// 2. **各模块 `settingsTiles` 贡献的条目**——如 finance 的「导出流水（CSV）」。
///
/// 设置页本身不认识任何具体模块：新增模块不需要改这个文件。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  /// null = 读取中。
  bool? _hasPin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hasPin = await ref.read(pinRepositoryProvider).hasPin();
    if (!mounted) return;
    setState(() => _hasPin = hasPin);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onTogglePin(bool enable) async {
    final repo = ref.read(pinRepositoryProvider);
    if (enable) {
      final pin = await showDialog<String>(
        context: context,
        builder: (_) => const PinSetupDialog(title: '设置启动 PIN'),
      );
      if (pin == null || !mounted) return;
      await repo.setPin(pin);
      if (!mounted) return;
      setState(() => _hasPin = true);
      _toast('已开启启动 PIN 锁');
      return;
    }

    // 关闭前先验证当前 PIN：避免手机被他人短暂拿到时顺手把锁关掉。
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) =>
          PinVerifyDialog(title: '关闭 PIN 锁', verify: repo.verifyPin),
    );
    if (ok != true || !mounted) return;
    await repo.clearPin();
    if (!mounted) return;
    setState(() => _hasPin = false);
    _toast('已关闭启动 PIN 锁');
  }

  Future<void> _onChangePin() async {
    final repo = ref.read(pinRepositoryProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) =>
          PinVerifyDialog(title: '验证当前 PIN', verify: repo.verifyPin),
    );
    if (ok != true || !mounted) return;
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const PinSetupDialog(title: '设置新 PIN'),
    );
    if (pin == null || !mounted) return;
    await repo.setPin(pin);
    if (!mounted) return;
    _toast('PIN 已更新');
  }

  @override
  Widget build(BuildContext context) {
    final hasPin = _hasPin;
    final moduleContext = ref.watch(moduleContextProvider);
    // 只有**启用中**的模块才贡献设置条目：停用后入口应当一起消失，
    // 否则「停用了还看得见它的导出按钮」会让人以为没停用成功。
    final moduleTiles = [
      for (final module in ref.watch(enabledModulesProvider))
        ...module.settingsTiles(moduleContext),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const SettingsSectionHeader('安全'),
          SwitchListTile(
            key: const Key('pin_switch'),
            secondary: const Icon(Icons.lock_outline),
            title: const Text('启动 PIN 锁'),
            subtitle: Text(
              hasPin == null
                  ? '读取中…'
                  : hasPin
                  ? '打开应用或从后台返回时需要输入 $pinLength 位 PIN'
                  : '未开启，任何人打开应用都能直接查看账目',
            ),
            value: hasPin ?? false,
            onChanged: hasPin == null ? null : _onTogglePin,
          ),
          if (hasPin == true)
            ListTile(
              key: const Key('change_pin_tile'),
              leading: const Icon(Icons.password_outlined),
              title: const Text('修改 PIN'),
              onTap: _onChangePin,
            ),
          const SettingsHint(
            'PIN 只用于阻挡他人随手翻看，不会加密数据库文件；'
            '忘记 PIN 可以在锁屏页重置后直接进入，账目数据不会丢失。',
          ),
          const Divider(height: 1),
          const BackupSection(),
          // 模块贡献的条目（如 finance 的「数据导出」）——顺序与模块注册顺序一致。
          ...moduleTiles,
          const SettingsSectionHeader('模块'),
          ListTile(
            key: const Key('module_management_tile'),
            leading: const Icon(Icons.widgets_outlined),
            title: const Text('模块管理'),
            subtitle: const Text('启用 / 停用 / 清理数据 / 排序'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/modules'),
          ),
          const SettingsHint(
            '停用只把模块从首页隐藏，数据一条都不会删；'
            '「清理数据」才会真正删除，且无法撤销。',
          ),
          const Divider(height: 1),
          const SettingsSectionHeader('关于'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('WorthTrack'),
            subtitle: Text('本地记账，数据只存在这台设备上'),
          ),
        ],
      ),
    );
  }
}
