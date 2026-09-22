import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/connection_profile.dart';
import '../models/remote_entry.dart';
import 'secure_store.dart';

/// Thrown when a remote host presents a key fingerprint that does not match
/// the one we trusted the first time we connected to it. This usually means
/// the server was reinstalled (fine, for personal use) or, less commonly,
/// a man-in-the-middle. The caller decides whether to re-trust it.
class HostKeyMismatchException implements Exception {
  final String host;
  final int port;
  final String newFingerprint;
  HostKeyMismatchException(this.host, this.port, this.newFingerprint);

  @override
  String toString() =>
      'Host key for $host:$port changed. New fingerprint: $newFingerprint';
}

/// Wraps a single [SSHClient] + [SftpClient] pair for one active session.
class SshService {
  SSHClient? _client;
  SftpClient? _sftp;

  bool get isConnected => _client != null && !(_client!.isClosed);

  Future<void> connect(
    ConnectionProfile profile, {
    bool forceTrustNewHostKey = false,
  }) async {
    final socket = await SSHSocket.connect(
      profile.host,
      profile.port,
      timeout: const Duration(seconds: 15),
    );

    List<SSHKeyPair>? identities;
    if (profile.authMethod == AuthMethod.privateKey &&
        profile.privateKeyPem != null &&
        profile.privateKeyPem!.isNotEmpty) {
      identities = SSHKeyPair.fromPem(profile.privateKeyPem!, profile.passphrase);
    }

    final client = SSHClient(
      socket,
      username: profile.username,
      identities: identities,
      onPasswordRequest: profile.authMethod == AuthMethod.password
          ? () => profile.password ?? ''
          : null,
      onVerifyHostKey: (type, fingerprintBytes) async {
        final fingerprint = String.fromCharCodes(fingerprintBytes);
        final known =
            await SecureStore.instance.getKnownFingerprint(profile.host, profile.port);
        if (known == null) {
          await SecureStore.instance
              .trustFingerprint(profile.host, profile.port, fingerprint);
          return true;
        }
        if (known == fingerprint) return true;
        if (forceTrustNewHostKey) {
          await SecureStore.instance
              .trustFingerprint(profile.host, profile.port, fingerprint);
          return true;
        }
        throw HostKeyMismatchException(profile.host, profile.port, fingerprint);
      },
    );

    await client.authenticated;
    _client = client;
    _sftp = await client.sftp();
  }

  void disconnect() {
    _sftp = null;
    _client?.close();
    _client = null;
  }

  SftpClient get _requireSftp {
    final sftp = _sftp;
    if (sftp == null) throw StateError('Not connected');
    return sftp;
  }

  Future<List<RemoteEntry>> listDirectory(String path) async {
    final names = await _requireSftp.listdir(path);
    return names
        .where((n) => n.filename != '.' && n.filename != '..')
        .map((n) => RemoteEntry.fromSftpName(n, path))
        .toList()
      ..sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  Future<void> makeDirectory(String path) => _requireSftp.mkdir(path);

  Future<void> delete(String path, {required bool isDirectory}) async {
    if (isDirectory) {
      await _requireSftp.rmdir(path);
    } else {
      await _requireSftp.remove(path);
    }
  }

  Future<void> rename(String oldPath, String newPath) =>
      _requireSftp.rename(oldPath, newPath);

  /// Uploads a local file to [remotePath], reporting progress and returning
  /// a cancel function the caller can invoke to abort mid-transfer.
  Future<void> uploadFile(
    String localPath,
    String remotePath, {
    required void Function(int transferred) onProgress,
    required void Function(void Function() cancel) onCancelBound,
  }) async {
    final localFile = File(localPath);
    if (!await localFile.exists()) {
      throw FileSystemException('Local file does not exist', localPath);
    }
    final length = await localFile.length();
    final remote = await _requireSftp.open(
      remotePath,
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.truncate |
          SftpFileOpenMode.write,
    );
    try {
      final writer = remote.write(
        localFile.openRead().cast<Uint8List>(),
        onProgress: onProgress,
      );
      onCancelBound(() => writer.abort());
      await writer.done;
      if (length == 0) onProgress(0);
    } finally {
      try {
        await remote.close();
      } catch (_) {}
    }
  }

  /// Downloads a remote file to [localPath], reporting progress and
  /// returning a cancel function.
  Future<void> downloadFile(
    String remotePath,
    String localPath, {
    required void Function(int transferred) onProgress,
    required void Function(void Function() cancel) onCancelBound,
  }) async {
    final remote = await _requireSftp.open(remotePath);
    final localFile = File(localPath);
    await localFile.parent.create(recursive: true);
    final sink = localFile.openWrite();
    sink.done.catchError((_) {});

    StreamSubscription<Uint8List>? sub;
    final completer = Completer<void>();
    var cancelled = false;
    try {
      sub = remote.read(onProgress: onProgress).listen(
        (chunk) {
          try {
            sink.add(chunk);
          } catch (e, st) {
            if (!completer.isCompleted) completer.completeError(e, st);
          }
        },
        onDone: () {
          sink.flush().then((_) {
            if (!completer.isCompleted) completer.complete();
          }).catchError((Object e, StackTrace st) {
            if (!completer.isCompleted) completer.completeError(e, st);
          });
        },
        onError: (Object e, StackTrace st) {
          if (!completer.isCompleted) completer.completeError(e, st);
        },
        cancelOnError: true,
      );
      onCancelBound(() {
        cancelled = true;
        sub?.cancel();
        if (!completer.isCompleted) completer.complete();
      });
      await completer.future;
    } finally {
      await sub?.cancel();
      try {
        await sink.close();
      } catch (_) {}
      try {
        await remote.close();
      } catch (_) {}
      if (cancelled) {
        if (await localFile.exists()) {
          try {
            await localFile.delete();
          } catch (_) {}
        }
      }
    }
  }
}
