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

/// Width (logical px) used for the centered desktop frame in browser tabs.
const double _kDesktopFrameWidth = 1024;

/// Generic desktop Chrome user-agent sent when a browser tab is in desktop view.
const String _kDesktopUserAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/124.0.0.0 Safari/537.36';

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
  late bool _desktopView;

  WorkspaceManager get _manager => ref.read(workspaceManagerProvider);

  @override
  void initState() {
    super.initState();
    _remotePort = widget.tab.remotePort;
    _desktopView = widget.tab.desktopView;
    // Defer past the first frame so we do not mount a platform view during
    // the same frame as a route pop (e.g. bottom sheet → browser tab).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _init();
    });
  }

  @override
  void didUpdateWidget(covariant BrowserTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab.id == widget.tab.id) {
      // The persisted desktopView may have been changed by another caller
      // (e.g. model update) — keep the local flag in sync without rebuilding
      // the WebView, which would lose navigation history.
      if (oldWidget.tab.desktopView != widget.tab.desktopView) {
        _desktopView = widget.tab.desktopView;
      }
      return;
    }
    // Tab was replaced (e.g. restored from disk) — re-init against the new
    // remote port and URL. The next frame call avoids mounting a platform
    // view in the same frame as a route pop.
    _urlController.text = widget.tab.url ?? 'localhost:${widget.tab.remotePort}/';
    _displayUrl = _urlController.text;
    _remotePort = widget.tab.remotePort;
    _desktopView = widget.tab.desktopView;
    _initGeneration++;
    _controller = null;
    _showWebView = false;
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

    if (_desktopView) {
      // Some sites serve different markup based on UA — switching to a
      // desktop UA here is what makes a "Request Desktop Site" toggle
      // work. setUserAgent must be set before the first loadRequest.
      controller.setUserAgent(_kDesktopUserAgent);
    }

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
      final initial = widget.tab.url ?? 'localhost:$_remotePort/';
      final display = _normalizeDisplayUrl(initial);
      if (!mounted || generation != _initGeneration) return;
      _displayUrl = display;
      _urlController.text = display;

      if (_isLocalDisplayUrl(display)) {
        // Sync _remotePort with whatever the URL says (in case the user
        // edited the port in the URL bar or restored from an older tab
        // where remotePort drifted from the URL).
        final portFromUrl = _portFromLocalDisplay(display);
        if (portFromUrl != null && portFromUrl != _remotePort) {
          _remotePort = portFromUrl;
        }
        final port = await _manager.ensureBrowserForward(
          widget.workspaceId,
          widget.tab.id,
          _remotePort,
        );
        if (!mounted || generation != _initGeneration) return;
        _localPort = port;
      } else {
        // External URL — no SSH forward needed.
        _localPort = 0;
      }

      final controller = _createController();
      _controller = controller;
      await controller.loadRequest(_toActualUri(display));
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

  /// True for `localhost[:port]` / `127.0.0.1[:port]` display URLs (with or
  /// without a scheme). External URLs always return false.
  bool _isLocalDisplayUrl(String display) {
    final uri = Uri.tryParse(display.contains('://') ? display : 'http://$display');
    if (uri == null) return false;
    return uri.host == 'localhost' || uri.host == '127.0.0.1';
  }

  /// Extract the remote port from a local display URL like
  /// `localhost:8080/admin`. Returns null for non-local URLs or missing ports.
  int? _portFromLocalDisplay(String display) {
    final match = RegExp(r'^(?:localhost|127\.0\.0\.1):(\d+)').firstMatch(display);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
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

    // Pure port number → local forward on that port.
    final portOnly = int.tryParse(raw);
    if (portOnly != null) {
      if (portOnly < 1 || portOnly > 65535) return 'localhost:$_remotePort/';
      return 'localhost:$portOnly/';
    }

    // Add scheme if missing — localhost/127.0.0.1 defaults to http,
    // external hosts default to https.
    if (!raw.contains('://')) {
      final lower = raw.toLowerCase();
      if (lower.startsWith('localhost') || lower.startsWith('127.0.0.1')) {
        raw = 'http://$raw';
      } else {
        raw = 'https://$raw';
      }
    }

    return _toDisplayUrl(raw);
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
    if (raw.isEmpty) {
      // Fall back to the SSH-forwarded port if one is set up, otherwise
      // return about:blank so the WebView doesn't try to load 0.0.0.0:0.
      if (_remotePort > 0 && _localPort > 0) {
        raw = 'localhost:$_remotePort/';
      } else {
        return Uri.parse('about:blank');
      }
    }
    if (!raw.contains('://')) {
      final lower = raw.toLowerCase();
      raw = (lower.startsWith('localhost') || lower.startsWith('127.0.0.1'))
          ? 'http://$raw'
          : 'https://$raw';
    }

    final uri = Uri.parse(raw);
    final isLocal = uri.host == 'localhost' || uri.host == '127.0.0.1';
    if (isLocal && _localPort > 0) {
      // Route through the SSH-forwarded port.
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

    // If the user typed a localhost URL while we were on an external one,
    // we need to set up the SSH forward on demand before loading.
    if (_isLocalDisplayUrl(display) && _localPort == 0) {
      final portFromUrl = _portFromLocalDisplay(display);
      if (portFromUrl != null && portFromUrl != _remotePort) {
        _remotePort = portFromUrl;
      }
      final port = await _manager.ensureBrowserForward(
        widget.workspaceId,
        widget.tab.id,
        _remotePort,
      );
      if (!mounted) return;
      _localPort = port;
    }

    setState(() {
      _displayUrl = display;
      _urlController.text = display;
      _error = null;
      _pageLoading = true;
    });
    _manager.updateAuxTab(
      widget.workspaceId,
      widget.tab.id,
      (tab) => tab.copyWith(remotePort: _remotePort, url: display),
    );
    await _controller?.loadRequest(_toActualUri(display));
  }

  Widget _buildWebView(WebViewController controller) {
    final Widget webView;
    if (!kIsWeb && Platform.isAndroid) {
      webView = WebViewWidget.fromPlatformCreationParams(
        params: AndroidWebViewWidgetCreationParams(
          controller: controller.platform,
          // Hybrid composition avoids Android WebView freezes/crashes on some devices.
          displayWithHybridComposition: true,
        ),
      );
    } else {
      webView = WebViewWidget(controller: controller);
    }

    if (!_desktopView) return webView;

    // Desktop frame: a darker surface around a fixed-width WebView so the
    // preview reads as "laptop on a desk". On screens narrower than the
    // frame, the WebView still renders at the desktop width — the user can
    // scroll it horizontally inside the frame to see clipped edges.
    return Container(
      color: ObsidianColors.surfaceContainerLowest,
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: _kDesktopFrameWidth,
        child: ColoredBox(
          color: ObsidianColors.background,
          child: webView,
        ),
      ),
    );
  }

  /// Toggle between mobile and desktop view. Updates the persisted tab, the
  /// controller's user-agent, and triggers a reload so the server sees the
  /// new UA on the next request.
  Future<void> _toggleDesktopView() async {
    final next = !_desktopView;
    setState(() => _desktopView = next);
    _manager.updateAuxTab(
      widget.workspaceId,
      widget.tab.id,
      (tab) => tab.copyWith(desktopView: next),
    );
    final controller = _controller;
    if (controller != null) {
      await controller.setUserAgent(next ? _kDesktopUserAgent : null);
      await controller.reload();
    }
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

    final portChanged = result.isLocalForward && result.remotePort != _remotePort;
    _remotePort = result.remotePort;
    _manager.updateAuxTab(
      widget.workspaceId,
      widget.tab.id,
      (tab) => tab.copyWith(remotePort: result.remotePort, url: result.displayUrl),
    );
    if (result.isLocalForward && portChanged) {
      await _manager.reconfigureBrowserForward(widget.workspaceId, widget.tab.id, result.remotePort);
    }

    if (!mounted) return;
    if (result.isLocalForward && portChanged) {
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
                        icon: Icon(
                          _desktopView ? Icons.desktop_mac : Icons.smartphone,
                          size: 20,
                          color: _desktopView ? ObsidianColors.primary : null,
                        ),
                        tooltip: _desktopView ? 'Switch to mobile view' : 'Switch to desktop view',
                        onPressed: _toggleDesktopView,
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

/// Parsed URL for a browser tab.
///
/// Two flavors:
///   - **Local forward** (`isLocalForward == true`): the URL is served by a
///     process on the remote host's localhost, surfaced in the WebView via
///     an SSH port-forward. [remotePort] is the port on the remote host.
///   - **External** (`isLocalForward == false`): any http/https URL that
///     doesn't target the remote host. [remotePort] is 0.
class BrowserUrlSetup {
  const BrowserUrlSetup({
    required this.remotePort,
    required this.displayUrl,
    this.isLocalForward = true,
  });

  final int remotePort;
  final String displayUrl;
  final bool isLocalForward;
}

/// Parse user input into a [BrowserUrlSetup]. Accepts:
///
///   - a bare port (`3000`) → local forward on that port
///   - `localhost[:port][/path]` or `127.0.0.1[:port][/path]` → local forward
///   - any `http://` or `https://` URL → external (no SSH forward)
///   - a bare host/path (`google.com`, `github.com/foo/bar`) → external
///     (assumes `https://` since the user clearly means a public site)
BrowserUrlSetup? parseBrowserUrl(String input) {
  var raw = input.trim();
  if (raw.isEmpty) return null;

  // Pure port number → local forward on that port.
  final portOnly = int.tryParse(raw);
  if (portOnly != null) {
    if (portOnly < 1 || portOnly > 65535) return null;
    return BrowserUrlSetup(
      remotePort: portOnly,
      displayUrl: 'localhost:$portOnly/',
      isLocalForward: true,
    );
  }

  // Ensure we have a scheme so Uri.parse can extract the host reliably.
  if (!raw.contains('://')) {
    final lower = raw.toLowerCase();
    if (lower.startsWith('localhost') || lower.startsWith('127.0.0.1')) {
      raw = 'http://$raw';
    } else {
      // External host — default to https. Users can override by typing
      // `http://` explicitly when targeting a site without TLS.
      raw = 'https://$raw';
    }
  }

  final uri = Uri.tryParse(raw);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;

  // Local forward: localhost / 127.0.0.1 with or without an explicit port.
  if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
    final port = uri.hasPort ? uri.port : 80;
    if (port < 1 || port > 65535) return null;
    final path = uri.path.isEmpty ? '/' : uri.path;
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return BrowserUrlSetup(
      remotePort: port,
      displayUrl: 'localhost:$port$path$query',
      isLocalForward: true,
    );
  }

  // External URL — preserve the user-facing form (host[:port][/path][?query][#fragment])
  // without any scheme prefix in the address bar.
  final portPart = uri.hasPort ? ':${uri.port}' : '';
  final queryPart = uri.hasQuery ? '?${uri.query}' : '';
  final fragmentPart = uri.hasFragment ? '#${uri.fragment}' : '';
  return BrowserUrlSetup(
    remotePort: 0,
    displayUrl: '${uri.host}$portPart${uri.path}$queryPart$fragmentPart',
    isLocalForward: false,
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
      setState(() => _error = 'Enter localhost:port/path or a full URL (e.g. localhost:3000/ or https://example.com)');
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
              hintText: 'localhost:3000/ or https://example.com',
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
