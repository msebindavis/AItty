enum HostAuthMethod { password, keyPair }

enum HostReachability { online, offline, unknown }

enum HostGroup { production, staging, development, personal }

enum HostTmuxMode { inherit, off, attachExisting, createNew }

class Host {
  const Host({
    required this.id,
    required this.label,
    required this.hostname,
    required this.username,
    this.group = HostGroup.production,
    this.port = 22,
    this.authMethod = HostAuthMethod.password,
    this.sshKeyId,
    this.reachability = HostReachability.unknown,
    this.tags = const [],
    this.isRecent = false,
    this.tmuxMode = HostTmuxMode.inherit,
    this.tmuxSessionName,
    this.startupSnippet,
    this.keepAliveIntervalSeconds,
  });

  final String id;
  final String label;
  final String hostname;
  final String username;
  final HostGroup group;
  final int port;
  final HostAuthMethod authMethod;
  final String? sshKeyId;
  final HostReachability reachability;
  final List<String> tags;
  final bool isRecent;
  final HostTmuxMode tmuxMode;
  final String? tmuxSessionName;
  final String? startupSnippet;
  final int? keepAliveIntervalSeconds;

  String get connectionString => '$username@$hostname';

  String get groupLabel => switch (group) {
        HostGroup.production => 'PRODUCTION',
        HostGroup.staging => 'STAGING',
        HostGroup.development => 'DEVELOPMENT',
        HostGroup.personal => 'PERSONAL',
      };

  Host copyWith({
    String? label,
    String? hostname,
    String? username,
    HostGroup? group,
    int? port,
    HostAuthMethod? authMethod,
    String? sshKeyId,
    HostReachability? reachability,
    List<String>? tags,
    bool? isRecent,
    HostTmuxMode? tmuxMode,
    String? tmuxSessionName,
    String? startupSnippet,
    int? keepAliveIntervalSeconds,
  }) {
    return Host(
      id: id,
      label: label ?? this.label,
      hostname: hostname ?? this.hostname,
      username: username ?? this.username,
      group: group ?? this.group,
      port: port ?? this.port,
      authMethod: authMethod ?? this.authMethod,
      sshKeyId: sshKeyId ?? this.sshKeyId,
      reachability: reachability ?? this.reachability,
      tags: tags ?? this.tags,
      isRecent: isRecent ?? this.isRecent,
      tmuxMode: tmuxMode ?? this.tmuxMode,
      tmuxSessionName: tmuxSessionName ?? this.tmuxSessionName,
      startupSnippet: startupSnippet ?? this.startupSnippet,
      keepAliveIntervalSeconds: keepAliveIntervalSeconds ?? this.keepAliveIntervalSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'hostname': hostname,
        'username': username,
        'group': group.name,
        'port': port,
        'authMethod': authMethod.name,
        if (sshKeyId != null) 'sshKeyId': sshKeyId,
        'reachability': reachability.name,
        if (tags.isNotEmpty) 'tags': tags,
        'tmuxMode': tmuxMode.name,
        if (tmuxSessionName != null) 'tmuxSessionName': tmuxSessionName,
        if (startupSnippet != null) 'startupSnippet': startupSnippet,
        if (keepAliveIntervalSeconds != null) 'keepAliveIntervalSeconds': keepAliveIntervalSeconds,
      };

  factory Host.fromJson(Map<String, dynamic> json) => Host(
        id: json['id'] as String,
        label: json['label'] as String,
        hostname: json['hostname'] as String,
        username: json['username'] as String,
        group: HostGroup.values.byName(json['group'] as String? ?? 'production'),
        port: json['port'] as int? ?? 22,
        authMethod: HostAuthMethod.values.byName(json['authMethod'] as String? ?? 'password'),
        sshKeyId: json['sshKeyId'] as String?,
        reachability: HostReachability.values.byName(json['reachability'] as String? ?? 'unknown'),
        tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
        tmuxMode: HostTmuxMode.values.byName(json['tmuxMode'] as String? ?? 'inherit'),
        tmuxSessionName: json['tmuxSessionName'] as String?,
        startupSnippet: json['startupSnippet'] as String?,
        keepAliveIntervalSeconds: json['keepAliveIntervalSeconds'] as int?,
      );
}
