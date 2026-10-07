import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// "10월 7일 (수) 14:30"
String formatDateTime(DateTime d) => DateFormat('M월 d일 (E) HH:mm', 'ko_KR').format(d);

/// 날짜 → 시간 순서로 고른다. 취소하면 null.
Future<DateTime?> pickDateTime(BuildContext context, {DateTime? initial, DateTime? first, DateTime? last}) async {
  final now = DateTime.now();
  final firstDate = DateTime((first ?? now).year, (first ?? now).month, (first ?? now).day);
  final lastDate = last ?? now.add(const Duration(days: 365));
  var start = initial ?? first ?? now;
  if (start.isBefore(firstDate)) start = firstDate;
  if (start.isAfter(lastDate)) start = lastDate;

  final d = await showDatePicker(context: context, initialDate: start, firstDate: firstDate, lastDate: lastDate);
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
  if (t == null) return null;
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}

/// 눌러서 날짜·시간을 고르는 입력칸. [onClear] 가 있으면 지우기 버튼이 생긴다 (선택 항목용).
class DateTimeField extends StatelessWidget {
  const DateTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.first,
    this.last,
    this.onClear,
    this.enabled = true,
    this.errorText,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? first;
  final DateTime? last;
  final VoidCallback? onClear;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: !enabled
          ? null
          : () async {
              final picked = await pickDateTime(context, initial: value, first: first, last: last);
              if (picked != null) onChanged(picked);
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          enabled: enabled,
          suffixIcon: value != null && onClear != null && enabled
              ? IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClear)
              : const Icon(Icons.event_outlined),
        ),
        child: Text(value == null ? '선택' : formatDateTime(value!), style: TextStyle(color: value == null ? Colors.black45 : null)),
      ),
    );
  }
}
