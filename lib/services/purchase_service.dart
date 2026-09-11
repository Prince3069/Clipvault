// services/purchase_service.dart — Dart 2.17+ compatible
// enablePendingPurchases() removed — deprecated in newer in_app_purchase_android
// ignore_for_file: avoid_print

import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';

enum PurchasePlan { monthly, annual }

class PurchaseService {
  static const String kMonthlyId = 'saveit_premium_monthly';
  static const String kAnnualId = 'saveit_premium_annual';

  // Consumable credit packs — IDs must match functions/lib/budget.js's
  // CREDIT_PACKS exactly, and must be created in Play Console as
  // "In-app products" (consumable), NOT subscriptions.
  static const String kCredits099Id = 'MediaNest_credits_099';
  static const String kCredits299Id = 'MediaNest_credits_299';
  static const String kCredits699Id = 'MediaNest_credits_699';
  static const String kCredits1499Id = 'MediaNest_credits_1499';
  static const Set<String> creditPackIds = {
    kCredits099Id,
    kCredits299Id,
    kCredits699Id,
    kCredits1499Id,
  };

  static const Set<String> _productIds = {
    kMonthlyId,
    kAnnualId,
    kCredits099Id,
    kCredits299Id,
    kCredits699Id,
    kCredits1499Id,
  };

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  List<ProductDetails> _products = [];
  bool _available = false;
  bool _loaded = false;

  List<ProductDetails> get products => List.unmodifiable(_products);
  bool get isAvailable => _available;

  ProductDetails? get monthly => _find(kMonthlyId);
  ProductDetails? get annual => _find(kAnnualId);
  ProductDetails? creditPack(String id) => _find(id);
  List<ProductDetails> get creditPacks =>
      _products.where((p) => creditPackIds.contains(p.id)).toList();

  ProductDetails? _find(String id) {
    try {
      return _products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> initialize({
    required void Function(PurchaseDetails) onPurchaseUpdate,
    required void Function(String) onError,
  }) async {
    // Guard against being called more than once (e.g. if a screen's "Retry"
    // button ever calls this again) — re-subscribing without cancelling the
    // previous subscription would process every future purchase update
    // twice, which would call onPurchaseUpdate (and grantPremium) twice.
    await _sub?.cancel();
    _sub = null;

    _available = await _iap.isAvailable();
    if (!_available) {
      onError('Google Play Billing not available on this device.');
      return;
    }

    // Listen to purchase stream
    // NOTE: enablePendingPurchases() was removed from newer versions of
    // in_app_purchase_android — pending purchases are now enabled by default.
    _sub = _iap.purchaseStream.listen(
      (purchases) async {
        for (final purchase in purchases) {
          print('Purchase: ${purchase.productID} → ${purchase.status}');
          onPurchaseUpdate(purchase);
          // Acknowledge every purchase immediately — Google auto-refunds after 3 days
          if (purchase.pendingCompletePurchase) {
            try {
              await _iap.completePurchase(purchase);
            } catch (e) {
              print('completePurchase error: $e');
            }
          }
        }
      },
      onError: (e) => onError('Purchase stream error: $e'),
    );

    await _loadProducts();
  }

  /// Force a fresh product query — for a "Retry" button after products
  /// failed to load the first time (e.g. right after Play Console products
  /// go active, or a flaky connection on first launch).
  Future<void> reloadProducts() async {
    _loaded = false;
    await _loadProducts();
  }

  Future<void> _loadProducts() async {
    if (_loaded) return;
    try {
      final response = await _iap.queryProductDetails(_productIds);
      if (response.error != null) {
        print('Product load error: ${response.error}');
        return;
      }
      _products = response.productDetails;
      _loaded = true;
      print('Products loaded: ${_products.map((p) => p.id).join(', ')}');
    } catch (e) {
      print('queryProductDetails error: $e');
    }
  }

  Future<void> buyPlan(PurchasePlan plan) async {
    if (!_available) throw 'Google Play Billing not available';
    if (!_loaded) await _loadProducts();

    final String productId = plan == PurchasePlan.monthly
        ? kMonthlyId
        : kAnnualId;

    final product = _find(productId);
    if (product == null)
      throw 'Product "$productId" not found. Check Play Console.';

    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Buys a consumable credit-pack top-up. autoConsume is deliberately
  /// false: consumption happens server-side, only after our backend
  /// verifies the purchase with Google Play and credits the person's
  /// balance (functions/index.js:/redeemCreditPurchase). If the client
  /// auto-consumed immediately, a purchase could be marked "used" by Play
  /// before our backend ever confirmed it and credited anything — the
  /// person would have paid and gotten nothing.
  Future<void> buyCreditPack(String productId) async {
    if (!_available) throw 'Google Play Billing not available';
    if (!creditPackIds.contains(productId)) {
      throw 'Unknown credit pack "$productId"';
    }
    if (!_loaded) await _loadProducts();

    final product = _find(productId);
    if (product == null) {
      throw 'Product "$productId" not found. Check Play Console.';
    }

    final param = PurchaseParam(productDetails: product);
    await _iap.buyConsumable(purchaseParam: param, autoConsume: false);
  }

  Future<void> restorePurchases() async {
    if (!_available) return;
    await _iap.restorePurchases();
  }

  void dispose() => _sub?.cancel();

  static PurchasePlan? planFromProductId(String productId) {
    if (productId == kMonthlyId) return PurchasePlan.monthly;
    if (productId == kAnnualId) return PurchasePlan.annual;
    return null;
  }

  static Duration planDuration(PurchasePlan plan) {
    if (plan == PurchasePlan.monthly) return const Duration(days: 31);
    return const Duration(days: 366);
  }
}
