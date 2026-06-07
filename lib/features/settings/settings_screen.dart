import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/obsidian_colors.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.marginMobile),
        children: [
          _SettingsTile(
            icon: Icons.vpn_key_outlined,
            title: 'Key Manager',
            subtitle: 'Import and manage SSH private keys',
            onTap: () => context.push('/settings/keys'),
          ),
          _SettingsTile(
            icon: Icons.lock_outline,
            title: 'App Lock',
            subtitle: 'Biometric unlock (coming soon)',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('App lock requires local_auth setup.')),
              );
            },
          ),
          _SettingsTile(
            icon: Icons.terminal,
            title: 'Terminal',
            subtitle: 'Keep-alive, tmux defaults',
            onTap: () => context.push('/settings/terminal'),
          ),
          _SettingsTile(
            icon: Icons.info_outline,
            title: 'About Obsidian SSH',
            subtitle: 'llmshell.AI v1.0.0',
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(icon, color: ObsidianColors.primary),
        title: Text(title, style: AppTypography.inter(size: 16, weight: FontWeight.w500)),
        subtitle: Text(subtitle, style: AppTypography.inter(size: 14, color: ObsidianColors.onSurfaceVariant)),
        trailing: const Icon(Icons.chevron_right, color: ObsidianColors.outline),
        onTap: onTap,
      ),
    );
  }
}
