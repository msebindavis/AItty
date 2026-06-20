abstract final class SourceLanguage {
  static const _binaryExtensions = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'ico',
    'bmp',
    'pdf',
    'zip',
    'gz',
    'tar',
    'bz2',
    'xz',
    '7z',
    'rar',
    'bin',
    'exe',
    'dll',
    'so',
    'dylib',
    'a',
    'o',
    'wasm',
    'mp3',
    'mp4',
    'mov',
    'avi',
    'mkv',
    'woff',
    'woff2',
    'ttf',
    'otf',
    'eot',
    'class',
    'jar',
    'pyc',
    'sqlite',
    'db',
  };

  static String extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot <= 0 || dot == path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  static bool isPreviewable(String path) => !_binaryExtensions.contains(extension(path));

  static String? forPath(String path) {
    final baseName = path.split('/').last.toLowerCase();
    if (baseName == 'dockerfile') return 'dockerfile';
    if (baseName == 'makefile') return 'makefile';

    return switch (extension(path)) {
      'dart' => 'dart',
      'js' || 'jsx' || 'mjs' || 'cjs' => 'javascript',
      'ts' || 'tsx' => 'typescript',
      'py' || 'pyw' => 'python',
      'rb' => 'ruby',
      'go' => 'go',
      'rs' => 'rust',
      'java' => 'java',
      'kt' || 'kts' => 'kotlin',
      'swift' => 'swift',
      'c' || 'h' => 'c',
      'cpp' || 'cc' || 'cxx' || 'hpp' => 'cpp',
      'cs' => 'csharp',
      'php' => 'php',
      'sh' || 'bash' || 'zsh' => 'bash',
      'yaml' || 'yml' => 'yaml',
      'json' => 'json',
      'xml' || 'html' || 'htm' => 'xml',
      'css' || 'scss' || 'sass' => 'css',
      'sql' => 'sql',
      'md' || 'markdown' => 'markdown',
      'toml' => 'toml',
      'ini' || 'cfg' || 'conf' => 'ini',
      'dockerfile' => 'dockerfile',
      'gradle' => 'gradle',
      'lua' => 'lua',
      'r' => 'r',
      'pl' => 'perl',
      'ex' || 'exs' => 'elixir',
      'erl' => 'erlang',
      'hs' => 'haskell',
      'scala' => 'scala',
      'vue' => 'vue',
      'tf' => 'hcl',
      'proto' => 'protobuf',
      _ => null,
    };
  }
}
