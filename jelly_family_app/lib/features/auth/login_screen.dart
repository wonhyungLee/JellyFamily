import 'package:flutter/material.dart';
import 'package:jelly_family_app/features/auth/user_options.dart';
import 'package:jelly_family_app/shared/widgets/jelly_background.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  UserOption? _selected = userOptions.first;
  final _emailController = TextEditingController();
  final _pinController = TextEditingController();
  final _pinFocus = FocusNode();
  bool _loading = false;
  bool _obscurePin = true;

  @override
  void initState() {
    super.initState();
    _emailController.text = _selected?.email ?? '';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _pinController.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final pin = _pinController.text.trim();
    if (email.isEmpty || pin.isEmpty) {
      _showSnack('이메일과 PIN을 입력하세요');
      return;
    }

    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: pin,
      );
    } on AuthException catch (error) {
      _showSnack('로그인 실패: ${error.message}');
    } catch (error) {
      _showSnack('로그인 실패: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: JellyBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          'assets/images/app_icon.png',
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '젤리패밀리',
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                            Text(
                              '우리 가족 용돈 챌린지',
                              style: textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '로그인',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<UserOption>(
                            initialValue: _selected,
                            decoration: const InputDecoration(
                              labelText: '이름',
                            ),
                            items: userOptions
                                .map(
                                  (u) => DropdownMenuItem(
                                    value: u,
                                    child: Text(u.name),
                                  ),
                                )
                                .toList(),
                            onChanged: _loading
                                ? null
                                : (value) {
                                    setState(() {
                                      _selected = value;
                                      _emailController.text =
                                          value?.email ?? '';
                                    });
                                    _pinFocus.requestFocus();
                                  },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _emailController,
                            enabled: !_loading,
                            decoration: const InputDecoration(
                              labelText: '이메일',
                            ),
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) => _pinFocus.requestFocus(),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _pinController,
                            focusNode: _pinFocus,
                            enabled: !_loading,
                            decoration: InputDecoration(
                              labelText: 'PIN',
                              suffixIcon: IconButton(
                                onPressed: _loading
                                    ? null
                                    : () => setState(
                                          () => _obscurePin = !_obscurePin,
                                        ),
                                icon: Icon(
                                  _obscurePin
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                tooltip: _obscurePin ? 'PIN 보기' : 'PIN 숨기기',
                              ),
                            ),
                            obscureText: _obscurePin,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _loading ? null : _signIn(),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _loading ? null : _signIn,
                            child: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('로그인'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '팁: 드롭다운은 편의를 위한 선택이며, 이메일은 직접 수정할 수 있어요.',
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
