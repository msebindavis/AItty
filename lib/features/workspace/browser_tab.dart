import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/constants/spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/obsidian_colors.dart';
import '../../models/workspace_tab.dart';
import '../../services/workspace_manager.dart';
import '../../utils/route_transition.dart';

/// In-app browser for previewing services on the remote host via SSH port forwarding.
class BrowserTab extends ConsumerStatefulWidget {
  const BrowserTab({
    super.key,
    required this.workspaceId,
    required this.tab,
  });

  final String workspaceId;
  final WorkspaceTab tab;

  @override
  ConsumerState<BrowserTab> createState() => _BrowserTabState();
}

class _BrowserTabState extends ConsumerState<BrowserTab> {
  WebViewController? _controller;
  final _urlController = TextEditingController();
  final _urlFocus = FocusNode();

  late int _remotePort;
  int _localPort = 0;
  String _displayUrl = '';
  bool _initializing = true;
  bool _showWebView = false;
  bool _pageLoading = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String? _error;
  int _initGeneration = 0;

  WorkspaceManager get _manager => ref.read(workspaceManagerProvider);

  @override
  void initState() {
    super.initState();
    _remotePort = widget.tab.remotePort;
    // Defer past the first frame so we do not mount a platform view during
    // the same frame as a route pop (e.g. bottom sheet → browser tab).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _init();
    });
  }

  @override
  void dispose() {
    _controller = null;
    _urlController.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  WebViewController _createController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(ObsidianColors.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() => _pageLoading = true);
          },
          onPageFinished: (_) => _syncFromWebView(),
          onUrlChange: (change) {
            if (change.url == null) return;
            _applyActualUrl(change.url!);
          },
          onWebResourceError: (err) {
            if (!mounted) return;
            setState(() => _error = err.description);
          },
        ),
      );

    if (!kIsWeb && Platform.isAndroid && controller.platform is AndroidWebViewController) {
      final android = controller.platform as AndroidWebViewController;
      android.setMediaPlaybackRequiresUserGesture(false);
    }

    return controller;
  }

  Future<void> _init() async {
    final generation = ++_initGeneration;
    setState(() {
      _initializing = true;
      _showWebView = false;
      _error = null;
    });
    try {
      final port = await _manager.ensureBrowserForward(
        widget.workspaceId,
        widget.tab.id,
        _remotePort,
      );
      if (!mounted || generation != _initGeneration) return;
      _localPort = port;
      final initial = widget.tab.url ?? 'localhost:$_remotePort/';
      _displayUrl = _normalizeDisplayUrl(initial);
      _urlController.text = _displayUrl;

      final controller = _createController();
      _controller = controller;
      await controller.loadRequest(_toActualUri(_displayUrl));
      if (!mounted || generation != _initGeneration) return;
      setState(() => _initializing = false);
      await waitForRouteTransition();
      if (!mounted || generation != _initGeneration) return;
      setState(() => _showWebView = true);
    } catch (e) {
      if (!mounted || generation != _initGeneration) return;
      setState(() {
        _error = e.toString();
        _initializing = false;
        _showWebView = false;
      });
    }
  }

  Future<void> _syncFromWebView() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final actual = await controller.currentUrl();
    if (actual != null) _applyActualUrl(actual);
    final back = await controller.canGoBack();
    final forward = await controller.canGoForward();
    if (!mounted) return;
    setState(() {
      _canGoBack = back;
      _canGoForward = forward;
      _pageLoading = false;
    });
  }

  void _applyActualUrl(String actualUrl) {
    final display = _toDisplayUrl(actualUrl);
    if (display == _displayUrl) return;
    _displayUrl = display;
    _urlController.text = display;
    // Persist URL without rebuilding the whole workspace (avoids WebView churn).
    _manager.updateAuxTab(
      widget.workspaceId,
      widget.tab.id,
      (tab) => tab.copyWith(url: display),
      notify: false,
    );
    if (mounted) setState(() {});
  }

  String _normalizeDisplayUrl(String input) {
    var raw = input.trim();
    if (raw.isEmpty) return 'localhost:$_remotePort/';
    if (!raw.contains('://') && !raw.startsWith('localhost') && !raw.startsWith('127.0.0.1')) {
      raw = 'localhost:$_remotePort/${raw.startsWith('/') ? raw.substring(1) : raw}';
    }
    return _toDisplayUrl(raw.contains('://') ? raw : 'http://$raw');
  }

  String _toDisplayUrl(String actualOrDisplay) {
    final uri = Uri.tryParse(actualOrDisplay.contains('://') ? actualOrDisplay : 'http://$actualOrDisplay');
    if (uri == null) return actualOrDisplay;
    if ((uri.host == '127.0.0.1' || uri.host == 'localhost') &&
        (uri.port == _localPort || uri.port == _remotePort || uri.port == 0)) {
      final path = uri.path.isEmpty ? '/' : uri.path;
      final query = uri.hasQuery ? '?${uri.query}' : '';
      return 'localhost:$_remotePort$path$query';
    }
    return actualOrDisplay.replaceFirst(RegExp(r'^https?://'), '');
  }

  Uri _toActualUri(String input) {
    var raw = input.trim();
    if (raw.isEmpty) raw = 'localhost:$_remotePort/';
    if (!raw.contains('://')) raw = 'http://$raw';

    final uri = Uri.parse(raw);
    if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
      return Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: _localPort,
        path: uri.path.isEmpty ? '/' : uri.path,
        query: uri.hasQuery ? uri.query : null,
        fragment: uri.hasFragment ? uri.fragment : null,
      );
    }
    return uri;
  }

  Future<void> _navigateTo(String input) async {
    _urlFocus.unfocus();
    final display = _normalizeDisplayUrl(input);
    setState(() {
      _displayUrl = display;
      _urlController.text = display;
      _error = null;
      _pageLoading = true;
    });
    _manager.updateAuxTab(
      widget.workspaceId,
      widget.tab.id,
      (tab) => tab.copyWith(url: display),
    );
    await _controller?.loadRequest(_toActualUri(display));
  }

  Widget _buildWebView(WebViewController controller) {
    if (!kIsWeb && Platform.isAndroid) {
      return WebViewWidget.fromPlatformCreationParams(
        params: AndroidWebViewWidgetCreationParams(
          controller: controller.platform,
          // Hybrid composition avoids Android WebView freezes/crashes on some devices.
          displayWithHybridComposition: true,
        ),
      );
    }
    return WebViewWidget(controller: controller);
  }

  Future<void> _reload() async {
    setState(() {
      _error = null;
      _pageLoading = true;
    });
    await _controller?.reload();
  }

  Future<void> _editUrl() async {
    final result = await showBrowserUrlDialog(
      context,
      title: 'Browser settings',
      confirmLabel: 'Apply',
      initialUrl: _displayUrl,
    );
    if (result == null || !mounted) return;

    final portChanged = result.remotePort != _remotePort;
    _remotePort = result.remotePort;
    _manager.updateAuxTab(
      widget.workspaceId,
      widget.tab.id,
      (tab) => tab.copyWith(remotePort: result.remotePort, url: result.displayUrl),
    );
    if (portChanged) {
      await _manager.reconfigureBrowserForward(widget.workspaceId, widget.tab.id, result.remotePort);
    }

    if (!mounted) return;
    if (portChanged) {
      _controller = null;
      _showWebView = false;
      await _init();
    } else {
      await _navigateTo(result.displayUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const ColoredBox(
        color: ObsidianColors.background,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _controller == null) {
      return ColoredBox(
        color: ObsidianColors.background,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, style: AppTypography.mono(size: 12, color: ObsidianColors.error), textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.md),
                FilledButton(onPressed: _init, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: ObsidianColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: ObsidianColors.surfaceContainerLow,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, size: 20),
                        tooltip: 'Back',
                        onPressed: _canGoBack ? () => _controller?.goBack() : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward, size: 20),
                        tooltip: 'Forward',
                        onPressed: _canGoForward ? () => _controller?.goForward() : null,
                      ),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: ObsidianColors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: AppSpacing.md),
                              Icon(
                                Icons.lock_outline,
                                size: 16,
                                color: _displayUrl.startsWith('https') ? ObsidianColors.secondary : ObsidianColors.outline,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: TextField(
                                  controller: _urlController,
                                  focusNode: _urlFocus,
                                  style: AppTypography.mono(size: 12),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                                  ),
                                  onSubmitted: _navigateTo,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: 'Reload',
                        onPressed: _reload,
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined, size: 20),
                        tooltip: 'URL settings',
                        onPressed: _editUrl,
                      ),
                    ],
                  ),
                ),
                if (_pageLoading) const LinearProgressIndicator(minHeight: 2),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_error != null)
            Material(
              color: ObsidianColors.error.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: ObsidianColors.error),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(_error!, style: AppTypography.mono(size: 11, color: ObsidianColors.error)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _error = null),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _showWebView && _controller != null
                ? _buildWebView(_controller!)
                : const ColoredBox(color: ObsidianColors.background),
          ),
        ],
      ),
    );
  }
}

/// Parsed URL for SSH port-forwarding to a service on remote localhost.
class BrowserUrlSetup {
  const BrowserUrlSetup({
    required this.remotePort,
    required this.displayUrl,
  });

  final int remotePort;
  final String displayUrl;
}

/// Parse user input like `localhost:3000/docs` or `3000` into port + display URL.
BrowserUrlSetup? parseBrowserUrl(String input) {
  var raw = input.trim();
  if (raw.isEmpty) return null;

  final portOnly = int.tryParse(raw);
  if (portOnly != null) {
    if (portOnly < 1 || portOnly > 65535) return null;
    return BrowserUrlSetup(remotePort: portOnly, displayUrl: 'localhost:$portOnly/');
  }

  if (!raw.contains('://')) {
    if (!raw.startsWith('localhost') && !raw.startsWith('127.0.0.1')) {
      raw = 'localhost:$raw';
    }
    raw = 'http://$raw';
  }

  final uri = Uri.tryParse(raw);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.host != 'localhost' && uri.host != '127.0.0.1') return null;

  final port = uri.hasPort ? uri.port : 80;
  if (port < 1 || port > 65535) return null;

  final path = uri.path.isEmpty ? '/' : uri.path;
  final query = uri.hasQuery ? '?${uri.query}' : '';
  return BrowserUrlSetup(
    remotePort: port,
    displayUrl: 'localhost:$port$path$query',
  );
}

/// Prompt for the remote service URL when creating or reconfiguring a browser tab.
Future<BrowserUrlSetup?> showBrowserUrlDialog(
  BuildContext context, {
  String title = 'New browser tab',
  String confirmLabel = 'Open',
  String? subtitle,
  String initialUrl = 'localhost:3000/',
}) {
  return showDialog<BrowserUrlSetup>(
    context: context,
    builder: (ctx) => _BrowserUrlDialog(
      title: title,
      confirmLabel: confirmLabel,
      subtitle: subtitle,
      initialUrl: initialUrl,
    ),
  );
}

class _BrowserUrlDialog extends StatefulWidget {
  const _BrowserUrlDialog({
    required this.title,
    required this.confirmLabel,
    this.subtitle,
    this.initialUrl = 'localhost:3000/',
  });

  final String title;
  final String confirmLabel;
  final String? subtitle;
  final String initialUrl;

  @override
  State<_BrowserUrlDialog> createState() => _BrowserUrlDialogState();
}

class _BrowserUrlDialogState extends State<_BrowserUrlDialog> {
  late final TextEditingController _urlCtrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = parseBrowserUrl(_urlCtrl.text);
    if (parsed == null) {
      setState(() => _error = 'Enter localhost:port/path (e.g. localhost:3000/)');
      return;
    }
    Navigator.pop(context, parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.subtitle != null) ...[
            Text(
              widget.subtitle!,
              style: AppTypography.inter(size: 13, color: ObsidianColors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          TextField(
            controller: _urlCtrl,
            decoration: InputDecoration(
              labelText: 'URL',
              hintText: 'localhost:3000/',
              errorText: _error,
            ),
            style: AppTypography.mono(size: 13),
            autofocus: true,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
