import 'package:flutter/material.dart';

import '../models/connection_profile.dart';
import '../models/transfer_task.dart';
import '../services/ssh_service.dart';
import '../services/transfer_manager.dart';
import '../utils/formatters.dart';
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
  final _filesTabKey = GlobalKey<FilesTabState>();
  _ConnectStage _stage = _ConnectStage.connecting;
  String? _errorMessage;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _connect();
  }

  bool _handleBackNavigation() {
    if (_tabController.index != 0) {
      _tabController.animateTo(0);
      return true;
    }
    if (_filesTabKey.currentState?.canGoBack == true) {
      _filesTabKey.currentState?.goBack();
      return true;
    }
    return false;
  }

  Future<bool> _showDisconnectConfirmation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect?'),
        content: Text('Are you sure you want to disconnect from "${widget.profile.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay connected'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    return confirm ?? false;
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
    final nav = Navigator.of(context);
    return AnimatedBuilder(
      animation: _transferManager,
      builder: (context, _) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          final handled = _handleBackNavigation();
          if (!handled) {
            final confirm = await _showDisconnectConfirmation();
            if (confirm && mounted) {
              _ssh.disconnect();
              nav.pop();
            }
          }
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: () async {
                final handled = _handleBackNavigation();
                if (!handled) {
                  final confirm = await _showDisconnectConfirmation();
                  if (confirm && mounted) {
                    _ssh.disconnect();
                    nav.pop();
                  }
                }
              },
            ),
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
                  onPressed: () async {
                    final confirm = await _showDisconnectConfirmation();
                    if (confirm && mounted) {
                      _ssh.disconnect();
                      nav.pop();
                    }
                  },
                ),
            ],
          ),
          body: Column(
            children: [
              Expanded(child: _buildBody()),
              if (_stage == _ConnectStage.connected)
                _ActiveTransferBanner(
                  transferManager: _transferManager,
                  onViewTransfers: () => _tabController.animateTo(1),
                ),
            ],
          ),
        ),
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
            FilesTab(
              key: _filesTabKey,
              ssh: _ssh,
              profile: widget.profile,
              transferManager: _transferManager,
              onViewTransfers: () => _tabController.animateTo(1),
            ),
            TransfersTab(transferManager: _transferManager),
          ],
        );
    }
  }
}

class _ActiveTransferBanner extends StatelessWidget {
  final TransferManager transferManager;
  final VoidCallback onViewTransfers;

  const _ActiveTransferBanner({
    required this.transferManager,
    required this.onViewTransfers,
  });

  @override
  Widget build(BuildContext context) {
    final activeTasks = transferManager.tasks.where((t) => t.isActive).toList();
    if (activeTasks.isEmpty) return const SizedBox.shrink();

    final task = activeTasks.first;
    final isUpload = task.direction == TransferDirection.upload;
    final percentNum = (task.progress * 100).clamp(0, 100);
    final percentStr = percentNum.toStringAsFixed(0);
    final activeCount = activeTasks.length;
    final countSuffix = activeCount > 1 ? ' ($activeCount active)' : '';

    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                isUpload ? Icons.upload : Icons.download,
                color: theme.colorScheme.onPrimaryContainer,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${isUpload ? 'Uploading' : 'Downloading'} ${task.fileName}$countSuffix',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatBytes(task.transferredBytes)} / ${formatBytes(task.totalBytes)} ($percentStr%)',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onPrimaryContainer.withAlpha(216),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: onViewTransfers,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('View Queue'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: task.status == TransferStatus.queued ? null : task.progress,
              minHeight: 4,
              backgroundColor: theme.colorScheme.onPrimaryContainer.withAlpha(50),
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
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
