import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/obsidian_colors.dart';
import '../../models/host.dart';
import '../../providers/hosts_provider.dart';
import '../../services/ssh_key_repository.dart';

class AddHostScreen extends ConsumerStatefulWidget {
  const AddHostScreen({super.key, this.hostId});

  final String? hostId;

  @override
  ConsumerState<AddHostScreen> createState() => _AddHostScreenState();
}

class _AddHostScreenState extends ConsumerState<AddHostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _userCtrl = TextEditingController(text: 'root');
  final _portCtrl = TextEditingController(text: '22');
  final _passwordCtrl = TextEditingController();
  final _tmuxNameCtrl = TextEditingController();
  final _startupSnippetCtrl = TextEditingController();

  HostAuthMethod _authMethod = HostAuthMethod.password;
  HostGroup _group = HostGroup.production;
  HostTmuxMode _tmuxMode = HostTmuxMode.inherit;
  String? _selectedKeyId;
  bool _loading = false;
  bool _initialized = false;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _hostCtrl.dispose();
    _userCtrl.dispose();
    _portCtrl.dispose();
    _passwordCtrl.dispose();
    _tmuxNameCtrl.dispose();
    _startupSnippetCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEdit() async {
    if (widget.hostId == null || _initialized) return;
    final hosts = await ref.read(hostsProvider.future);
    Host? host;
    for (final h in hosts) {
      if (h.id == widget.hostId) {
        host = h;
        break;
      }
    }
    if (host == null) return;
    _labelCtrl.text = host.label;
    _hostCtrl.text = host.hostname;
    _userCtrl.text = host.username;
    _portCtrl.text = '${host.port}';
    _group = host.group;
    _authMethod = host.authMethod;
    _selectedKeyId = host.sshKeyId;
    _tmuxMode = host.tmuxMode;
    _tmuxNameCtrl.text = host.tmuxSessionName ?? '';
    _startupSnippetCtrl.text = host.startupSnippet ?? '';
    _initialized = true;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hostId != null && !_initialized) {
      _loadEdit();
    }

    final keysAsync = ref.watch(_sshKeysProvider);

    return Scaffold(
      appBar: AppBar(
        leading: TextButton.icon(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.close, size: 20, color: ObsidianColors.primary),
          label: Text('Cancel', style: AppTypography.inter(size: 14, color: ObsidianColors.primary)),
        ),
        leadingWidth: 100,
        title: Text(widget.hostId == null ? 'Add Host' : 'Edit Host'),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.marginMobile),
          children: [
            _FormSection(
              icon: Icons.bookmark_outline,
              title: 'IDENTITY',
              children: [
                TextFormField(
                  controller: _labelCtrl,
                  decoration: const InputDecoration(labelText: 'Label / Alias *', hintText: 'e.g., Web Server Alpha'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<HostGroup>(
                  value: _group,
                  decoration: const InputDecoration(labelText: 'Group / Category'),
                  items: HostGroup.values
                      .map((g) => DropdownMenuItem(value: g, child: Text(_groupName(g))))
                      .toList(),
                  onChanged: (v) => setState(() => _group = v ?? HostGroup.production),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _FormSection(
              icon: Icons.dns_outlined,
              title: 'CONNECTION',
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _hostCtrl,
                        style: AppTypography.mono(size: 14),
                        decoration: const InputDecoration(labelText: 'Hostname or IP *', hintText: '192.168.1.1'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    SizedBox(
                      width: 88,
                      child: TextFormField(
                        controller: _portCtrl,
                        style: AppTypography.mono(size: 14),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Port'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _FormSection(
              icon: Icons.terminal,
              title: 'SESSION',
              children: [
                DropdownButtonFormField<HostTmuxMode>(
                  value: _tmuxMode,
                  decoration: const InputDecoration(labelText: 'tmux mode'),
                  items: const [
                    DropdownMenuItem(value: HostTmuxMode.inherit, child: Text('Inherit app default')),
                    DropdownMenuItem(value: HostTmuxMode.off, child: Text('Off')),
                    DropdownMenuItem(value: HostTmuxMode.attachExisting, child: Text('Attach or create')),
                    DropdownMenuItem(value: HostTmuxMode.createNew, child: Text('Create new')),
                  ],
                  onChanged: (v) => setState(() => _tmuxMode = v ?? HostTmuxMode.inherit),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _tmuxNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Default session name',
                    hintText: 'api-build',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _startupSnippetCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Startup snippet (optional)',
                    hintText: 'npm run dev',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _FormSection(
              icon: Icons.key_outlined,
              title: 'AUTHENTICATION',
              children: [
                SegmentedButton<HostAuthMethod>(
                  segments: const [
                    ButtonSegment(value: HostAuthMethod.password, label: Text('Password'), icon: Icon(Icons.password, size: 16)),
                    ButtonSegment(value: HostAuthMethod.keyPair, label: Text('Key Pair'), icon: Icon(Icons.vpn_key_outlined, size: 16)),
                  ],
                  selected: {_authMethod},
                  onSelectionChanged: (s) => setState(() => _authMethod = s.first),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _userCtrl,
                  style: AppTypography.mono(size: 14),
                  decoration: const InputDecoration(labelText: 'Username *', hintText: 'root', prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                if (_authMethod == HostAuthMethod.password)
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    style: AppTypography.mono(size: 14),
                    decoration: InputDecoration(
                      labelText: widget.hostId == null ? 'Password' : 'Password (leave blank to keep)',
                    ),
                  )
                else
                  keysAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('$e'),
                    data: (keys) => DropdownButtonFormField<String>(
                      value: _selectedKeyId,
                      decoration: const InputDecoration(labelText: 'Private Key'),
                      items: [
                        for (final k in keys)
                          DropdownMenuItem(value: k.id, child: Text(k.name)),
                      ],
                      onChanged: (v) => setState(() => _selectedKeyId = v),
                    ),
                  ),
                if (_authMethod == HostAuthMethod.keyPair) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      const Icon(Icons.info_outline, size: 14, color: ObsidianColors.outline),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Keys can be managed in Settings.',
                          style: AppTypography.mono(size: 12, color: ObsidianColors.outline),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.marginMobile),
          child: FilledButton.icon(
            onPressed: _loading ? null : _save,
            icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
            label: Text(_loading ? 'Saving…' : 'Save Host'),
            style: FilledButton.styleFrom(
              backgroundColor: ObsidianColors.primary,
              foregroundColor: ObsidianColors.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      final port = int.tryParse(_portCtrl.text.trim()) ?? 22;
      await ref.read(hostsProvider.notifier).save(
            id: widget.hostId,
            label: _labelCtrl.text.trim(),
            hostname: _hostCtrl.text.trim(),
            username: _userCtrl.text.trim(),
            group: _group,
            port: port,
            authMethod: _authMethod,
            sshKeyId: _authMethod == HostAuthMethod.keyPair ? _selectedKeyId : null,
            password: _authMethod == HostAuthMethod.password ? _passwordCtrl.text : null,
            tmuxMode: _tmuxMode,
            tmuxSessionName: _tmuxNameCtrl.text.trim().isEmpty ? null : _tmuxNameCtrl.text.trim(),
            startupSnippet: _startupSnippetCtrl.text.trim().isEmpty ? null : _startupSnippetCtrl.text.trim(),
          );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _groupName(HostGroup g) => switch (g) {
        HostGroup.production => 'Production',
        HostGroup.staging => 'Staging',
        HostGroup.development => 'Development',
        HostGroup.personal => 'Personal',
      };
}

final _sshKeysProvider = FutureProvider((ref) => ref.read(sshKeyRepositoryProvider).listKeys());

class _FormSection extends StatelessWidget {
  const _FormSection({required this.icon, required this.title, required this.children});

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            color: ObsidianColors.surfaceContainerLow,
            child: Row(
              children: [
                Icon(icon, size: 18, color: ObsidianColors.outline),
                const SizedBox(width: AppSpacing.sm),
                Text(title, style: AppTypography.mono(size: 14, weight: FontWeight.w500, color: ObsidianColors.onSurfaceVariant).copyWith(letterSpacing: 1)),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(AppSpacing.md), child: Column(children: children)),
        ],
      ),
    );
  }
}
