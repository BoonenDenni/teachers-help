import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/appwrite/auth_controller.dart';

class TeacherLoginScreen extends ConsumerStatefulWidget {
  const TeacherLoginScreen({super.key});

  @override
  ConsumerState<TeacherLoginScreen> createState() => _TeacherLoginScreenState();
}

class _TeacherLoginScreenState extends ConsumerState<TeacherLoginScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _name = TextEditingController();
  bool _isSignUp = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    final name = _name.text.trim();
    if (email.isEmpty || password.isEmpty) return;

    final controller = ref.read(authControllerProvider.notifier);
    if (_isSignUp) {
      await controller.signUpEmail(email: email, password: password, name: name.isEmpty ? 'Leraar' : name);
    } else {
      await controller.signInEmail(email: email, password: password);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Leraar inloggen')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_isSignUp) ...<Widget>[
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Naam',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _email,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Wachtwoord',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: auth.isLoading ? null : _submit,
                  child: Text(_isSignUp ? 'Account aanmaken' : 'Inloggen'),
                ),
                TextButton(
                  onPressed: auth.isLoading
                      ? null
                      : () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(_isSignUp
                      ? 'Heb je al een account? Inloggen'
                      : 'Nieuwe leraar? Account aanmaken'),
                ),
                if (auth.hasError) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    'Fout: ${auth.error}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

