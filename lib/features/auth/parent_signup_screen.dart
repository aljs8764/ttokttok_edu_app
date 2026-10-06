import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/providers.dart';
import '../parent/models.dart';
import '../parent/parent_repository.dart';
import '../parent/terms_gate.dart';

/// 학부모 가입 — 학원이 등록해 둔 보호자 번호로 가입하면 자녀가 자동으로 연결된다.
/// 휴대폰 인증(SMS)은 아직 없다 (Open Issue 1). 약관: 학부모용(서비스·개인정보·만 14세 미만 법정대리인·마케팅).
final _publicTermsProvider = FutureProvider.autoDispose<List<Terms>>((ref) => fetchPublicParentTerms(ref.watch(apiClientProvider)));

class ParentSignupScreen extends ConsumerStatefulWidget {
  const ParentSignupScreen({super.key});

  @override
  ConsumerState<ParentSignupScreen> createState() => _ParentSignupScreenState();
}

class _ParentSignupScreenState extends ConsumerState<ParentSignupScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _checked = <String>{};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _pw, _pw2]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _digits => _phone.text.replaceAll(RegExp(r'\D'), '');
  bool get _phoneOk => RegExp(r'^01[016789]\d{7,8}$').hasMatch(_digits);
  bool get _pwOk => _pw.text.length >= 8 && _pw.text.contains(RegExp(r'\d')) && _pw.text.contains(RegExp(r'[A-Za-z]'));

  Future<void> _submit(List<Terms> terms) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signUpParent(
            name: _name.text,
            phone: _digits,
            password: _pw.text,
            termsIds: _checked.toList(),
          );
      // 이동은 router redirect
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final terms = ref.watch(_publicTermsProvider);
    final list = terms.valueOrNull ?? const <Terms>[];
    final requiredOk = list.where((t) => t.required).every((t) => _checked.contains(t.id));
    final allChecked = list.isNotEmpty && list.every((t) => _checked.contains(t.id));
    final valid = _name.text.trim().isNotEmpty && _phoneOk && _pwOk && _pw.text == _pw2.text && requiredOk && terms.hasValue;

    return Scaffold(
      appBar: AppBar(title: const Text('학부모 가입')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('학원에 알려 준 보호자 휴대폰 번호로 가입하면 자녀가 자동으로 연결됩니다.', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          TextField(controller: _name, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: '이름'), maxLength: 50),
          const SizedBox(height: 4),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')), LengthLimitingTextInputFormatter(13)],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '휴대폰 번호 (로그인 아이디)',
              hintText: '010-1234-5678',
              errorText: _phone.text.isNotEmpty && !_phoneOk ? '휴대폰 번호 형식이 아닙니다' : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pw,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '비밀번호',
              helperText: '영문·숫자 포함 8자 이상',
              errorText: _pw.text.isNotEmpty && !_pwOk ? '영문·숫자 포함 8자 이상' : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pw2,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: '비밀번호 확인', errorText: _pw2.text.isNotEmpty && _pw2.text != _pw.text ? '비밀번호가 다릅니다' : null),
          ),
          const SizedBox(height: 20),
          terms.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Column(children: [
              Text('약관을 불러오지 못했습니다: ${errorMessage(e)}', style: const TextStyle(color: AppColors.error)),
              TextButton(onPressed: () => ref.invalidate(_publicTermsProvider), child: const Text('다시 시도')),
            ]),
            data: (list) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: allChecked,
                  title: const Text('전체 동의', style: TextStyle(fontWeight: FontWeight.w700)),
                  onChanged: (v) => setState(() => v == true ? _checked.addAll(list.map((t) => t.id)) : _checked.clear()),
                ),
                const Divider(height: 1),
                for (final t in list)
                  TermsCheckTile(terms: t, checked: _checked.contains(t.id), onChanged: (v) => setState(() => v ? _checked.add(t.id) : _checked.remove(t.id))),
              ],
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: AppColors.error))),
          const SizedBox(height: 24),
          FilledButton(onPressed: valid && !_busy ? () => _submit(list) : null, child: const Text('가입하기')),
        ],
      ),
    );
  }
}
