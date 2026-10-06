import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/flavor.dart';
import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/providers.dart';

/// AUTH-001 로그인. 교사앱은 이메일, 학부모앱은 휴대폰 번호가 아이디.
/// 앱은 항상 로그인 유지(rememberMe) — 다시 켰을 때 바로 들어간다.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _id = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(sessionStoreProvider).storage.readLastLoginId().then((v) {
      if (v != null && mounted && _id.text.isEmpty) _id.text = v;
    });
  }

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_id.text.trim().isEmpty || _pw.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).login(_id.text, _pw.text);
      // 이동은 router redirect 가 한다
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flavor = ref.watch(appConfigProvider).flavor;
    final expired = ref.watch(authControllerProvider.select((s) => s.expired));
    final teacher = flavor == Flavor.teacher;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: '똑똑'),
                        TextSpan(text: '.', style: TextStyle(color: AppColors.accent)),
                      ]),
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(teacher ? '선생님용' : '학부모용', style: const TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 32),
                    if (expired && _error == null) ...[
                      const _Notice('로그인이 만료되었습니다. 다시 로그인해 주세요.'),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _id,
                      keyboardType: teacher ? TextInputType.emailAddress : TextInputType.phone,
                      autofillHints: [teacher ? AutofillHints.email : AutofillHints.telephoneNumber],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: teacher ? '이메일' : '휴대폰 번호'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pw,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: '비밀번호',
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: AppColors.error)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('로그인'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      teacher ? '계정은 원장님이 초대 메일 또는 임시 비밀번호로 만들어 드립니다.' : '학원에 등록된 보호자 번호로 가입하면 자녀가 자동으로 연결됩니다.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: const TextStyle(color: AppColors.warning)),
      );
}
