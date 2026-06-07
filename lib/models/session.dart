enum SessionState {
  connected,
  processing,
  awaitingInput,
  idle,
  reconnecting,
  disconnected,
}

class Session {
  const Session({
    required this.id,
    required this.hostId,
    required this.title,
    required this.connectionString,
    required this.state,
    required this.lastOutputLine,
    this.iconName = 'dns',
  });

  final String id;
  final String hostId;
  final String title;
  final String connectionString;
  final SessionState state;
  final String lastOutputLine;
  final String iconName;
}
