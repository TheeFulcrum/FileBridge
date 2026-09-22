import 'package:flutter/material.dart';

import '../models/connection_profile.dart';
import '../services/ssh_service.dart';
import '../services/transfer_manager.dart';
import 'files_tab.dart';
import 'transfers_tab.dart';

enum _ConnectStage { connecting, connected, hostKeyMismatch, error }

class SessionScreen extends StatefulWidget {
  final ConnectionProfile profile;
  const SessionScreen({super.key, required this.profile});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> with SingleTickerProviderStateMixin {
  final _ssh = SshService();
  final _transferManager = TransferManager();
  _ConnectStage _stage = _ConnectStage.connecting;
  String? _errorMessage;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _connect();
  }

  Future<void> _connect({bool trustNewKey = false}) async {
    setState(() {
      _stage = _ConnectStage.connecting;
      _errorMessage = null;
    });
    try {
      await _ssh.connect(widget.profile, forceTrustNewHostKey: trustNewKey);
      if (mounted) setState(() => _stage = _ConnectStage.connected);
    } on HostKeyMismatchException {
      if (mounted) setState(() => _stage = _ConnectStage.hostKeyMismatch);
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _ConnectStage.error;
          _errorMessage = '$e';
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ssh.disconnect();
    _transferManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _transferManager,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(widget.profile.name),
          bottom: _stage == _ConnectStage.connected
              ? TabBar(
                  controller: _tabController,
                  tabs: [
                    const Tab(icon: Icon(Icons.folder_open), text: 'Files'),
                    Tab(
                      icon: const Icon(Icons.swap_vert),
                      text: _transferManager.activeCount > 0
                          ? 'Transfers (${_transferManager.activeCount})'
                          : 'Transfers',
                    ),
                  ],
                )
              : null,
          actions: [
            if (_stage == _ConnectStage.connected)
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Disconnect',
                onPressed: () {
                  _ssh.disconnect();
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_stage) {
      case _ConnectStage.connecting:
        return const Center(child: CircularProgressIndicator());
      case _ConnectStage.hostKeyMismatch:
        return _HostKeyWarning(
          profile: widget.profile,
          onTrustAndRetry: () => _connect(trustNewKey: true),
          onCancel: () => Navigator.of(context).pop(),
        );
      case _ConnectStage.error:
        return _ConnectError(
          message: _errorMessage ?? 'Unknown error',
          onRetry: () => _connect(),
        );
      case _ConnectStage.connected:
        return TabBarView(
          controller: _tabController,
          children: [
            FilesTab(ssh: _ssh, profile: widget.profile, transferManager: _transferManager),
            TransfersTab(transferManager: _transferManager),
          ],
        );
    }
  }
}

class _HostKeyWarning extends StatelessWidget {
  final ConnectionProfile profile;
  final VoidCallback onTrustAndRetry;
  final VoidCallback onCancel;

  const _HostKeyWarning({
    required this.profile,
    required this.onTrustAndRetry,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 56),
            const SizedBox(height: 16),
            Text(
              'The SSH host key for ${profile.host} has changed',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'This normally happens after reinstalling or re-keying your Ubuntu '
              'machine. Only continue if you expect this.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
                const SizedBox(width: 12),
                FilledButton(onPressed: onTrustAndRetry, child: const Text('Trust & connect')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ConnectError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 56),
            const SizedBox(height: 16),
            const Text('Could not connect', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
