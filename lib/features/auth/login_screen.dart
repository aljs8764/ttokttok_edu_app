import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/flavor.dart';
import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/providers.dart';
import '../../core/widgets/logo_mark.dart';
import 'social_screens.dart';
import '../../core/i18n/i18n.dart';

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
    } on OtpRequiredException catch (e) {
      if (mounted) await showOtpDialog(context, ref, e.challengeId);
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
    // 디자인: 학부모 = 밝은 Ground 배경, 교사 = 다크(Ink) 배경으로 두 앱을 구분 (P_Login · T_Login)
    final fg = teacher ? Colors.white : AppColors.ink;
    final sub = teacher ? AppColors.inkTextSecondary : AppColors.plannedFg;

    InputDecoration field(String label, {String? hint, Widget? suffix}) => teacher
        ? InputDecoration(
            labelText: label,
            hintText: hint,
            suffixIcon: suffix,
            filled: true,
            fillColor: AppColors.inkField,
            labelStyle: const TextStyle(color: AppColors.inkTextSecondary),
            floatingLabelStyle: const TextStyle(color: AppColors.accent),
            hintStyle: const TextStyle(color: Color(0xFF8C98B0)),
            suffixIconColor: AppColors.inkTextSecondary,
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.field), borderSide: const BorderSide(color: AppColors.inkFieldBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.field), borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
          )
        : InputDecoration(labelText: label, hintText: hint, suffixIcon: suffix);

    return Scaffold(
      backgroundColor: teacher ? AppColors.ink : AppColors.ground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      LogoMark(size: teacher ? 56 : 64),
                      if (teacher) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.chip)),
                          child: Text(tr('선생님용'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 18),
                    Text(
                      teacher ? tr('버튼 한 번으로\n출결과 소통을 끝내요') : tr('아이의 하루,\n똑똑하게 안심하세요'),
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.6, height: 1.3, color: fg),
                    ),
                    if (!teacher) ...[
                      const SizedBox(height: 8),
                      Text(tr('여러 학원의 등·하원 소식을 한 곳에서 받아보세요.'), style: TextStyle(fontSize: 15, height: 1.5, color: sub)),
                    ],
                    const SizedBox(height: 28),
                    if (expired && _error == null) ...[
                      _Notice(tr('로그인이 만료되었습니다. 다시 로그인해 주세요.')),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _id,
                      style: TextStyle(color: fg, fontSize: 16),
                      keyboardType: teacher ? TextInputType.emailAddress : TextInputType.phone,
                      autofillHints: [teacher ? AutofillHints.email : AutofillHints.telephoneNumber],
                      textInputAction: TextInputAction.next,
                      decoration: field(teacher ? tr('이메일') : tr('휴대폰 번호'), hint: teacher ? 'teacher@academy.kr' : '010-0000-0000'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _pw,
                      style: TextStyle(color: fg, fontSize: 16),
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: field(
                        tr('비밀번호'),
                        suffix: IconButton(
                          tooltip: _obscure ? tr('비밀번호 보기') : tr('비밀번호 숨기기'),
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: teacher ? const Color(0xFFFFB4A8) : AppColors.error)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(64, 56),
                        backgroundColor: teacher ? AppColors.accent : AppColors.ink,
                        foregroundColor: teacher ? AppColors.ink : Colors.white,
                        textStyle: const TextStyle(fontFamily: kFontFamily, fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: teacher ? AppColors.ink : Colors.white))
                          : Text(tr('로그인')),
                    ),
                    SocialLoginButtons(
                      teacher: teacher,
                      onOtp: (id) => showOtpDialog(context, ref, id),
                      onError: (m) => setState(() => _error = m),
                    ),
                    const SizedBox(height: 28),
                    if (teacher)
                      Text(
                        tr('계정은 원장님이 보낸 초대 메일로 만들 수 있어요.\n초대를 못 받았다면 소속 기관에 문의해 주세요.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.inkTextSecondary),
                      )
                    else
                      // 처음 가입 안내 카드 (P_Login 하단)
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.cardSmall)),
                        child: Row(children: [
                          const Icon(Icons.chat_bubble_outline, size: 22, color: AppColors.ink),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              tr('학원에 등록된 보호자 번호로 가입하면 자녀가 자동으로 연결돼요'),
                              style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.plannedFg),
                            ),
                          ),
                          TextButton(
                            onPressed: _busy ? null : () => context.push('/signup'),
                            child: Text(tr('가입하기'), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ]),
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
        decoration: BoxDecoration(color: AppColors.noticeBg, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(color: AppColors.noticeFg)),
      );
}
