import 'package:flutter/material.dart';

import '../models/transfer_task.dart';
import '../services/transfer_manager.dart';
import '../utils/formatters.dart';

class TransfersTab extends StatelessWidget {
  final TransferManager transferManager;
  const TransfersTab({super.key, required this.transferManager});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: transferManager,
      builder: (context, _) {
        final tasks = transferManager.tasks;
        if (tasks.isEmpty) {
          return const Center(child: Text('No transfers yet'));
        }
        return ListView.builder(
          itemCount: tasks.length,
          itemBuilder: (context, i) => _TransferTile(
            task: tasks[i],
            onCancel: () => transferManager.cancel(tasks[i].id),
            onRemove: () => transferManager.remove(tasks[i].id),
          ),
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
    final directionIcon =
        task.direction == TransferDirection.upload ? Icons.upload : Icons.download;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(directionIcon, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.fileName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                _statusChip(task.status),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: task.progress),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '${formatBytes(task.transferredBytes)} / ${formatBytes(task.totalBytes)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Spacer(),
                if (task.isActive)
                  TextButton(onPressed: onCancel, child: const Text('Cancel'))
                else
                  TextButton(onPressed: onRemove, child: const Text('Remove')),
              ],
            ),
            if (task.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  task.error!,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
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
