import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/social_sdk.dart';
import '../../core/providers.dart';
import '../parent/models.dart';
import '../parent/parent_repository.dart';
import '../parent/terms_gate.dart';
import '../../core/i18n/i18n.dart';

final _termsProvider = FutureProvider.autoDispose<List<Terms>>((ref) => fetchPublicParentTerms(ref.watch(apiClientProvider)));

/// AUTH-006 서버가 켜 둔 소셜 로그인 (앱에 키가 있는 것만)
final socialProvidersProvider = FutureProvider.autoDispose<List<SocialKind>>((ref) async {
  try {
    final r = await ref.watch(apiClientProvider).publicPost('auth/social/providers', const <String, dynamic>{});
    final on = (r['providers'] as List).cast<String>();
    return SocialKind.values.where((k) => on.contains(k.api) && socialConfigured(k)).toList();
  } catch (_) {
    return const [];
  }
});

/// 로그인 화면의 "카카오로 시작 / 네이버로 시작" 버튼
class SocialLoginButtons extends ConsumerStatefulWidget {
  const SocialLoginButtons({super.key, required this.teacher, required this.onOtp, required this.onError});
  final bool teacher;
  final Future<void> Function(String challengeId) onOtp;
  final void Function(String message) onError;

  @override
  ConsumerState<SocialLoginButtons> createState() => _SocialLoginButtonsState();
}

class _SocialLoginButtonsState extends ConsumerState<SocialLoginButtons> {
  bool _busy = false;

  Future<void> _go(SocialKind k) async {
    setState(() => _busy = true);
    try {
      final token = await socialAccessToken(k);
      if (token == null) return;
      final signup = await ref.read(authControllerProvider.notifier).loginSocial(k, token);
      if (signup == null || !mounted) return; // 로그인됨 → router redirect
      if (widget.teacher) {
        widget.onError(tr('{0} 계정이 연결된 선생님 계정이 없습니다. 이메일로 로그인한 뒤 메뉴 > 간편 로그인 연결에서 연결해 주세요.', [k.label]));
      } else {
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SocialSignupScreen(info: signup)));
      }
    } on OtpRequiredException catch (e) {
      await widget.onOtp(e.challengeId);
    } catch (e) {
      widget.onError(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(socialProvidersProvider).valueOrNull ?? const <SocialKind>[];
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: Divider()),
        Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text(tr('간편 로그인'), style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
        Expanded(child: Divider()),
      ]),
      const SizedBox(height: 12),
      for (final k in list) ...[
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: k == SocialKind.kakao ? const Color(0xFFFEE500) : const Color(0xFF03C75A),
            foregroundColor: k == SocialKind.kakao ? const Color(0xD9000000) : Colors.white,
          ),
          onPressed: _busy ? null : () => _go(k),
          child: Text(tr('{0}로 시작', [k.label])),
        ),
        const SizedBox(height: 8),
      ],
    ]);
  }
}

/// 소셜 계정으로 처음 온 학부모 — 이름·휴대폰 확인 + 약관 동의 후 가입
class SocialSignupScreen extends ConsumerStatefulWidget {
  const SocialSignupScreen({super.key, required this.info});
  final SocialSignupInfo info;

  @override
  ConsumerState<SocialSignupScreen> createState() => _SocialSignupScreenState();
}

class _SocialSignupScreenState extends ConsumerState<SocialSignupScreen> {
  late final _name = TextEditingController(text: widget.info.name ?? '');
  late final _phone = TextEditingController(text: widget.info.phone ?? '');
  final _checked = <String>{};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  String get _digits => _phone.text.replaceAll(RegExp(r'\D'), '');
  bool get _phoneOk => RegExp(r'^01[016789]\d{7,8}$').hasMatch(_digits);

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signUpSocial(widget.info.signupToken, _name.text, _digits, _checked.toList());
      // 이동은 router redirect (로그인 화면 위에 띄운 이 화면도 함께 닫힌다)
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final terms = ref.watch(_termsProvider);
    final list = terms.valueOrNull ?? const <Terms>[];
    final requiredOk = list.where((t) => t.required).every((t) => _checked.contains(t.id));
    final valid = _name.text.trim().isNotEmpty && _phoneOk && requiredOk && terms.hasValue;
    return Scaffold(
      appBar: AppBar(title: Text(tr('가입하기'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(tr('학원에 등록된 보호자 휴대폰 번호를 입력하면 자녀가 자동으로 연결됩니다.'), style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        TextField(controller: _name, decoration: InputDecoration(labelText: tr('이름')), onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('휴대폰 번호')), onChanged: (_) => setState(() {})),
        const SizedBox(height: 16),
        ...terms.when(
          loading: () => [const Center(child: CircularProgressIndicator())],
          error: (e, _) => [Text(errorMessage(e), style: const TextStyle(color: AppColors.error))],
          data: (list) => [
            for (final t in list)
              TermsCheckTile(terms: t, checked: _checked.contains(t.id), onChanged: (v) => setState(() => v ? _checked.add(t.id) : _checked.remove(t.id))),
          ],
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: AppColors.error))),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy || !valid ? null : _submit, child: Text(tr('가입 완료'))),
      ]),
    );
  }
}

/// 내 계정에 카카오·네이버 연결 / 해제 (교사·학부모 공통)
class SocialLinkScreen extends ConsumerStatefulWidget {
  const SocialLinkScreen({super.key});

  @override
  ConsumerState<SocialLinkScreen> createState() => _SocialLinkScreenState();
}

class _SocialLinkScreenState extends ConsumerState<SocialLinkScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;

  Options get _me => Options(extra: {'noInstitution': true});

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ref.read(apiClientProvider).dio.get<Map<String, dynamic>>('me/social', options: _me);
      if (mounted) setState(() => _data = r.data);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _link(SocialKind k) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await socialAccessToken(k);
      if (token == null) return;
      await ref.read(apiClientProvider).dio.put<List<dynamic>>('me/social/${k.api}', data: {'accessToken': token}, options: _me);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlink(SocialKind k) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).dio.delete<List<dynamic>>('me/social/${k.api}', options: _me);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final enabled = ((d?['providers'] as List?) ?? const []).cast<String>();
    final links = ((d?['links'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final kinds = SocialKind.values.where((k) => enabled.contains(k.api) && socialConfigured(k)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(tr('간편 로그인 연결'))),
      body: d == null && _error == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(tr('연결해 두면 다음부터 비밀번호 없이 카카오·네이버로 로그인할 수 있습니다.'), style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: AppColors.error))),
              if (kinds.isEmpty) Text(tr('지금은 사용할 수 있는 간편 로그인이 없습니다.')),
              for (final k in kinds)
                Builder(builder: (_) {
                  final link = links.where((l) => l['provider'] == k.api).firstOrNull;
                  return Card(
                    child: ListTile(
                      title: Text(k.label),
                      subtitle: Text(link == null ? tr('연결 안 됨') : tr('연결됨{0}', [link['email'] != null ? ' · ${link['email']}' : ''])),
                      trailing: link == null
                          ? FilledButton(onPressed: _busy ? null : () => _link(k), child: Text(tr('연결')))
                          : TextButton(onPressed: _busy ? null : () => _unlink(k), child: Text(tr('해제'))),
                    ),
                  );
                }),
            ]),
    );
  }
}

/// AUTH-007 로그인 2단계 — 인증 앱 6자리 또는 복구 코드
Future<void> showOtpDialog(BuildContext context, WidgetRef ref, String challengeId) async {
  final ctrl = TextEditingController();
  String? error;
  var busy = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(tr('2단계 인증')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('인증 앱에 표시된 6자리 숫자를 입력하세요. 휴대폰을 바꿨다면 복구 코드를 입력할 수 있습니다.'), style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(labelText: tr('인증 코드'))),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
        ]),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(c), child: Text(tr('취소'))),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    set(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await ref.read(authControllerProvider.notifier).loginOtp(challengeId, ctrl.text.trim());
                      if (c.mounted) Navigator.pop(c);
                    } catch (e) {
                      final msg = errorMessage(e);
                      if (msg.contains(tr('처음부터')) && c.mounted) {
                        Navigator.pop(c);
                        return;
                      }
                      set(() {
                        busy = false;
                        error = msg;
                      });
                    }
                  },
            child: Text(tr('확인')),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
}
