import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/obsidian_colors.dart';
import '../../models/host.dart';
import '../../providers/hosts_provider.dart';
import '../../widgets/section_header.dart';
import '../../widgets/status_chip.dart';

class SelectHostScreen extends ConsumerStatefulWidget {
  const SelectHostScreen({super.key});

  @override
  ConsumerState<SelectHostScreen> createState() => _SelectHostScreenState();
}

class _SelectHostScreenState extends ConsumerState<SelectHostScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final hostsAsync = ref.watch(hostsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal Hosts'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: () => context.push('/hosts/add'))],
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

          final recent = filtered.where((h) => h.isRecent).toList();
          final grouped = <HostGroup, List<Host>>{};
          for (final host in filtered) {
            grouped.putIfAbsent(host.group, () => []).add(host);
          }

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
            children: [
              TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, color: ObsidianColors.outline),
                  hintText: 'Search hosts or groups...',
                ),
              ),
              if (recent.isNotEmpty) ...[
                const SectionHeader('RECENT'),
                ...recent.map(
                  (h) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _RecentHostCard(host: h, onTap: () => context.push('/sessions/new/path?host=${h.id}')),
                  ),
                ),
              ],
              const SectionHeader('ALL HOSTS'),
              for (final group in HostGroup.values)
                if (grouped[group]?.isNotEmpty ?? false) ...[
                  SectionHeader(grouped[group]!.first.groupLabel),
                  ...grouped[group]!.map(
                    (h) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(h.label, style: AppTypography.inter(size: 16, weight: FontWeight.w500)),
                      subtitle: Text(h.hostname, style: AppTypography.mono(size: 12)),
                      trailing: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: h.reachability == HostReachability.online ? ObsidianColors.secondary : ObsidianColors.outline,
                          shape: BoxShape.circle,
                        ),
                      ),
                      onTap: () => context.push('/sessions/new/path?host=${h.id}'),
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
}

class _RecentHostCard extends StatelessWidget {
  const _RecentHostCard({required this.host, required this.onTap});

  final Host host;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.dns_outlined, color: ObsidianColors.primary),
                  const Spacer(),
                  StatusChip.host(reachability: host.reachability),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(host.label, style: AppTypography.inter(size: 18, weight: FontWeight.w600)),
              Text(host.connectionString, style: AppTypography.mono(size: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
