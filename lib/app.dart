import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pulpitflow/core/theme/app_theme.dart';
import 'package:pulpitflow/core/router/app_router.dart';
import 'package:pulpitflow/shared/state/theme_provider.dart';

class PulpitFlowApp extends ConsumerWidget {
  const PulpitFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final pulpitTheme = ref.watch(themeProvider);
    final colors = PulpitColors.of(pulpitTheme);

    return MaterialApp.router(
      title: 'PulpitFlow',
      debugShowCheckedModeBanner: false,
      theme: colors.toThemeData(),
      routerConfig: router,
    );
  }
}
