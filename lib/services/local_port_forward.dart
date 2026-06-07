import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

/// Listens on 127.0.0.1 and pipes each connection through SSH to remote localhost:port.
class LocalPortForward {
  LocalPortForward({
    required this.localPort,
    required this.server,
    required this.subscription,
  });

  final int localPort;
  final ServerSocket server;
  final StreamSubscription<Socket> subscription;

  static Future<LocalPortForward> start({
    required SSHClient client,
    required int remotePort,
    String remoteHost = '127.0.0.1',
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sub = server.listen((socket) async {
      try {
        final forward = await client.forwardLocal(remoteHost, remotePort);
        forward.stream.listen((data) => socket.add(data));
        socket.listen(
          (data) => forward.sink.add(data),
          onDone: () => forward.sink.close(),
          onError: (_) => forward.sink.close(),
        );
      } catch (_) {
        await socket.close();
      }
    });
    return LocalPortForward(
      localPort: server.port,
      server: server,
      subscription: sub,
    );
  }

  Future<void> close() async {
    await subscription.cancel();
    await server.close();
  }
}
