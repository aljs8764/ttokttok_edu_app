import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'attendance_queue.dart';
import 'events_tab.dart';
import 'notices_tab.dart';
import 'teacher_home_screen.dart';

/// 교사앱 하단 탭 — 출결(반 목록) · 알림장 · 행사. 탭은 처음 열 때 만든다 (시작할 때 불필요한 조회를 줄이려고).
class TeacherShell extends ConsumerStatefulWidget {
  const TeacherShell({super.key});

  @override
  ConsumerState<TeacherShell> createState() => _TeacherShellState();
}

class _TeacherShellState extends ConsumerState<TeacherShell> {
  int _index = 0;
  final _visited = <int>{0};

  @override
  void initState() {
    super.initState();
    // 지난번에 못 보낸 오프라인 큐가 있으면 읽어서 보낸다
    Future.microtask(() => ref.read(attendanceQueueProvider.notifier).start());
  }

  static const _tabs = <Widget>[TeacherHomeScreen(), TeacherNoticesTab(), TeacherEventsTab()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [for (var i = 0; i < _tabs.length; i++) _visited.contains(i) ? _tabs[i] : const SizedBox.shrink()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _index = i;
          _visited.add(i);
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: '출결'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: '알림장'),
          NavigationDestination(icon: Icon(Icons.event_outlined), selectedIcon: Icon(Icons.event), label: '행사'),
        ],
      ),
    );
  }
}
