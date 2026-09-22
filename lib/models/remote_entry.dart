import 'package:dartssh2/dartssh2.dart';

/// A single entry (file or directory) inside a remote directory listing.
class RemoteEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final bool isSymlink;
  final int? size;
  final DateTime? modified;

  const RemoteEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.isSymlink,
    this.size,
    this.modified,
  });

  factory RemoteEntry.fromSftpName(SftpName entry, String parentPath) {
    final attrs = entry.attr;
    final path = parentPath == '/'
        ? '/${entry.filename}'
        : '$parentPath/${entry.filename}';
    return RemoteEntry(
      name: entry.filename,
      path: path,
      isDirectory: attrs.isDirectory,
      isSymlink: attrs.isSymbolicLink,
      size: attrs.size,
      modified: attrs.modifyTime != null
          ? DateTime.fromMillisecondsSinceEpoch(attrs.modifyTime! * 1000)
          : null,
    );
  }
}
