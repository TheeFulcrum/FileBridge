import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/connection_profile.dart';

/// Persists connection profiles (including secrets) and trusted host-key
/// fingerprints using the platform keystore/keychain via
/// [FlutterSecureStorage]. Nothing here ever touches plain shared
/// preferences or disk in cleartext.
class SecureStore {
  SecureStore._();
  static final SecureStore instance = SecureStore._();

  static const _profilesKey = 'filebridge.connection_profiles';
  static const _knownHostsKey = 'filebridge.known_hosts';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  Future<List<ConnectionProfile>> loadProfiles() async {
    final raw = await _storage.read(key: _profilesKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => ConnectionProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveProfile(ConnectionProfile profile) async {
    final profiles = await loadProfiles();
    final index = profiles.indexWhere((p) => p.id == profile.id);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.add(profile);
    }
    await _persistProfiles(profiles);
  }

  Future<void> deleteProfile(String id) async {
    final profiles = await loadProfiles();
    profiles.removeWhere((p) => p.id == id);
    await _persistProfiles(profiles);
  }

  Future<void> _persistProfiles(List<ConnectionProfile> profiles) async {
    final raw = jsonEncode(profiles.map((p) => p.toJson()).toList());
    await _storage.write(key: _profilesKey, value: raw);
  }

  /// Returns the trusted fingerprint for `host:port`, or null if this host
  /// has never been connected to before (trust-on-first-use).
  Future<String?> getKnownFingerprint(String host, int port) async {
    final map = await _loadKnownHosts();
    return map['$host:$port'];
  }

  Future<void> trustFingerprint(String host, int port, String fingerprint) async {
    final map = await _loadKnownHosts();
    map['$host:$port'] = fingerprint;
    await _storage.write(key: _knownHostsKey, value: jsonEncode(map));
  }

  Future<void> forgetFingerprint(String host, int port) async {
    final map = await _loadKnownHosts();
    map.remove('$host:$port');
    await _storage.write(key: _knownHostsKey, value: jsonEncode(map));
  }

  Future<Map<String, String>> _loadKnownHosts() async {
    final raw = await _storage.read(key: _knownHostsKey);
    if (raw == null || raw.isEmpty) return {};
    return Map<String, String>.from(jsonDecode(raw) as Map);
  }
}
