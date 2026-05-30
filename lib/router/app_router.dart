import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/home/home_screen.dart';
import '../screens/person/person_edit_screen.dart';
import '../screens/person/person_list_screen.dart';
import '../screens/record/record_edit_screen.dart';
import '../screens/record/record_detail_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/reminder/reminder_list_screen.dart';
import '../screens/reminder/reminder_edit_screen.dart';
import '../screens/weight/weight_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/annual_review/annual_review_screen.dart';
import '../screens/shell/main_shell_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShellScreen(navigationShell: navigationShell),
        branches: [
          // Home - Timeline
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          // Search
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => const SearchScreen(),
              ),
            ],
          ),
          // Reminders
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reminders',
                builder: (context, state) => const ReminderListScreen(),
              ),
            ],
          ),
          // Settings
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      // Persons (standalone with nested edit)
      GoRoute(
        path: '/persons',
        builder: (context, state) => const PersonListScreen(),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) {
              final id = state.uri.queryParameters['id'];
              return PersonEditScreen(personId: id);
            },
          ),
        ],
      ),
      // Record add/edit (standalone - full screen)
      GoRoute(
        path: '/record/edit',
        builder: (context, state) {
          final recordId = state.uri.queryParameters['recordId'];
          final personId = state.uri.queryParameters['personId'];
          return RecordEditScreen(recordId: recordId, personId: personId);
        },
      ),
      // Record detail (standalone - full screen)
      GoRoute(
        path: '/record/detail',
        builder: (context, state) {
          final recordId = state.uri.queryParameters['id']!;
          return RecordDetailScreen(recordId: recordId);
        },
      ),
      // Weight screen (standalone)
      GoRoute(
        path: '/weight',
        builder: (context, state) {
          final personId = state.uri.queryParameters['personId']!;
          return WeightScreen(personId: personId);
        },
      ),
      // Reminder edit (standalone)
      GoRoute(
        path: '/reminder/edit',
        builder: (context, state) {
          final reminderId = state.uri.queryParameters['reminderId'];
          final personId = state.uri.queryParameters['personId'];
          final recordId = state.uri.queryParameters['recordId'];
          return ReminderEditScreen(
            reminderId: reminderId,
            personId: personId,
            recordId: recordId,
          );
        },
      ),
      // Annual review (standalone)
      GoRoute(
        path: '/annual-review',
        builder: (context, state) => const AnnualReviewScreen(),
      ),
    ],
  );
}
