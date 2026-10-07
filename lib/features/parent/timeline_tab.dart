import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import 'merge_banner.dart';
import 'models.dart';
import 'parent_providers.dart';

/// PAR-001 통합 안심 타임라인 — 여러 학원의 등·하원을 시간순 한 줄로. 날짜별로 묶고 최신이 위.
class TimelineTab extends ConsumerWidget {
  const TimelineTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(childrenProvider);
    final timeline = ref.watch(timelineProvider);

    if (children.valueOrNull?.isEmpty ?? false) {
      return const _Empty(
        icon: Icons.link_off,
        text: '연결된 자녀가 없습니다.\n학원에 등록된 보호자 번호와 가입한 번호가 같은지 확인하거나,\n학원에서 받은 초대 링크로 자녀 정보를 보내 주세요.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(timelineProvider.notifier).refresh(),
      child: timeline.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Empty(icon: Icons.cloud_off, text: errorMessage(e)),
        data: (s) {
          if (s.items.isEmpty) {
            return ListView(padding: const EdgeInsets.all(16), children: const [
              MergeSuggestionBanner(),
              SizedBox(height: 80),
              Icon(Icons.schedule, size: 48, color: AppColors.muted),
              SizedBox(height: 12),
              Text('아직 등·하원 기록이 없습니다', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
            ]);
          }
          final rows = _withDateHeaders(s.items);
          return NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 300) ref.read(timelineProvider.notifier).loadMore();
              return false;
            },
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: rows.length + 2,
              itemBuilder: (_, idx) {
                // 맨 위: "같은 아이인가요?" (스펙 7-8, 후보가 없으면 빈 칸)
                if (idx == 0) return const MergeSuggestionBanner();
                final i = idx - 1;
                if (i == rows.length) {
                  return s.loadingMore
                      ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                      : const SizedBox(height: 16);
                }
                final r = rows[i];
                return r is DateTime ? _DateHeader(r) : _TimelineTile(r as TimelineItem);
              },
            ),
          );
        },
      ),
    );
  }

  static List<Object> _withDateHeaders(List<TimelineItem> items) {
    final out = <Object>[];
    DateTime? day;
    for (final it in items) {
      final d = DateUtils.dateOnly(it.occurredAt);
      if (day != d) {
        out.add(d);
        day = d;
      }
      out.add(it);
    }
    return out;
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader(this.day);
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final label = day == today
        ? '오늘'
        : day == today.subtract(const Duration(days: 1))
            ? '어제'
            : DateFormat('M월 d일 (E)', 'ko_KR').format(day);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile(this.item);
  final TimelineItem item;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (item.type) {
      'CHECK_IN' => (Icons.login, item.isLate ? AppColors.warning : AppColors.success),
      'CHECK_OUT' => (Icons.logout, AppColors.info),
      _ => (Icons.edit_note, item.status == 'ABSENT' ? AppColors.error : AppColors.muted),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 18, backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.studentName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(item.headline),
                  ],
                ),
              ),
              Text(DateFormat('HH:mm').format(item.occurredAt), style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          const SizedBox(height: 100),
          Icon(icon, size: 48, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, height: 1.5)),
        ],
      );
}
