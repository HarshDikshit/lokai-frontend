import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_theme.dart';
import '../../core/localization.dart';

class LandingScreen extends ConsumerWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo + brand
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.account_balance, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LokAI',
                        style: TextStyle(
                          fontSize: 32, fontWeight: FontWeight.w800,
                          color: Colors.white, letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'Local Leadership Intelligence',
                        style: TextStyle(
                          fontSize: 12, color: Colors.white.withOpacity(0.75),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {
                      final currentLocale = ref.read(localeProvider);
                      ref.read(localeProvider.notifier).setLocale(currentLocale.languageCode == 'en' 
                              ? const Locale('hi') 
                              : const Locale('en'));
                    },
                    icon: const Icon(Icons.language, color: Colors.white),
                  ),
                ],
              ),

              const SizedBox(height: 60),

              // Hero illustration area
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.location_city_rounded,
                        size: 80,
                        color: Colors.white.withOpacity(0.15),
                      ),
                      const SizedBox(height: 40),
                      Text(
                        context.translate('hero_title'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 30, fontWeight: FontWeight.w700,
                          color: Colors.white, height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        context.translate('hero_subtitle'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15, color: Colors.white.withOpacity(0.75),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Feature chips
              Wrap(
                spacing: 10, runSpacing: 8, 
                children: [
                  _featureChip(Icons.report_problem_outlined, context.translate('feature_report')),
                  _featureChip(Icons.track_changes, context.translate('feature_track')),
                  _featureChip(Icons.verified_outlined, context.translate('feature_verify')),
                  _featureChip(Icons.analytics_outlined, context.translate('feature_ai')),
                ],
              ),

              const SizedBox(height: 40),

              // CTA buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go('/login'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    context.translate('get_started'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => context.go('/register'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    context.translate('new_here_create'),
                    style: TextStyle(
                      fontSize: 15, color: Colors.white.withOpacity(0.85),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featureChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
