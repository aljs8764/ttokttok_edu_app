import 'package:flutter/material.dart';

import 'events_tab.dart';
import 'notices_tab.dart';
import 'teacher_home_screen.dart';

/// 교사앱 하단 탭 — 출결(반 목록) · 알림장 · 행사. 탭은 처음 열 때 만든다 (시작할 때 불필요한 조회를 줄이려고).
class TeacherShell extends StatefulWidget {
  const TeacherShell({super.key});

  @override
  State<TeacherShell> createState() => _TeacherShellState();
}

class _TeacherShellState extends State<TeacherShell> {
  int _index = 0;
  final _visited = <int>{0};

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
