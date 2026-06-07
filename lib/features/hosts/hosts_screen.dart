import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/obsidian_colors.dart';
import '../../models/host.dart';
import '../../providers/hosts_provider.dart';
import '../../widgets/host_list_tile.dart';
import '../../widgets/section_header.dart';

class HostsScreen extends ConsumerStatefulWidget {
  const HostsScreen({super.key});

  @override
  ConsumerState<HostsScreen> createState() => _HostsScreenState();
}

class _HostsScreenState extends ConsumerState<HostsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final hostsAsync = ref.watch(hostsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.terminal, size: 22),
            const SizedBox(width: AppSpacing.sm),
            Text('Terminal Hosts', style: AppTypography.inter(size: 20, weight: FontWeight.w600, color: ObsidianColors.primary)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => context.push('/hosts/add')),
        ],
      ),
      body: hostsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (hosts) {
          final filtered = hosts.where((h) {
            if (_query.isEmpty) return true;
            final q = _query.toLowerCase();
            return h.label.toLowerCase().contains(q) || h.hostname.toLowerCase().contains(q);
          }).toList();

          final grouped = <HostGroup, List<Host>>{};
          for (final host in filtered) {
            grouped.putIfAbsent(host.group, () => []).add(host);
          }

          if (filtered.isEmpty) {
            return Column(
              children: [
                _searchField(),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('No hosts yet', style: AppTypography.inter(size: 18, weight: FontWeight.w500)),
                        const SizedBox(height: AppSpacing.md),
                        FilledButton.icon(
                          onPressed: () => context.push('/hosts/add'),
                          icon: const Icon(Icons.add),
                          label: const Text('Add Host'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
            children: [
              _searchField(),
              for (final group in HostGroup.values)
                if (grouped[group]?.isNotEmpty ?? false) ...[
                  SectionHeader(grouped[group]!.first.groupLabel),
                  ...grouped[group]!.map(
                    (host) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: HostListTile(
                        host: host,
                        onTap: () => context.push('/sessions/new/path?host=${host.id}'),
                        onMenu: () => _showHostMenu(host),
                      ),
                    ),
                  ),
                ],
              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.sm),
      child: TextField(
        onChanged: (v) => setState(() => _query = v),
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search, color: ObsidianColors.outline),
          hintText: 'Filter hosts by name or IP...',
        ),
      ),
    );
  }

  void _showHostMenu(Host host) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Connect'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/sessions/new/path?host=${host.id}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/hosts/add?hostId=${host.id}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: ObsidianColors.error),
              title: const Text('Delete'),
              onTap: () async {
                Navigator.pop(ctx);
                await ref.read(hostsProvider.notifier).delete(host.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}
