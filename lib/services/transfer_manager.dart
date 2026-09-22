import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/transfer_task.dart';
import 'ssh_service.dart';

/// Runs uploads/downloads against an [SshService], keeping a list of
/// [TransferTask]s that the UI observes. At most [maxConcurrent] transfers
/// run at once; the rest wait in the queue.
class TransferManager extends ChangeNotifier {
  final List<TransferTask> _tasks = [];
  final int maxConcurrent;
  int _running = 0;

  TransferManager({this.maxConcurrent = 2});

  List<TransferTask> get tasks => List.unmodifiable(_tasks);

  int get activeCount => _tasks.where((t) => t.isActive).length;

  void _safeNotifyListeners() {
    Future.microtask(() => notifyListeners());
  }

  String enqueueUpload(
    SshService ssh, {
    required String localPath,
    required String remotePath,
    required String fileName,
    required int totalBytes,
  }) {
    final task = TransferTask(
      id: const Uuid().v4(),
      fileName: fileName,
      direction: TransferDirection.upload,
      localPath: localPath,
      remotePath: remotePath,
      totalBytes: totalBytes,
    );
    _tasks.insert(0, task);
    _safeNotifyListeners();
    _runNext(ssh);
    return task.id;
  }

  String enqueueDownload(
    SshService ssh, {
    required String localPath,
    required String remotePath,
    required String fileName,
    required int totalBytes,
  }) {
    final task = TransferTask(
      id: const Uuid().v4(),
      fileName: fileName,
      direction: TransferDirection.download,
      localPath: localPath,
      remotePath: remotePath,
      totalBytes: totalBytes,
    );
    _tasks.insert(0, task);
    _safeNotifyListeners();
    _runNext(ssh);
    return task.id;
  }

  void cancel(String id) {
    final task = _tasks.firstWhere((t) => t.id == id);
    task.requestCancel();
  }

  void remove(String id) {
    _tasks.removeWhere((t) => t.id == id && !t.isActive);
    _safeNotifyListeners();
  }

  void clearFinished() {
    _tasks.removeWhere((t) => !t.isActive);
    _safeNotifyListeners();
  }

  Future<void> _runNext(SshService ssh) async {
    if (_running >= maxConcurrent) return;
    final next = _tasks.firstWhere(
      (t) => t.status == TransferStatus.queued,
      orElse: () => TransferTask(
        id: '',
        fileName: '',
        direction: TransferDirection.upload,
        localPath: '',
        remotePath: '',
        totalBytes: 0,
      ),
    );
    if (next.id.isEmpty) return;

    _running++;
    next.status = TransferStatus.running;
    _safeNotifyListeners();

    try {
      int lastNotify = 0;
      void onProgress(int transferred) {
        next.transferredBytes = transferred;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastNotify > 100 || transferred == next.totalBytes) {
          lastNotify = now;
          _safeNotifyListeners();
        }
      }

      void onCancelBound(void Function() cancel) => next.bindCancel(cancel);

      if (next.direction == TransferDirection.upload) {
        await ssh.uploadFile(
          next.localPath,
          next.remotePath,
          onProgress: onProgress,
          onCancelBound: onCancelBound,
        );
      } else {
        await ssh.downloadFile(
          next.remotePath,
          next.localPath,
          onProgress: onProgress,
          onCancelBound: onCancelBound,
        );
      }
      next.status =
          next.cancelRequested ? TransferStatus.cancelled : TransferStatus.completed;
    } catch (e) {
      next.status =
          next.cancelRequested ? TransferStatus.cancelled : TransferStatus.failed;
      next.error = '$e';
    } finally {
      _running--;
      _safeNotifyListeners();
      _runNext(ssh);
    }
  }
}
