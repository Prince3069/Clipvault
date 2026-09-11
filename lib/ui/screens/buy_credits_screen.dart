// ui/screens/buy_credits_screen.dart
//
// The missing piece: PremiumProvider.buyCreditPack() and the whole
// server-side redemption flow (functions/index.js's /redeemCreditPurchase,
// verified against Google Play before crediting anything) already worked —
// but nothing anywhere let a person actually see the available packs and
// tap one. This is that screen.

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';

import '../../providers/premium_provider.dart';
import '../../services/purchase_service.dart';
import '../themes/app_theme.dart';
import 'premium_screen.dart';

class BuyCreditsScreen extends StatefulWidget {
  const BuyCreditsScreen({Key? key}) : super(key: key);

  @override
  State<BuyCreditsScreen> createState() => _BuyCreditsScreenState();
}

class _BuyCreditsScreenState extends State<BuyCreditsScreen> {
  String? _purchasingId;

  // Local copy for when Play products haven't loaded yet (e.g. flaky
  // connection on first open) — matches functions/lib/budget.js's
  // CREDIT_PACKS exactly. Real prices from Play Store are used whenever
  // they're available; this is only a placeholder while loading.
  static const _fallbackPacks = [
    {'id': PurchaseService.kCredits099Id, 'price': '\$0.99'},
    {'id': PurchaseService.kCredits299Id, 'price': '\$2.99'},
    {'id': PurchaseService.kCredits699Id, 'price': '\$6.99'},
    {'id': PurchaseService.kCredits1499Id, 'price': '\$14.99'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<PremiumProvider>(context, listen: false)
            .refreshCreditBalance();
      }
    });
  }

  Future<void> _buy(String productId) async {
    if (_purchasingId != null) return;
    setState(() => _purchasingId = productId);
    final premium = Provider.of<PremiumProvider>(context, listen: false);
    await premium.buyCreditPack(productId);
    // Purchase result arrives asynchronously via the purchase stream —
    // _purchasingId just drives this screen's own button spinner, and
    // clears once the provider isn't mid-purchase anymore or a message
    // comes back (success or error), whichever happens first.
    if (mounted) setState(() => _purchasingId = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Buy Credits'),
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Consumer<PremiumProvider>(
        builder: (_, premium, __) {
          if (!premium.isPremium) {
            return _buildNeedsProFirst();
          }

          final packs = premium.purchaseService.creditPacks;

          return RefreshIndicator(
            onRefresh: () async {
              await premium.purchaseService.reloadProducts();
              await premium.refreshCreditBalance();
              if (mounted) setState(() {});
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _buildHeader(premium),
                const SizedBox(height: AppSpacing.lg),
                if (premium.errorMessage != null)
                  _buildErrorBanner(premium.errorMessage!),
                if (packs.isEmpty)
                  ..._buildFallbackPacks()
                else
                  ...packs.map(_buildRealPackTile),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'Credits top up your AI allowance for translation and '
                  'Repurpose Studio. They\'re added on top of what your '
                  'plan already includes and never expire when your '
                  'subscription renews.',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.5),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildNeedsProFirst() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                  color: AppColors.primary, size: 40),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Pro first, then credits',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Credits top up a Pro subscriber\'s AI allowance — they '
              'don\'t do anything on their own without an active '
              'subscription. Subscribe to Pro first, then come back here '
              'any time you need more.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(MaterialPageRoute(
                    builder: (_) => const PremiumScreen(),
                  ));
                },
                child: const Text('View Pro plans'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(PremiumProvider premium) {
    final credits = premium.remainingCredits;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.bolt_rounded, color: Colors.white, size: 30),
          const SizedBox(height: AppSpacing.sm),
          Text(
            credits == null ? 'Your AI credits' : '$credits credits left',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Buy more any time your plan\'s allowance runs low.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFallbackPacks() {
    // Play Store products haven't loaded (e.g. this screen opened before
    // the app finished its first product query). Show something sensible
    // rather than a blank screen, but don't let a tap here silently do
    // nothing — try loading products first.
    return [
      const Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(
          'Loading current prices…',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ),
      ..._fallbackPacks.map((pack) => _packTile(
            id: pack['id']!,
            title: _labelFor(pack['id']!),
            price: pack['price']!,
            onTap: () async {
              final premium =
                  Provider.of<PremiumProvider>(context, listen: false);
              await premium.purchaseService.reloadProducts();
              if (mounted) setState(() {});
            },
          )),
    ];
  }

  Widget _buildRealPackTile(ProductDetails product) {
    return _packTile(
      id: product.id,
      title: _labelFor(product.id),
      price: product.price,
      onTap: () => _buy(product.id),
    );
  }

  String _labelFor(String productId) {
    switch (productId) {
      case PurchaseService.kCredits099Id:
        return 'Small top-up';
      case PurchaseService.kCredits299Id:
        return 'Medium top-up';
      case PurchaseService.kCredits699Id:
        return 'Large top-up';
      case PurchaseService.kCredits1499Id:
        return 'Biggest top-up';
      default:
        return 'Credit pack';
    }
  }

  Widget _packTile({
    required String id,
    required String title,
    required String price,
    required VoidCallback onTap,
  }) {
    final isBusy = _purchasingId == id;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: ListTile(
        onTap: isBusy ? null : onTap,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.bolt_rounded, color: AppColors.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: isBusy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                price,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  fontSize: 15,
                ),
              ),
      ),
    );
  }
}
