import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../models/host.dart';
import '../models/remote_file_entry.dart';
import 'host_repository.dart';
import 'known_hosts_store.dart';
import 'local_port_forward.dart';
import 'ssh_key_repository.dart';

class ShellChannel {
  ShellChannel({
    required this.id,
    required this.session,
  });

  final String id;
  final SSHSession session;
  StreamSubscription<Uint8List>? stdoutSub;
  StreamSubscription<Uint8List>? stderrSub;
}

class SshConnection {
  SshConnection(this._client) {
    _client.done.whenComplete(() {
      _disconnected = true;
      _shells.clear();
      onDisconnected?.call();
    });
  }

  final SSHClient _client;
  final Map<String, ShellChannel> _shells = {};
  SftpClient? _sftp;
  final _forwards = <LocalPortForward>[];
  bool _disconnected = false;

  VoidCallback? onDisconnected;

  SSHClient get client => _client;

  bool get isConnected => !_disconnected && !_client.isClosed;

  Set<String> get openChannelIds => _shells.keys.toSet();

  static Future<SshConnection> connect({
    required Host host,
    required HostRepository hosts,
    required SshKeyRepository keys,
    required KnownHostsStore knownHosts,
    Duration? keepAliveInterval,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final socket = await _connectTcpSocket(
      host.hostname,
      host.port,
      timeout: timeout,
    );

    List<SSHKeyPair>? identities;
    if (host.authMethod == HostAuthMethod.keyPair) {
      String? pem;
      if (host.sshKeyId != null) {
        pem = await keys.getPrivateKeyPem(host.sshKeyId!);
      } else {
        pem = await hosts.getEmbeddedPrivateKey(host);
      }
      if (pem != null && pem.isNotEmpty) {
        identities = SSHKeyPair.fromPem(pem);
      }
    }

    final password = host.authMethod == HostAuthMethod.password ? await hosts.getHostPassword(host) : null;

    final client = SSHClient(
      socket,
      username: host.username,
      identities: identities,
      keepAliveInterval: keepAliveInterval,
      onPasswordRequest: password != null ? () => password : null,
      onVerifyHostKey: (type, fingerprint) async {
        final fp = base64Encode(fingerprint);
        final trusted = await knownHosts.isTrusted(host.hostname, host.port, fp);
        if (trusted) return true;
        await knownHosts.trust(host.hostname, host.port, fp);
        return true;
      },
    );

    await client.authenticated;
    return SshConnection(client);
  }

  Future<String> openShell({
    required String channelId,
    int width = 80,
    int height = 24,
  }) async {
    if (_shells.containsKey(channelId)) return channelId;
    final session = await _client.shell(
      pty: SSHPtyConfig(width: width, height: height),
    );
    _shells[channelId] = ShellChannel(id: channelId, session: session);
    return channelId;
  }

  Future<void> closeShell(String channelId) async {
    final channel = _shells.remove(channelId);
    if (channel == null) return;
    await channel.stdoutSub?.cancel();
    await channel.stderrSub?.cancel();
    channel.session.close();
  }

  ShellChannel? _channel(String channelId) => _shells[channelId];

  void write(String channelId, String text) {
    if (!isConnected) return;
    _channel(channelId)?.session.write(Uint8List.fromList(utf8.encode(text)));
  }

  void writeBytes(String channelId, Uint8List bytes) {
    if (!isConnected) return;
    _channel(channelId)?.session.write(bytes);
  }

  void attachOutput(
    String channelId, {
    required void Function(String chunk) onStdout,
    void Function(String chunk)? onStderr,
  }) {
    final channel = _channel(channelId);
    if (channel == null) return;
    channel.stdoutSub?.cancel();
    channel.stderrSub?.cancel();
    channel.stdoutSub = channel.session.stdout.listen((data) {
      onStdout(utf8.decode(data, allowMalformed: true));
    });
    channel.stderrSub = channel.session.stderr.listen((data) {
      onStderr?.call(utf8.decode(data, allowMalformed: true));
    });
  }

  void resizeTerminal(String channelId, int width, int height) {
    if (!isConnected) return;
    final channel = _channel(channelId);
    if (channel == null) return;
    try {
      channel.session.resizeTerminal(width, height);
    } on SSHStateError {
      _disconnected = true;
    }
  }

  Future<void> ping() async {
    if (!isConnected) return;
    await _client.ping();
  }

  Future<SftpClient> sftp() async {
    if (!isConnected) throw SSHStateError('Transport is closed');
    _sftp ??= await _client.sftp();
    return _sftp!;
  }

  /// Drop the cached SFTP client so a new exec channel can open reliably.
  Future<void> prepareForExec() async {
    final client = _sftp;
    _sftp = null;
    if (client != null) {
      try {
        client.close();
      } catch (_) {}
    }
  }

  Future<List<RemoteFileEntry>> listDirectory(String path) async {
    final client = await sftp();
    final names = await client.listdir(path);
    return names.map(_mapSftpName).toList();
  }

  Future<void> createDirectory(String path) async {
    final client = await sftp();
    await client.mkdir(path);
  }

  Future<void> uploadFile(String localPath, String remotePath) async {
    final client = await sftp();
    final file = await client.open(
      remotePath,
      mode: SftpFileOpenMode.write | SftpFileOpenMode.create | SftpFileOpenMode.truncate,
    );
    try {
      await file.write(File(localPath).openRead().cast<Uint8List>()).done;
    } finally {
      await file.close();
    }
  }

  Future<void> uploadBytes(Uint8List data, String remotePath) async {
    final client = await sftp();
    final file = await client.open(
      remotePath,
      mode: SftpFileOpenMode.write | SftpFileOpenMode.create | SftpFileOpenMode.truncate,
    );
    try {
      await file.writeBytes(data);
    } finally {
      await file.close();
    }
  }

  RemoteFileEntry _mapSftpName(SftpName name) {
    final parts = name.longname.split(RegExp(r'\s+'));
    final perm = parts.isNotEmpty ? parts.first : '----------';
    return RemoteFileEntry(
      name: name.filename,
      isDirectory: name.attr.isDirectory,
      permissions: perm,
      size: name.attr.size,
    );
  }

  Future<({String stdout, String stderr, int? exitCode})> executeResult(
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!isConnected) throw SSHStateError('Transport is closed');

    final result = await _client
        .runWithResult(command, stderr: true)
        .timeout(timeout, onTimeout: () => throw TimeoutException('SSH command timed out', timeout));

    return (
      stdout: utf8.decode(result.stdout, allowMalformed: true),
      stderr: utf8.decode(result.stderr, allowMalformed: true),
      exitCode: result.exitCode,
    );
  }

  Future<bool> executeSuccess(
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final result = await executeResult(command, timeout: timeout);
    return result.exitCode == 0;
  }

  Future<String> executeCapture(
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final result = await executeResult(command, timeout: timeout);
    return result.stdout;
  }

  Future<LocalPortForward> forwardRemotePort(int remotePort, {String remoteHost = '127.0.0.1'}) async {
    final forward = await LocalPortForward.start(
      client: _client,
      remotePort: remotePort,
      remoteHost: remoteHost,
    );
    _forwards.add(forward);
    return forward;
  }

  Future<void> closeForward(LocalPortForward forward) async {
    _forwards.remove(forward);
    await forward.close();
  }

  Future<void> disconnect() async {
    _disconnected = true;
    for (final id in _shells.keys.toList()) {
      await closeShell(id);
    }
    for (final f in _forwards) {
      await f.close();
    }
    _forwards.clear();
    _client.close();
    await _client.done;
  }
}

class _IoSshSocket implements SSHSocket {
  _IoSshSocket(this._socket);

  final Socket _socket;

  @override
  Stream<Uint8List> get stream => _socket;

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  Future<void> close() => _socket.close();

  @override
  Future<void> get done => _socket.done;

  @override
  void destroy() => _socket.destroy();
}

/// Prefer IPv4 when both stacks resolve — avoids "No route to host" on IPv4-only networks.
Future<SSHSocket> _connectTcpSocket(
  String host,
  int port, {
  Duration? timeout,
}) async {
  final trimmed = host.trim();
  final literal = InternetAddress.tryParse(trimmed);
  final addresses = literal != null
      ? [literal]
      : await InternetAddress.lookup(trimmed);

  if (addresses.isEmpty) {
    throw SocketException('Failed host lookup: $trimmed');
  }

  final ordered = List<InternetAddress>.from(addresses)
    ..sort((a, b) {
      final a4 = a.type == InternetAddressType.IPv4;
      final b4 = b.type == InternetAddressType.IPv4;
      if (a4 == b4) return 0;
      return a4 ? -1 : 1;
    });

  Object? lastError;
  for (final address in ordered) {
    try {
      final socket = await Socket.connect(address, port, timeout: timeout);
      return _IoSshSocket(socket);
    } catch (e) {
      lastError = e;
    }
  }

  if (lastError != null) throw lastError;
  throw SocketException('Could not connect to $trimmed:$port');
}
