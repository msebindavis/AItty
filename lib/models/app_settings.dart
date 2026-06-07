import 'host.dart';

class AppSettings {
  const AppSettings({
    this.keepAliveEnabled = true,
    this.keepAliveIntervalSeconds = 60,
    this.defaultTmuxMode = HostTmuxMode.attachExisting,
    this.detachOnAppClose = true,
  });

  final bool keepAliveEnabled;
  final int keepAliveIntervalSeconds;
  final HostTmuxMode defaultTmuxMode;
  final bool detachOnAppClose;

  Duration? get keepAliveInterval {
    if (!keepAliveEnabled || keepAliveIntervalSeconds <= 0) return null;
    return Duration(seconds: keepAliveIntervalSeconds);
  }

  AppSettings copyWith({
    bool? keepAliveEnabled,
    int? keepAliveIntervalSeconds,
    HostTmuxMode? defaultTmuxMode,
    bool? detachOnAppClose,
  }) {
    return AppSettings(
      keepAliveEnabled: keepAliveEnabled ?? this.keepAliveEnabled,
      keepAliveIntervalSeconds: keepAliveIntervalSeconds ?? this.keepAliveIntervalSeconds,
      defaultTmuxMode: defaultTmuxMode ?? this.defaultTmuxMode,
      detachOnAppClose: detachOnAppClose ?? this.detachOnAppClose,
    );
  }

  Map<String, dynamic> toJson() => {
        'keepAliveEnabled': keepAliveEnabled,
        'keepAliveIntervalSeconds': keepAliveIntervalSeconds,
        'defaultTmuxMode': defaultTmuxMode.name,
        'detachOnAppClose': detachOnAppClose,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        keepAliveEnabled: json['keepAliveEnabled'] as bool? ?? true,
        keepAliveIntervalSeconds: json['keepAliveIntervalSeconds'] as int? ?? 60,
        defaultTmuxMode: HostTmuxMode.values.byName(
          json['defaultTmuxMode'] as String? ?? HostTmuxMode.attachExisting.name,
        ),
        detachOnAppClose: json['detachOnAppClose'] as bool? ?? true,
      );
}
