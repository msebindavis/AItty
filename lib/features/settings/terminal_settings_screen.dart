import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/spacing.dart';
import '../../models/app_settings.dart';
import '../../models/host.dart';
import '../../services/app_settings_repository.dart';

class TerminalSettingsScreen extends ConsumerStatefulWidget {
  const TerminalSettingsScreen({super.key});

  @override
  ConsumerState<TerminalSettingsScreen> createState() => _TerminalSettingsScreenState();
}

class _TerminalSettingsScreenState extends ConsumerState<TerminalSettingsScreen> {
  AppSettings? _settings;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await ref.read(appSettingsRepositoryProvider).load();
    if (mounted) setState(() => _settings = s);
  }

  Future<void> _save(AppSettings next) async {
    setState(() {
      _settings = next;
      _saving = true;
    });
    await ref.read(appSettingsRepositoryProvider).save(next);
    ref.invalidate(appSettingsProvider);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Terminal')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.marginMobile),
        children: [
          SwitchListTile(
            title: const Text('SSH keep-alive'),
            subtitle: const Text('Send periodic keep-alive packets'),
            value: settings.keepAliveEnabled,
            onChanged: _saving
                ? null
                : (v) => _save(settings.copyWith(keepAliveEnabled: v)),
          ),
          ListTile(
            title: const Text('Keep-alive interval'),
            subtitle: Text(_intervalLabel(settings.keepAliveIntervalSeconds)),
            trailing: DropdownButton<int>(
              value: settings.keepAliveIntervalSeconds,
              items: const [
                DropdownMenuItem(value: 0, child: Text('Off')),
                DropdownMenuItem(value: 30, child: Text('30s')),
                DropdownMenuItem(value: 60, child: Text('60s')),
                DropdownMenuItem(value: 120, child: Text('120s')),
                DropdownMenuItem(value: 300, child: Text('300s')),
              ],
              onChanged: _saving
                  ? null
                  : (v) {
                      if (v != null) _save(settings.copyWith(keepAliveIntervalSeconds: v));
                    },
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Default tmux mode'),
            subtitle: const Text('Used when host setting is Inherit'),
            trailing: DropdownButton<HostTmuxMode>(
              value: settings.defaultTmuxMode,
              items: const [
                DropdownMenuItem(value: HostTmuxMode.off, child: Text('Off')),
                DropdownMenuItem(value: HostTmuxMode.attachExisting, child: Text('Attach or create')),
                DropdownMenuItem(value: HostTmuxMode.createNew, child: Text('Create new')),
              ],
              onChanged: _saving
                  ? null
                  : (v) {
                      if (v != null) _save(settings.copyWith(defaultTmuxMode: v));
                    },
            ),
          ),
          SwitchListTile(
            title: const Text('Detach tmux on close'),
            subtitle: const Text('Leave remote tmux sessions running when closing the app'),
            value: settings.detachOnAppClose,
            onChanged: _saving
                ? null
                : (v) => _save(settings.copyWith(detachOnAppClose: v)),
          ),
        ],
      ),
    );
  }

  String _intervalLabel(int seconds) => switch (seconds) {
        0 => 'Disabled',
        30 => '30 seconds',
        60 => '60 seconds',
        120 => '2 minutes',
        300 => '5 minutes',
        _ => '$seconds seconds',
      };
}
