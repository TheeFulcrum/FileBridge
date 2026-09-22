import 'package:flutter/material.dart';

import '../models/connection_profile.dart';
import '../services/secure_store.dart';
import 'edit_connection_screen.dart';
import 'session_screen.dart';

class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  late Future<List<ConnectionProfile>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = SecureStore.instance.loadProfiles();
    });
  }

  Future<void> _openEditor([ConnectionProfile? profile]) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditConnectionScreen(profile: profile)),
    );
    if (result == true) _reload();
  }

  Future<void> _delete(ConnectionProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove connection?'),
        content: Text('This will delete "${profile.name}" and its saved credentials.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await SecureStore.instance.deleteProfile(profile.id);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FileBridge')),
      body: FutureBuilder<List<ConnectionProfile>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final profiles = snapshot.data ?? [];
          if (profiles.isEmpty) {
            return _EmptyState(onAdd: () => _openEditor());
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: profiles.length,
            itemBuilder: (context, index) {
              final p = profiles[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?'),
                  ),
                  title: Text(p.name),
                  subtitle: Text('${p.username}@${p.host}:${p.port}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') _openEditor(p);
                      if (value == 'delete') _delete(p);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => SessionScreen(profile: p)),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add server'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dns_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No servers yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your Ubuntu machine\'s SSH details to start moving files.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add server'),
            ),
          ],
        ),
      ),
    );
  }
}
