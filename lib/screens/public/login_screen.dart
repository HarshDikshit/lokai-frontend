import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../core/localization.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey  = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref.read(authProvider.notifier).login(
      _emailCtrl.text.trim(),
      _passCtrl.text,
    );

    if (!mounted) return;

    // Only navigate on success — on failure the error is shown inline
    if (success) {
      final role = ref.read(authProvider).role;
      switch (role) {
        case 'leader':           context.go('/leader');    break;
        case 'higher_authority': context.go('/authority'); break;
        default:                 context.go('/citizen');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: AppColors.primary),
                    onPressed: () => context.go('/'),
                    padding: EdgeInsets.zero,
                  ),
                  IconButton(
                    onPressed: () {
                      final currentLocale = ref.read(localeProvider);
                      ref.read(localeProvider.notifier).setLocale(currentLocale.languageCode == 'en' 
                              ? const Locale('hi') 
                              : const Locale('en'));
                    },
                    icon: const Icon(Icons.language, color: AppColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.account_balance, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 24),
              Text(context.translate('welcome_back'), style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 8),
              Text(
                context.translate('sign_in_to_account'),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
              ),
              const SizedBox(height: 40),

              // Form
              Form(
                key: _formKey,
                child: Column(children: [
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    // Clear stale error when user edits
                    onChanged: (_) => ref.read(authProvider.notifier).clearError(),
                    decoration: InputDecoration(
                      labelText: context.translate('email_address'),
                      prefixIcon: const Icon(Icons.email_outlined),
                    ),
                    validator: (v) =>
                        v == null || !v.contains('@') ? context.translate('enter_valid_email') : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    onChanged: (_) => ref.read(authProvider.notifier).clearError(),
                    decoration: InputDecoration(
                      labelText: context.translate('password'),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.length < 6 ? context.translate('min_6_char') : null,
                  ),

                  // Inline error
                  if (auth.error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(auth.error!,
                            style: const TextStyle(
                                color: AppColors.error, fontSize: 13))),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: auth.isLoading ? null : _login,
                      child: auth.isLoading
                          ? const SizedBox(height: 20, width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(context.translate('sign_in')),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(context.translate('dont_have_account'),
                        style: const TextStyle(color: AppColors.textSecondary)),
                    GestureDetector(
                      onTap: () => context.go('/register'),
                      child: Text(context.translate('register'),
                          style: const TextStyle(color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
