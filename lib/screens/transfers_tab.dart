import 'package:flutter/material.dart';

import '../models/transfer_task.dart';
import '../services/transfer_manager.dart';
import '../utils/formatters.dart';

class TransfersTab extends StatefulWidget {
  final TransferManager transferManager;
  const TransfersTab({super.key, required this.transferManager});

  @override
  State<TransfersTab> createState() => _TransfersTabState();
}

class _TransfersTabState extends State<TransfersTab>
    with AutomaticKeepAliveClientMixin<TransfersTab> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnimatedBuilder(
      animation: widget.transferManager,
      builder: (context, _) {
        final tasks = widget.transferManager.tasks;
        if (tasks.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_vert_circle_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'No transfers yet',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          );
        }
        final hasFinished = tasks.any((t) => !t.isActive);
        return Column(
          children: [
            if (hasFinished)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      '${tasks.length} transfer${tasks.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: widget.transferManager.clearFinished,
                      icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                      label: const Text('Clear finished'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                itemCount: tasks.length,
                itemBuilder: (context, i) => _TransferTile(
                  task: tasks[i],
                  onCancel: () => widget.transferManager.cancel(tasks[i].id),
                  onRemove: () => widget.transferManager.remove(tasks[i].id),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TransferTile extends StatelessWidget {
  final TransferTask task;
  final VoidCallback onCancel;
  final VoidCallback onRemove;

  const _TransferTile({
    required this.task,
    required this.onCancel,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isUpload = task.direction == TransferDirection.upload;
    final directionIcon = isUpload ? Icons.upload_file : Icons.download_for_offline;
    final iconColor = isUpload ? Colors.blue : Colors.teal;
    final percentNum = (task.progress * 100).clamp(0, 100);
    final percentStr = percentNum.toStringAsFixed(1);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: iconColor.withAlpha(38),
                  child: Icon(directionIcon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.fileName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isUpload ? 'Upload to PC' : 'Download to Phone',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _statusChip(task.status),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.status == TransferStatus.queued ? null : task.progress,
                minHeight: 8,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(
                  task.status == TransferStatus.completed
                      ? Colors.green
                      : task.status == TransferStatus.failed
                          ? Colors.red
                          : iconColor,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${formatBytes(task.transferredBytes)} / ${formatBytes(task.totalBytes)} ($percentStr%)',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                if (task.isActive)
                  OutlinedButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Remove',
                    onPressed: onRemove,
                  ),
              ],
            ),
            if (task.error != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.error!,
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(TransferStatus status) {
    Color color;
    String label;
    switch (status) {
      case TransferStatus.queued:
        color = Colors.grey;
        label = 'Queued';
        break;
      case TransferStatus.running:
        color = Colors.blue;
        label = 'Running';
        break;
      case TransferStatus.completed:
        color = Colors.green;
        label = 'Done';
        break;
      case TransferStatus.failed:
        color = Colors.red;
        label = 'Failed';
        break;
      case TransferStatus.cancelled:
        color = Colors.orange;
        label = 'Cancelled';
        break;
    }
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white)),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}
