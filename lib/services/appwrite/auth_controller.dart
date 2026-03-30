import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'appwrite_providers.dart';

final authControllerProvider =
    AsyncNotifierProvider<AuthController, models.User?>(AuthController.new);

class AuthController extends AsyncNotifier<models.User?> {
  Account get _account => ref.read(appwriteAccountProvider);

  @override
  Future<models.User?> build() async {
    try {
      return await _account.get();
    } on AppwriteException {
      return null;
    }
  }

  Future<void> signUpEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _account.create(
        userId: ID.unique(),
        email: email,
        password: password,
        name: name,
      );
      await _account.createEmailPasswordSession(email: email, password: password);
      return await _account.get();
    });
  }

  Future<void> signInEmail({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _account.createEmailPasswordSession(email: email, password: password);
      return await _account.get();
    });
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        await _account.deleteSessions();
      } on AppwriteException {
        // If already logged out, treat as success.
      }
      return null;
    });
  }
}

