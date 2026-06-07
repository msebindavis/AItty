class SessionStartChoice {
  const SessionStartChoice({
    required this.useTmux,
    this.sessionName,
  });

  final bool useTmux;
  final String? sessionName;
}
