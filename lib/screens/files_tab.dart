import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/connection_profile.dart';
import '../models/remote_entry.dart';
import '../services/ssh_service.dart';
import '../services/transfer_manager.dart';
import '../utils/formatters.dart';

class FilesTab extends StatefulWidget {
  final SshService ssh;
  final ConnectionProfile profile;
  final TransferManager transferManager;
  final VoidCallback? onViewTransfers;

  const FilesTab({
    super.key,
    required this.ssh,
    required this.profile,
    required this.transferManager,
    this.onViewTransfers,
  });

  @override
  State<FilesTab> createState() => FilesTabState();
}

class FilesTabState extends State<FilesTab> with AutomaticKeepAliveClientMixin<FilesTab> {
  @override
  bool get wantKeepAlive => true;

  late String _currentPath;
  final List<String> _pathHistory = [];
  Future<List<RemoteEntry>>? _future;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.profile.remotePath;
    _refresh();
  }

  bool get canGoBack =>
      _pathHistory.isNotEmpty || (_currentPath != '/' && _currentPath != '.');

  bool goBack() {
    if (_pathHistory.isNotEmpty) {
      setState(() {
        _currentPath = _pathHistory.removeLast();
        _future = widget.ssh.listDirectory(_currentPath);
      });
      return true;
    }
    if (_currentPath != '/' && _currentPath != '.') {
      _goUp();
      return true;
    }
    return false;
  }

  void _refresh() {
    setState(() {
      _future = widget.ssh.listDirectory(_currentPath);
    });
  }

  void _open(RemoteEntry entry) {
    if (!entry.isDirectory) return _showFileActions(entry);
    _pathHistory.add(_currentPath);
    setState(() {
      _currentPath = entry.path;
      _future = widget.ssh.listDirectory(_currentPath);
    });
  }

  void _goUp() {
    if (_pathHistory.isNotEmpty) {
      setState(() {
        _currentPath = _pathHistory.removeLast();
        _future = widget.ssh.listDirectory(_currentPath);
      });
      return;
    }
    if (_currentPath == '/' || _currentPath == '.') return;
    final parts = _currentPath.split('/')..removeLast();
    final parent = parts.isEmpty || parts.join('/').isEmpty ? '/' : parts.join('/');
    setState(() {
      _currentPath = parent;
      _future = widget.ssh.listDirectory(_currentPath);
    });
  }

  Future<void> _upload() async {
    final files = await FilePicker.pickFiles();
    for (final file in files) {
      final path = file.path;
      if (path == null) continue;
      final remotePath = _joinPath(_currentPath, file.name);
      final size = file.lengthSync() ?? await file.length() ?? 0;
      widget.transferManager.enqueueUpload(
        widget.ssh,
        localPath: path,
        remotePath: remotePath,
        fileName: file.name,
        totalBytes: size,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Upload queued'),
          action: widget.onViewTransfers != null
              ? SnackBarAction(
                  label: 'View',
                  onPressed: widget.onViewTransfers!,
                )
              : null,
        ),
      );
    }
  }

  Future<void> _download(RemoteEntry entry) async {
    if (entry.isDirectory) {
      _showError('Folder downloads are not supported yet. Select a file.');
      return;
    }
    try {
      Directory? dir;
      try {
        dir = await getApplicationDocumentsDirectory();
      } catch (_) {
        dir = await getExternalStorageDirectory();
      }
      if (dir == null) {
        _showError('Could not access storage directory on device');
        return;
      }
      final downloads = Directory('${dir.path}/FileBridge');
      if (!await downloads.exists()) {
        await downloads.create(recursive: true);
      }
      final localPath = '${downloads.path}/${entry.name}';
      widget.transferManager.enqueueDownload(
        widget.ssh,
        localPath: localPath,
        remotePath: entry.path,
        fileName: entry.name,
        totalBytes: entry.size ?? 0,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloading ${entry.name}'),
            action: widget.onViewTransfers != null
                ? SnackBarAction(
                    label: 'View',
                    onPressed: widget.onViewTransfers!,
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Download error: $e');
      }
    }
  }

  Future<void> _mkdir() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await widget.ssh.makeDirectory(_joinPath(_currentPath, name));
      _refresh();
    } catch (e) {
      _showError('Could not create folder: $e');
    }
  }

  Future<void> _delete(RemoteEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Delete "${entry.name}" from the server? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.ssh.delete(entry.path, isDirectory: entry.isDirectory);
      _refresh();
    } catch (e) {
      _showError('Could not delete: $e');
    }
  }

  Future<void> _rename(RemoteEntry entry) async {
    final controller = TextEditingController(text: entry.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == entry.name) return;
    try {
      await widget.ssh.rename(entry.path, _joinPath(_currentPath, name));
      _refresh();
    } catch (e) {
      _showError('Could not rename: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _joinPath(String base, String name) {
    if (base == '/') return '/$name';
    return '$base/$name';
  }

  void _showFileActions(RemoteEntry entry) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Download'),
              onTap: () {
                Navigator.pop(ctx);
                _download(entry);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(ctx);
                _rename(entry);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(ctx);
                _delete(entry);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: Column(
        children: [
          Material(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    tooltip: 'Up',
                    onPressed: canGoBack ? _goUp : null,
                  ),
                  Expanded(
                    child: Text(
                      _currentPath,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.create_new_folder_outlined),
                    tooltip: 'New folder',
                    onPressed: _mkdir,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                    onPressed: _refresh,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: FutureBuilder<List<RemoteEntry>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  final entries = snapshot.data ?? [];
                  if (entries.isEmpty) {
                    return const Center(child: Text('This folder is empty'));
                  }
                  return ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      return ListTile(
                        leading: Icon(
                          entry.isDirectory
                              ? Icons.folder
                              : Icons.insert_drive_file_outlined,
                          color: entry.isDirectory ? Colors.amber[700] : Colors.blueGrey,
                        ),
                        title: Text(entry.name),
                        subtitle: entry.isDirectory
                            ? null
                            : Text('${formatBytes(entry.size)} · ${formatDate(entry.modified)}'),
                        onTap: () => _open(entry),
                        onLongPress: () => _showFileActions(entry),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _upload,
        tooltip: 'Upload files',
        child: const Icon(Icons.upload_file),
      ),
    );
  }
}
