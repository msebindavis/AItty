class ResumableSession {
  const ResumableSession({
    required this.id,
    required this.hostId,
    required this.tmuxSessionName,
    required this.cwd,
    required this.lastActiveAt,
    this.label,
    this.useTmux = true,
  });

  final String id;
  final String hostId;
  final String tmuxSessionName;
  final String cwd;
  final String? label;
  final DateTime lastActiveAt;
  final bool useTmux;

  String get displayLabel => label ?? (useTmux ? tmuxSessionName : 'Shell');

  ResumableSession copyWith({
    String? tmuxSessionName,
    String? cwd,
    String? label,
    DateTime? lastActiveAt,
    bool? useTmux,
  }) {
    return ResumableSession(
      id: id,
      hostId: hostId,
      tmuxSessionName: tmuxSessionName ?? this.tmuxSessionName,
      cwd: cwd ?? this.cwd,
      label: label ?? this.label,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      useTmux: useTmux ?? this.useTmux,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'hostId': hostId,
        'tmuxSessionName': tmuxSessionName,
        'cwd': cwd,
        if (label != null) 'label': label,
        'useTmux': useTmux,
        'lastActiveAt': lastActiveAt.toIso8601String(),
      };

  factory ResumableSession.fromJson(Map<String, dynamic> json) => ResumableSession(
        id: json['id'] as String,
        hostId: json['hostId'] as String,
        tmuxSessionName: json['tmuxSessionName'] as String,
        cwd: json['cwd'] as String,
        label: json['label'] as String?,
        useTmux: json['useTmux'] as bool? ?? true,
        lastActiveAt: DateTime.parse(json['lastActiveAt'] as String),
      );
}
