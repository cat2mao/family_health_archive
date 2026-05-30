import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers/app_providers.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  runApp(
    const ProviderScope(
      child: _BootstrapApp(),
    ),
  );
}

class _BootstrapApp extends ConsumerWidget {
  const _BootstrapApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(bootstrapProvider);
    return bootstrap.when(
      loading: () => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.favorite,
                  size: 48,
                  color: Colors.teal.shade400,
                ),
                const SizedBox(height: 16),
                const Text('家庭健康档案'),
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
      error: (e, _) => MaterialApp(
        home: Scaffold(
          body: Center(child: Text('启动失败: $e')),
        ),
      ),
      data: (selfId) {
        if (selfId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final current = ref.read(selectedPersonIdProvider);
            if (current == null) {
              ref.read(selectedPersonIdProvider.notifier).state = selfId;
            }
          });
        }
        return FamilyHealthApp();
      },
    );
  }
}
