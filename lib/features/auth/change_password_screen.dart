import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/i18n/i18n.dart';

/// AUTH-005 비밀번호 변경. 임시 비밀번호로 로그인하면 강제(forced)로 이 화면부터.
/// 바꾸면 백엔드가 모든 세션을 끊으므로 새 비밀번호로 다시 로그인한다.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key, required this.forced});

  final bool forced;

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _strong => _next.text.length >= 8 && _next.text.contains(RegExp(r'\d')) && _next.text.contains(RegExp(r'[A-Za-z]'));

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).changePassword(_current.text, _next.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('비밀번호를 바꿨습니다. 새 비밀번호로 로그인하세요.'))));
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = _current.text.isNotEmpty && _strong && _next.text == _confirm.text;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('비밀번호 변경')),
        automaticallyImplyLeading: !widget.forced,
        actions: [
          if (widget.forced) TextButton(onPressed: () => ref.read(authControllerProvider.notifier).logout(), child: Text(tr('로그아웃'))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.forced)
            Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(tr('임시 비밀번호로 로그인했습니다. 계속하려면 새 비밀번호를 정해 주세요.'), style: TextStyle(color: AppColors.textSecondary)),
            ),
          TextField(controller: _current, obscureText: true, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: widget.forced ? tr('임시 비밀번호') : tr('현재 비밀번호'))),
          const SizedBox(height: 12),
          TextField(
            controller: _next,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: tr('새 비밀번호'),
              helperText: tr('영문·숫자 포함 8자 이상'),
              errorText: _next.text.isNotEmpty && !_strong ? tr('영문·숫자 포함 8자 이상') : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: tr('새 비밀번호 확인'),
              errorText: _confirm.text.isNotEmpty && _confirm.text != _next.text ? tr('비밀번호가 다릅니다') : null,
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: AppColors.error))),
          const SizedBox(height: 24),
          FilledButton(onPressed: valid && !_busy ? _submit : null, child: Text(tr('변경'))),
        ],
      ),
    );
  }
}
