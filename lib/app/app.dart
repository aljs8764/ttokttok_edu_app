import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/push/push_service.dart';
import 'push_navigation.dart';
import 'router.dart';
import 'theme.dart';

class TtokApp extends ConsumerStatefulWidget {
  const TtokApp({super.key});

  @override
  ConsumerState<TtokApp> createState() => _TtokAppState();
}

class _TtokAppState extends ConsumerState<TtokApp> {
  StreamSubscription<PushPayload>? _taps;

  @override
  void initState() {
    super.initState();
    final push = ref.read(pushServiceProvider);
    _taps = push.taps.listen((p) => openFromPush(ref, p));
    // 알림을 눌러 앱이 새로 켜졌으면 첫 화면이 뜬 뒤 이동
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = push.takePendingTap();
      if (pending != null) openFromPush(ref, pending);
    });
  }

  @override
  void dispose() {
    _taps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flavor = ref.watch(appConfigProvider).flavor;
    return MaterialApp.router(
      title: flavor.title,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
