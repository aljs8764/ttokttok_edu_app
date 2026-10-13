import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import 'merge_banner.dart';
import 'models.dart';
import 'parent_providers.dart';
import '../../core/i18n/i18n.dart';

/// PAR-001 통합 안심 타임라인 — 여러 학원의 등·하원을 시간순 한 줄로. 날짜별로 묶고 최신이 위.
/// 디자인(Main): 현재 상태 다크 카드 → 요약 카드(안 읽은 알림장·응답 기다리는 행사) → 날짜별 타임라인 카드
class TimelineTab extends ConsumerWidget {
  const TimelineTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(childrenProvider);
    final timeline = ref.watch(timelineProvider);

    if (children.valueOrNull?.isEmpty ?? false) {
      return _Empty(
        icon: Icons.link_off,
        text: tr('연결된 자녀가 없습니다.\n학원에 등록된 보호자 번호와 가입한 번호가 같은지 확인하거나,\n학원에서 받은 초대 링크로 자녀 정보를 보내 주세요.'),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(timelineProvider.notifier).refresh(),
      child: timeline.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Empty(icon: Icons.cloud_off, text: errorMessage(e)),
        data: (s) {
          final head = <Widget>[
            const MergeSuggestionBanner(),
            for (final n in _nowCards(s.items)) Padding(padding: const EdgeInsets.only(bottom: 12), child: _NowCard(n)),
            const _SummaryRow(),
          ];
          if (s.items.isEmpty) {
            return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
              ...head,
              const SizedBox(height: 60),
              const Icon(Icons.schedule, size: 48, color: AppColors.muted),
              const SizedBox(height: 12),
              Text(tr('아직 등·하원 기록이 없습니다'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            ]);
          }
          final rows = _withDateHeaders(s.items);
          return NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 300) ref.read(timelineProvider.notifier).loadMore();
              return false;
            },
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              itemCount: head.length + rows.length + 1,
              itemBuilder: (_, idx) {
                if (idx < head.length) return head[idx];
                final i = idx - head.length;
                if (i == rows.length) {
                  return s.loadingMore
                      ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                      : const SizedBox(height: 16);
                }
                final r = rows[i];
                return r is DateTime ? _DateHeader(r) : _TimelineTile(r as _Row);
              },
            ),
          );
        },
      ),
    );
  }

  /// 날짜 머리 + 날짜 안 첫·끝 표시 (흰 카드 하나처럼 보이게 모서리를 둥글린다)
  static List<Object> _withDateHeaders(List<TimelineItem> items) {
    final out = <Object>[];
    DateTime? day;
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final d = DateUtils.dateOnly(it.occurredAt);
      final first = day != d;
      if (first) {
        out.add(d);
        day = d;
      }
      final last = i == items.length - 1 || DateUtils.dateOnly(items[i + 1].occurredAt) != d;
      out.add(_Row(it, first: first, last: last));
    }
    return out;
  }

  /// 오늘 기록이 있는 아이마다 가장 최근 상태 한 장 (전체 보기면 아이 수만큼)
  static List<TimelineItem> _nowCards(List<TimelineItem> items) {
    final today = DateUtils.dateOnly(DateTime.now());
    final seen = <String>{};
    final out = <TimelineItem>[];
    for (final it in items) {
      if (DateUtils.dateOnly(it.occurredAt) != today) break; // 최신이 위
      if (seen.add(it.childId ?? it.studentName)) out.add(it);
    }
    return out;
  }
}

class _Row {
  const _Row(this.item, {required this.first, required this.last});
  final TimelineItem item;
  final bool first;
  final bool last;
}

/// 상태 → (라벨, 칩 배경, 칩 글자) — 색과 라벨을 같이 쓴다
(String, Color, Color) _kind(TimelineItem it) => switch (it.type) {
      'CHECK_IN' => (it.isLate ? tr('등원(지각)') : tr('등원'), AppColors.checkInBg, AppColors.checkInFg),
      'CHECK_OUT' => (tr('하원'), AppColors.checkOutBg, AppColors.checkOutFg),
      _ => switch (it.status) {
          'ABSENT' => (tr('결석'), AppColors.dangerBg, AppColors.dangerFg),
          'IN' => (tr('등원'), AppColors.checkInBg, AppColors.checkInFg),
          'OUT' => (tr('하원'), AppColors.checkOutBg, AppColors.checkOutFg),
          _ => (tr('변경'), AppColors.plannedBg, AppColors.plannedFg),
        },
    };

/// 현재 상태 카드 (Ink 다크) — "서윤이는 지금 / 바른수학 / 15:02 등원 · 수업 중"
class _NowCard extends StatelessWidget {
  const _NowCard(this.item);
  final TimelineItem item;

  @override
  Widget build(BuildContext context) {
    final hm = DateFormat('HH:mm').format(item.occurredAt);
    final out = item.type == 'CHECK_OUT' || item.status == 'OUT';
    final absent = item.status == 'ABSENT';
    final place = out && item.destinationName != null ? item.destinationName! : item.institutionName;
    final status = absent
        ? tr('오늘 결석')
        : out
            ? tr('{0} {1}에서 하원', [hm, item.institutionName])
            : tr('{0} 등원 · 수업 중', [hm]);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(tr('{0}의 지금', [item.studentName]), style: const TextStyle(fontSize: 13, color: AppColors.inkTextSecondary))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.chip)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF5BD39A), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(tr('실시간'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Text(
          out ? tr('{0}(으)로 이동', [place]) : place,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: Colors.white),
        ),
        const SizedBox(height: 4),
        Text(status, style: const TextStyle(fontSize: 15, color: Color(0xFFE3E8F1))),
      ]),
    );
  }
}

/// 안 읽은 알림장 · 응답 기다리는 행사 — 누르면 해당 탭으로
class _SummaryRow extends ConsumerWidget {
  const _SummaryRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNoticeCountProvider);
    final pending = ref.watch(eventsProvider).valueOrNull?.where((e) => e.needsAnswer).length ?? 0;
    Widget card(String label, int n, int tab) => Expanded(
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => ref.read(parentTabProvider.notifier).state = tab,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Text(tr('{0}건', [n]), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: n > 0 ? AppColors.ink : AppColors.muted)),
                ]),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        card(tr('안 읽은 알림장'), unread, 1),
        const SizedBox(width: 10),
        card(tr('응답 기다리는 행사'), pending, 3),
      ]),
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader(this.day);
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final label = day == today
        ? tr('오늘의 안심 타임라인')
        : day == today.subtract(const Duration(days: 1))
            ? tr('어제')
            : DateFormat(tr('M월 d일 (E)'), dateLocale()).format(day);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
        if (day == today) Text(DateFormat(tr('M월 d일 (E)'), dateLocale()).format(day), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ]),
    );
  }
}

/// 시간 | 점·세로선 | 상태칩 + 장소 / 부가 설명
class _TimelineTile extends StatelessWidget {
  const _TimelineTile(this.row);
  final _Row row;

  @override
  Widget build(BuildContext context) {
    final item = row.item;
    final (label, chipBg, chipFg) = _kind(item);
    final sub = switch (item.type) {
      'CHECK_OUT' when item.destinationName != null => tr('다음 목적지: {0}', [item.destinationName]),
      _ => item.headline,
    };
    return Container(
      padding: EdgeInsets.fromLTRB(18, 0, 18, row.last ? 10 : 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: row.last ? const BorderRadius.vertical(bottom: Radius.circular(22)) : null,
      ),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 46,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                DateFormat('HH:mm').format(item.occurredAt),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          ),
          SizedBox(
            width: 14,
            child: Column(children: [
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: chipFg, shape: BoxShape.circle),
              ),
              Expanded(
                child: Container(width: 2, margin: const EdgeInsets.only(top: 4), color: row.last ? Colors.transparent : AppColors.line),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(6)),
                    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: chipFg)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.institutionName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
                const SizedBox(height: 3),
                Text('${item.studentName} · $sub', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ]),
            ),
          ),
        ]),
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
