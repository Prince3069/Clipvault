// ui/screens/premium_screen.dart
// COMPLETE - Premium Screen wired to the real PremiumProvider/PurchaseService

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';
import '../../providers/premium_provider.dart';
import '../../services/purchase_service.dart';
import '../themes/app_theme.dart';
import 'buy_credits_screen.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({Key? key}) : super(key: key);

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  // Fallback display pricing, used only while the real Play Store price
  // hasn't loaded yet (or briefly on a device with no Play Store). Once
  // PurchaseService has real ProductDetails, the actual Play Store price —
  // already localized and currency-converted by Google — is shown instead,
  // so this table never goes stale or mismatches what Play actually charges.
  final Map<String, dynamic> _plans = {
    'monthly': {
      'id': PurchaseService.kMonthlyId,
      'plan': PurchasePlan.monthly,
      'name': 'Monthly',
      'badge': 'MOST POPULAR',
      'fallbackPrice': '\$3.99',
      'fallbackPricePerMonth': '\$3.99/month',
      'trial': '4-day trial where available · then',
      'color': AppColors.primary,
    },
    'annual': {
      'id': PurchaseService.kAnnualId,
      'plan': PurchasePlan.annual,
      'name': 'Annual',
      'badge': 'BEST VALUE',
      'fallbackPrice': '\$35.99',
      'fallbackPricePerMonth': '\$3.00/month',
      'trial': 'Save 24% vs monthly',
      'color': AppColors.secondary,
    }
  };

  ProductDetails? _productFor(String planKey) {
    final premiumProvider =
        Provider.of<PremiumProvider>(context, listen: false);
    return planKey == 'monthly'
        ? premiumProvider.purchaseService.monthly
        : premiumProvider.purchaseService.annual;
  }

  Future<void> _handlePurchase(PurchasePlan plan) async {
    final premiumProvider =
        Provider.of<PremiumProvider>(context, listen: false);
    await premiumProvider.buyPlan(plan);
    if (!mounted) return;
    final error = premiumProvider.errorMessage;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Purchase failed: $error'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleRestore() async {
    final premiumProvider =
        Provider.of<PremiumProvider>(context, listen: false);
    await premiumProvider.restorePurchases();
    if (!mounted) return;
    final error = premiumProvider.errorMessage;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error != null
            ? 'Restore failed: $error'
            : premiumProvider.isPremium
                ? '✅ Purchases restored'
                : 'No previous purchase found for this account'),
        backgroundColor: error != null ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleRetry() async {
    await Provider.of<PremiumProvider>(context, listen: false).reloadProducts();
  }

  @override
  Widget build(BuildContext context) {
    final premiumProvider = Provider.of<PremiumProvider>(context);
    final showError = !premiumProvider.isLoading &&
        !premiumProvider.hasProducts &&
        !premiumProvider.isPremium;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('MediaNest Pro'),
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: premiumProvider.isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            )
          : showError
              ? _buildErrorState(premiumProvider)
              : _buildContent(premiumProvider),
    );
  }

  Widget _buildErrorState(PremiumProvider premiumProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 64),
            const SizedBox(height: 16),
            Text(
              premiumProvider.errorMessage ??
                  'Could not load subscription plans. Check your connection '
                      'and try again.',
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _handleRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(PremiumProvider premiumProvider) {
    final isPremium = premiumProvider.isPremium;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Hero Header ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppShadows.primary,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    color: Colors.white, size: 32),
                const SizedBox(height: 12),
                const Text(
                  'Try the full creator workspace\nbefore choosing a plan.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '4-DAY FREE TRIAL · CANCEL ANYTIME',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ─── Features List ─────────────────────────────────────────────────
          const Text(
            'Everything included',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'Free, always',
            style: AppTypography.titleMedium.copyWith(color: AppColors.success),
          ),
          const SizedBox(height: 8),
          _buildFeatureItem('Downloads',
              '10 per day, from Instagram, TikTok, Facebook, Vimeo, LinkedIn & more'),
          _buildFeatureItem('WhatsApp Status saver',
              'Save and share statuses — photos and videos'),
          _buildFeatureItem(
              'Private Vault', 'PIN protected, with a decoy PIN option'),
          _buildFeatureItem('Quick Clip Editor basics',
              'Trim, rotate, change speed, extract a frame, extract audio, split'),
          _buildFeatureItem(
              'Translation', '1 free translation a day — text, speech & video'),
          _buildFeatureItem('No ads. Ever.',
              'Not now, not later — that never changes on any plan'),

          const SizedBox(height: 24),

          Text(
            'Pro — unlock the full creator toolkit',
            style: AppTypography.titleMedium.copyWith(color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          _buildFeatureItem('Unlimited downloads', 'No daily cap'),
          _buildFeatureItem('HD & 4K quality', 'Highest available resolution'),
          _buildFeatureItem(
              'Batch download', 'Download multiple videos at once'),
          _buildFeatureItem(
              'Cloud Vault Pro', '3GB synced storage across your devices'),
          _buildFeatureItem(
              'Auto-backup statuses', 'WhatsApp statuses saved automatically'),
          _buildFeatureItem('Repurpose Studio',
              'AI captions, hashtags, subtitles, scripts & more per clip'),
          _buildFeatureItem('Creator Coach',
              'Personalized coaching, daily challenges & content ideas'),
          _buildFeatureItem('Unlimited translation',
              'Text, speech & video — to and from any language'),

          const SizedBox(height: 32),

          // ─── Plans ─────────────────────────────────────────────────────────
          const Text(
            'Choose your plan',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),

          // Annual Plan
          _buildPlanCard(
            plan: _plans['annual']!,
            isPremium: isPremium,
            premiumProvider: premiumProvider,
          ),

          const SizedBox(height: 12),

          // Monthly Plan
          _buildPlanCard(
            plan: _plans['monthly']!,
            isPremium: isPremium,
            premiumProvider: premiumProvider,
          ),

          const SizedBox(height: 24),

          // ─── Footer ───────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Column(
              children: [
                if (!isPremium)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: premiumProvider.purchaseInProgress
                          ? null
                          : () => _handlePurchase(PurchasePlan.monthly),
                      child: premiumProvider.purchaseInProgress
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Start 4-Day Free Trial'),
                    ),
                  ),
                if (isPremium)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const BuyCreditsScreen(),
                          ));
                        },
                        icon: const Icon(Icons.bolt_rounded, size: 18),
                        label: const Text('Buy more AI credits'),
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: premiumProvider.isLoading ? null : _handleRestore,
                  child: const Text('Restore purchases'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Payment processed securely by Google Play.\n'
                  'Prices and currency are localized by Google Play. '
                  'Subscriptions renew automatically; cancel anytime.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () {
                        // Open privacy policy
                      },
                      child: const Text(
                        'Privacy Policy',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Text(' · ',
                        style: TextStyle(color: AppColors.textMuted)),
                    GestureDetector(
                      onTap: () {
                        // Open terms of service
                      },
                      child: const Text(
                        'Terms of Service',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: AppColors.success,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required Map<String, dynamic> plan,
    required bool isPremium,
    required PremiumProvider premiumProvider,
  }) {
    final isSelected = plan['id'] == PurchaseService.kMonthlyId;
    final color = plan['color'] as Color;
    final planKey =
        plan['id'] == PurchaseService.kMonthlyId ? 'monthly' : 'annual';
    final product = _productFor(planKey);

    // Prefer the real, localized price from Google Play. It's already
    // converted to the buyer's currency and matches exactly what they'll be
    // charged — the fallback strings only cover the brief window before
    // products finish loading.
    final displayPrice = product?.price ?? plan['fallbackPrice'] as String;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSelected ? color.withValues(alpha: 0.06) : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? color : AppColors.borderLight,
          width: isSelected ? 2 : 1,
        ),
        boxShadow: isSelected ? AppShadows.soft : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          plan['name'],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            plan['badge'],
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plan['trial'],
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    displayPrice,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (product == null)
                    Text(
                      plan['fallbackPricePerMonth'] as String,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!isPremium)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: premiumProvider.purchaseInProgress
                    ? null
                    : () => _handlePurchase(plan['plan'] as PurchasePlan),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: premiumProvider.purchaseInProgress
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(isSelected ? 'Start Free Trial' : 'Subscribe'),
              ),
            ),
        ],
      ),
    );
  }
}
