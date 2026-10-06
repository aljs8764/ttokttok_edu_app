import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import 'student_api.dart';

/// STD-001 기기 연결 — 부모님 앱(더보기 → 학생앱 연결)에서 만든 8자리 코드를 넣는다.
class StudentLinkScreen extends ConsumerStatefulWidget {
  const StudentLinkScreen({super.key});

  @override
  ConsumerState<StudentLinkScreen> createState() => _StudentLinkScreenState();
}

class _StudentLinkScreenState extends ConsumerState<StudentLinkScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String get _normalized => _code.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  Future<void> _submit() async {
    if (_normalized.length != 8 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(studentApiProvider).link(_normalized, '학생 휴대폰');
      ref.read(studentLinkedProvider.notifier).set(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text.rich(
                    const TextSpan(children: [TextSpan(text: '똑똑'), TextSpan(text: '.', style: TextStyle(color: AppColors.accent))]),
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                  const Text('QR 출석', style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 32),
                  const Text('부모님 휴대폰의 똑똑 앱에서\n더보기 → 학생앱 연결 을 누르면 나오는\n8자리 코드를 입력하세요.',
                      style: TextStyle(fontSize: 16, height: 1.5)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _code,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]')), LengthLimitingTextInputFormatter(10)],
                    style: const TextStyle(fontSize: 28, letterSpacing: 6, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(hintText: 'ABCD2345'),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _normalized.length == 8 && !_busy ? _submit : null, child: const Text('연결하기')),
                  const SizedBox(height: 16),
                  const Text('코드는 10분 동안 한 번만 쓸 수 있어요.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
