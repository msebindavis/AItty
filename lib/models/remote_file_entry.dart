class RemoteFileEntry {
  const RemoteFileEntry({
    required this.name,
    required this.isDirectory,
    required this.permissions,
    this.size,
    this.modified,
  });

  final String name;
  final bool isDirectory;
  final String permissions;
  final int? size;
  final String? modified;
}
