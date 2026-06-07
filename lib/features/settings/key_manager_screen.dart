import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/obsidian_colors.dart';
import '../../services/ssh_key_repository.dart';

class KeyManagerScreen extends ConsumerStatefulWidget {
  const KeyManagerScreen({super.key});

  @override
  ConsumerState<KeyManagerScreen> createState() => _KeyManagerScreenState();
}

class _KeyManagerScreenState extends ConsumerState<KeyManagerScreen> {
  @override
  Widget build(BuildContext context) {
    final keysAsync = ref.watch(_keysProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Key Manager')),
      floatingActionButton: FloatingActionButton(
        onPressed: _importKey,
        child: const Icon(Icons.add),
      ),
      body: keysAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (keys) {
          if (keys.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.marginMobile),
                child: Text(
                  'No SSH keys stored.\nImport a .pem or private key file.',
                  textAlign: TextAlign.center,
                  style: AppTypography.inter(size: 16, color: ObsidianColors.onSurfaceVariant),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.marginMobile),
            itemCount: keys.length,
            itemBuilder: (context, i) {
              final key = keys[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.vpn_key, color: ObsidianColors.primary),
                  title: Text(key.name, style: AppTypography.inter(size: 16, weight: FontWeight.w500)),
                  subtitle: key.comment != null ? Text(key.comment!) : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: ObsidianColors.error),
                    onPressed: () async {
                      await ref.read(sshKeyRepositoryProvider).deleteKey(key.id);
                      ref.invalidate(_keysProvider);
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _importKey() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    String? pem;
    if (file.bytes != null) {
      pem = String.fromCharCodes(file.bytes!);
    } else if (file.path != null) {
      pem = await File(file.path!).readAsString();
    }
    if (pem == null || pem.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not read key file')));
      return;
    }

    await ref.read(sshKeyRepositoryProvider).saveKey(name: file.name, privateKeyPem: pem);
    ref.invalidate(_keysProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported ${file.name}')));
    }
  }
}

final _keysProvider = FutureProvider((ref) => ref.read(sshKeyRepositoryProvider).listKeys());
