import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/connection_profile.dart';
import '../services/secure_store.dart';

class EditConnectionScreen extends StatefulWidget {
  final ConnectionProfile? profile;
  const EditConnectionScreen({super.key, this.profile});

  @override
  State<EditConnectionScreen> createState() => _EditConnectionScreenState();
}

class _EditConnectionScreenState extends State<EditConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _privateKey;
  late final TextEditingController _passphrase;
  late final TextEditingController _remotePath;
  late AuthMethod _authMethod;
  bool _obscurePassword = true;
  bool _saving = false;

  bool get _isEditing => widget.profile != null;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _name = TextEditingController(text: p?.name ?? '');
    _host = TextEditingController(text: p?.host ?? '');
    _port = TextEditingController(text: (p?.port ?? 22).toString());
    _username = TextEditingController(text: p?.username ?? '');
    _password = TextEditingController(text: p?.password ?? '');
    _privateKey = TextEditingController(text: p?.privateKeyPem ?? '');
    _passphrase = TextEditingController(text: p?.passphrase ?? '');
    _remotePath = TextEditingController(text: p?.remotePath ?? '.');
    _authMethod = p?.authMethod ?? AuthMethod.password;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _host,
      _port,
      _username,
      _password,
      _privateKey,
      _passphrase,
      _remotePath,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickKeyFile() async {
    final file = await FilePicker.pickFile();
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _privateKey.text = utf8.decode(bytes));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final profile = ConnectionProfile(
        id: widget.profile?.id ?? const Uuid().v4(),
        name: _name.text.trim(),
        host: _host.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? 22,
        username: _username.text.trim(),
        authMethod: _authMethod,
        password: _authMethod == AuthMethod.password ? _password.text : null,
        privateKeyPem: _authMethod == AuthMethod.privateKey ? _privateKey.text : null,
        passphrase: _authMethod == AuthMethod.privateKey && _passphrase.text.isNotEmpty
            ? _passphrase.text
            : null,
        remotePath: _remotePath.text.trim().isEmpty ? '.' : _remotePath.text.trim(),
      );
      await SecureStore.instance.saveProfile(profile);
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit server' : 'Add server')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'My Ubuntu PC'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _host,
                    decoration: const InputDecoration(
                      labelText: 'Host / IP',
                      hintText: '192.168.1.20',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _port,
                    decoration: const InputDecoration(labelText: 'Port'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _username,
              decoration: const InputDecoration(labelText: 'Username'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _remotePath,
              decoration: const InputDecoration(
                labelText: 'Starting remote folder',
                hintText: '/home/you or leave as .',
              ),
            ),
            const SizedBox(height: 20),
            SegmentedButton<AuthMethod>(
              segments: const [
                ButtonSegment(value: AuthMethod.password, label: Text('Password')),
                ButtonSegment(value: AuthMethod.privateKey, label: Text('Private key')),
              ],
              selected: {_authMethod},
              onSelectionChanged: (s) => setState(() => _authMethod = s.first),
            ),
            const SizedBox(height: 16),
            if (_authMethod == AuthMethod.password)
              TextFormField(
                controller: _password,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              )
            else ...[
              TextFormField(
                controller: _privateKey,
                maxLines: 6,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Private key (PEM)',
                  hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickKeyFile,
                icon: const Icon(Icons.upload_file),
                label: const Text('Import key file'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passphrase,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Key passphrase (optional)',
                ),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
