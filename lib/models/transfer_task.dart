enum TransferDirection { upload, download }

enum TransferStatus { queued, running, completed, failed, cancelled }

/// Mutable state for one file transfer. Owned and mutated by
/// [TransferManager], which calls [notifyListeners] on the manager after
/// every update so the UI can reactively rebuild.
class TransferTask {
  final String id;
  final String fileName;
  final TransferDirection direction;
  final String localPath;
  final String remotePath;
  final int totalBytes;

  int transferredBytes;
  TransferStatus status;
  String? error;
  void Function()? _cancel;

  TransferTask({
    required this.id,
    required this.fileName,
    required this.direction,
    required this.localPath,
    required this.remotePath,
    required this.totalBytes,
    this.transferredBytes = 0,
    this.status = TransferStatus.queued,
    this.error,
  });

  double get progress =>
      totalBytes <= 0 ? 0 : (transferredBytes / totalBytes).clamp(0, 1);

  bool get isActive =>
      status == TransferStatus.queued || status == TransferStatus.running;

  bool cancelRequested = false;

  void bindCancel(void Function() cancel) => _cancel = cancel;

  void requestCancel() {
    cancelRequested = true;
    _cancel?.call();
  }
}
