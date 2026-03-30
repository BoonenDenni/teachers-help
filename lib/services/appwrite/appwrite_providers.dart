import 'package:appwrite/appwrite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_config.dart';

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnv);

final appwriteClientProvider = Provider<Client>((ref) {
  final AppConfig config = ref.watch(appConfigProvider);
  return Client()
      .setEndpoint(config.appwriteEndpoint)
      .setProject(config.appwriteProjectId);
});

final appwriteAccountProvider = Provider<Account>(
  (ref) => Account(ref.watch(appwriteClientProvider)),
);

final appwriteDatabasesProvider = Provider<Databases>(
  (ref) => Databases(ref.watch(appwriteClientProvider)),
);

final appwriteFunctionsProvider = Provider<Functions>(
  (ref) => Functions(ref.watch(appwriteClientProvider)),
);

