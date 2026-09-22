enum AuthMethod { password, privateKey }

/// A saved SSH/SFTP connection profile. Secrets (password, private key,
/// passphrase) are stored in the same encrypted blob managed by
/// [SecureStore], never in plain shared preferences.
class ConnectionProfile {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final AuthMethod authMethod;
  final String? password;
  final String? privateKeyPem;
  final String? passphrase;
  final String remotePath;

  const ConnectionProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.authMethod,
    this.password,
    this.privateKeyPem,
    this.passphrase,
    this.remotePath = '.',
  });

  ConnectionProfile copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    AuthMethod? authMethod,
    String? password,
    String? privateKeyPem,
    String? passphrase,
    String? remotePath,
  }) {
    return ConnectionProfile(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
      password: password ?? this.password,
      privateKeyPem: privateKeyPem ?? this.privateKeyPem,
      passphrase: passphrase ?? this.passphrase,
      remotePath: remotePath ?? this.remotePath,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'authMethod': authMethod.name,
        'password': password,
        'privateKeyPem': privateKeyPem,
        'passphrase': passphrase,
        'remotePath': remotePath,
      };

  factory ConnectionProfile.fromJson(Map<String, dynamic> json) {
    return ConnectionProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int,
      username: json['username'] as String,
      authMethod: AuthMethod.values.firstWhere(
        (e) => e.name == json['authMethod'],
        orElse: () => AuthMethod.password,
      ),
      password: json['password'] as String?,
      privateKeyPem: json['privateKeyPem'] as String?,
      passphrase: json['passphrase'] as String?,
      remotePath: json['remotePath'] as String? ?? '.',
    );
  }
}
