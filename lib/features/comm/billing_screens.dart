import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/providers.dart';
import '../../core/i18n/i18n.dart';

/// Phase 2 ④ 학부모 납부 내역 (PAR-007 API, 청구서 발송 PAY-001 알림의 도착 화면).
/// 앱 결제(PG)는 아직 없다 — 학원에 직접 납부하면 원장님이 확인해 "수납 완료"로 바뀐다.

class ParentInvoice {
  const ParentInvoice({
    required this.id,
    required this.institutionName,
    required this.studentName,
    required this.title,
    required this.amount,
    required this.dueDate,
    required this.status,
    required this.overdueDays,
    this.memo,
    this.paidOn,
  });

  final String id, institutionName, studentName, title, status;
  final int amount, overdueDays;
  final DateTime dueDate;
  final String? memo;
  final DateTime? paidOn;

  factory ParentInvoice.fromJson(Map<String, dynamic> j) => ParentInvoice(
        id: j['id'] as String,
        institutionName: j['institutionName'] as String? ?? '',
        studentName: (j['student'] as Map<String, dynamic>)['name'] as String? ?? '',
        title: j['title'] as String,
        amount: (j['amount'] as num).toInt(),
        dueDate: DateTime.parse(j['dueDate'] as String),
        status: j['status'] as String,
        overdueDays: (j['overdueDays'] as num?)?.toInt() ?? 0,
        memo: j['memo'] as String?,
        paidOn: j['paidOn'] == null ? null : DateTime.parse(j['paidOn'] as String),
      );
}

final myInvoicesProvider = FutureProvider.autoDispose<List<ParentInvoice>>((ref) async {
  final r = await ref.watch(apiClientProvider).dio.get<List<dynamic>>(
        'me/invoices',
        options: Options(extra: {'noInstitution': true}),
        queryParameters: {'limit': 50},
      );
  return r.data!.map((e) => ParentInvoice.fromJson(e as Map<String, dynamic>)).toList();
});

final _won = NumberFormat('#,###', 'ko_KR');
DateFormat get _md => DateFormat(tr('M월 d일'), dateLocale());

class InvoiceListScreen extends ConsumerWidget {
  const InvoiceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myInvoicesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('납부 내역'))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myInvoicesProvider),
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(errorMessage(e), style: const TextStyle(color: AppColors.textSecondary))),
          data: (items) => items.isEmpty
              ? ListView(children: [
                  SizedBox(height: 160),
                  Center(child: Text(tr('받은 청구서가 없습니다'), style: TextStyle(color: AppColors.textSecondary))),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: items.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Text(
                          tr('학원에 직접 납부하시면 원장님이 확인한 뒤 "납부 완료"로 바뀝니다.'),
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                        ),
                      );
                    }
                    final v = items[i - 1];
                    return ListTile(
                      title: Text(tr('{0} · {1}원', [v.title, _won.format(v.amount)])),
                      subtitle: Text(tr('{0} · {1}\n기한 {2}{3}', [v.studentName, v.institutionName, _md.format(v.dueDate), v.memo != null ? '\n${v.memo}' : ''])),
                      isThreeLine: true,
                      trailing: _StatusChip(v),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.v);
  final ParentInvoice v;

  @override
  Widget build(BuildContext context) {
    if (v.status == 'PAID') {
      return Chip(label: Text(v.paidOn != null ? tr('납부 완료 {0}', [_md.format(v.paidOn!)]) : tr('납부 완료')), backgroundColor: AppColors.success.withValues(alpha: 0.12));
    }
    if (v.overdueDays > 0) {
      return Chip(label: Text(tr('연체 {0}일', [v.overdueDays])), backgroundColor: AppColors.error.withValues(alpha: 0.12));
    }
    return Chip(label: Text(tr('미납')), backgroundColor: AppColors.warning.withValues(alpha: 0.15));
  }
}
