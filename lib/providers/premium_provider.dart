// providers/premium_provider.dart — Dart 2.17+ compatible
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/purchase_service.dart';

class PremiumProvider extends ChangeNotifier {
  static const int kFreeDailyLimit = 10;

  // Must match the deployed Cloud Function URL — see ai_service.dart's
  // _baseUrl, which points at the same backend.
  static const String _functionsBaseUrl =
      'https://us-central1-social-downloader-2d02b.cloudfunctions.net/apiV1';

  static const _kIsPremium = 'premium_active';
  static const _kPlanId = 'premium_plan_id';
  static const _kExpiry = 'premium_expiry';
  static const _kDlCount = 'downloads_today_count';
  static const _kDlDate = 'downloads_today_date';
  static const _kTrialUsed = 'trial_used';
  static const _kPurchaseToken = 'purchase_token';

  bool _isPremium = false;
  PurchasePlan? _plan;
  DateTime? _expiry;
  int _downloadsToday = 0;
  bool _trialUsed = false;
  bool _isLoading = false;
  String? _errorMessage;
  bool _purchaseInProgress = false;

  // Credit balance — populated after any AI action or credit-pack purchase.
  // Shown to the person so they can see for themselves it's real and
  // legit, not just a claim on our part.
  int? _remainingCredits;
  String? _lastCreditPurchaseMessage;
  int? _freeTranslationsRemaining;

  final PurchaseService _purchaseService = PurchaseService();

  bool get isPremium => _isPremium;
  bool get isFree => !_isPremium;
  PurchasePlan? get plan => _plan;
  DateTime? get expiry => _expiry;
  int get downloadsToday => _downloadsToday;
  int get remainingDownloads =>
      (kFreeDailyLimit - _downloadsToday).clamp(0, kFreeDailyLimit);
  bool get canDownload => _isPremium || _downloadsToday < kFreeDailyLimit;
  bool get trialUsed => _trialUsed;
  bool get isLoading => _isLoading;
  bool get purchaseInProgress => _purchaseInProgress;
  String? get errorMessage => _errorMessage;
  int? get remainingCredits => _remainingCredits;
  int? get freeTranslationsRemaining => _freeTranslationsRemaining;
  String? get lastCreditPurchaseMessage => _lastCreditPurchaseMessage;
  bool get hasProducts => _purchaseService.products.isNotEmpty;
  PurchaseService get purchaseService => _purchaseService;

  // Plan label — if/else instead of switch expression
  String get planLabel {
    if (!_isPremium) return 'Free';
    if (_plan == PurchasePlan.monthly) return 'Monthly';
    if (_plan == PurchasePlan.annual) return 'Annual';
    return 'Premium';
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    await _loadFromPrefs();
    if (_isPremium) {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString(_kPurchaseToken);
      final savedProductId = _plan == PurchasePlan.monthly
          ? PurchaseService.kMonthlyId
          : PurchaseService.kAnnualId;
      if (savedToken != null) {
        try {
          // Idempotent on the server (see /verifySubscriptionPurchase) —
          // safe to call on every app start. This is what keeps the
          // server's Firestore record current without the client ever
          // writing premiumExpiry itself.
          await _verifySubscriptionWithServer(
            productId: savedProductId,
            purchaseToken: savedToken,
          );
        } catch (e) {
          print('Startup entitlement re-verification skipped: $e');
        }
      }
    }
    await _purchaseService.initialize(
      onPurchaseUpdate: _handlePurchaseUpdate,
      onError: (e) {
        _errorMessage = e;
        notifyListeners();
      },
    );
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isPremium = prefs.getBool(_kIsPremium) ?? false;
    _trialUsed = prefs.getBool(_kTrialUsed) ?? false;

    final planStr = prefs.getString(_kPlanId);
    // Parse plan string — if/else instead of switch expression
    if (planStr == 'monthly') {
      _plan = PurchasePlan.monthly;
    } else if (planStr == 'annual') {
      _plan = PurchasePlan.annual;
    } else {
      _plan = null;
    }

    final expiryStr = prefs.getString(_kExpiry);
    if (expiryStr != null) {
      _expiry = DateTime.tryParse(expiryStr);
      if (_expiry != null && DateTime.now().isAfter(_expiry!)) {
        await _revokePremium(prefs);
      }
    }
    _loadDailyCount(prefs);
  }

  void _loadDailyCount(SharedPreferences prefs) {
    final savedDate = prefs.getString(_kDlDate) ?? '';
    final today = _today();
    if (savedDate == today) {
      _downloadsToday = prefs.getInt(_kDlCount) ?? 0;
    } else {
      _downloadsToday = 0;
    }
  }

  String _today() => DateTime.now().toIso8601String().substring(0, 10);

  Future<void> recordDownload() async {
    if (_isPremium) return;
    _downloadsToday++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDlDate, _today());
    await prefs.setInt(_kDlCount, _downloadsToday);
    notifyListeners();
  }

  Future<void> buyPlan(PurchasePlan plan) async {
    _errorMessage = null;
    _purchaseInProgress = true;
    notifyListeners();
    try {
      await _purchaseService.buyPlan(plan);
    } catch (e) {
      _errorMessage = e.toString();
      _purchaseInProgress = false;
      notifyListeners();
    }
  }

  Future<void> restorePurchases() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    await _purchaseService.restorePurchases();
    _isLoading = false;
    notifyListeners();
  }

  /// Re-query Play Store products — used by the premium screen's "Retry"
  /// button when products failed to load (e.g. Play Console products
  /// weren't active yet, or a flaky connection on first launch).
  Future<void> reloadProducts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    await _purchaseService.reloadProducts();
    _isLoading = false;
    notifyListeners();
  }

  void _handlePurchaseUpdate(PurchaseDetails purchase) async {
    _purchaseInProgress = false;

    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      if (PurchaseService.creditPackIds.contains(purchase.productID)) {
        await _redeemCreditPack(purchase);
      } else {
        await _grantPremiumFromPurchase(purchase);
      }
    } else if (purchase.status == PurchaseStatus.error) {
      _errorMessage = purchase.error?.message ?? 'Purchase failed';
      print('Purchase error: ${purchase.error}');
    } else if (purchase.status == PurchaseStatus.canceled) {
      print('Purchase canceled');
    } else if (purchase.status == PurchaseStatus.pending) {
      print('Purchase pending...');
    }

    notifyListeners();
  }

  /// Sends the real Play purchase token to the backend, which verifies it
  /// with Google Play directly before crediting anything — see
  /// functions/index.js:/redeemCreditPurchase. This is the only path that
  /// ever adds to a person's credit balance.
  Future<void> _redeemCreditPack(PurchaseDetails purchase) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) {
        _errorMessage = 'Please sign in to redeem your credit purchase';
        return;
      }

      final response = await http.post(
        Uri.parse('$_functionsBaseUrl/redeemCreditPurchase'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'productId': purchase.productID,
          'purchaseToken': purchase.verificationData.serverVerificationData,
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        final creditsAdded = data['creditsAdded'] as int? ?? 0;
        _lastCreditPurchaseMessage = '✅ $creditsAdded credits added!';
        await refreshCreditBalance();
      } else {
        _errorMessage =
            data['error']?.toString() ?? 'Could not redeem credit purchase';
      }
    } catch (e) {
      _errorMessage = 'Could not redeem credit purchase: $e';
      print('Credit pack redemption error: $e');
    }
    // Whatever the outcome, tell in_app_purchase this purchase is handled —
    // otherwise it stays in the pending queue and re-fires on every app
    // launch. Our backend already did the real consumption via the Play
    // Developer API on success; this just clears the client-side plugin
    // state so it isn't reprocessed.
    try {
      await InAppPurchase.instance.completePurchase(purchase);
    } catch (_) {}
  }

  /// Buys a credit-pack top-up. UI should call this from a "Buy credits"
  /// screen once getAICredits/translateText/processRepurposeAction come
  /// back with canBuyCredits: true (budget exhausted).
  ///
  /// Requires Pro first — credits top up a Pro subscriber's AI allowance,
  /// they don't do anything on their own for a free user (translateText's
  /// free tier doesn't consult the credit/budget system at all). Blocking
  /// this before the purchase even starts means nobody pays for something
  /// that wouldn't actually work for them. The server enforces the same
  /// rule independently in /redeemCreditPurchase — this is the fast,
  /// friendly check, not the only one.
  Future<void> buyCreditPack(String productId) async {
    if (!_isPremium) {
      _errorMessage = 'Credits top up your Pro AI allowance — subscribe to '
          'Pro first, then you can buy credits any time you need more.';
      notifyListeners();
      return;
    }
    _errorMessage = null;
    _purchaseInProgress = true;
    notifyListeners();
    try {
      await _purchaseService.buyCreditPack(productId);
    } catch (e) {
      _errorMessage = e.toString();
      _purchaseInProgress = false;
      notifyListeners();
    }
  }

  /// Pulls the latest credit balance from the backend — call this whenever
  /// a screen wants to show "you have N credits left", not just right
  /// after a purchase or AI action.
  Future<void> refreshCreditBalance() async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) return;
      final response = await http.get(
        Uri.parse('$_functionsBaseUrl/getAICredits'),
        headers: {'Authorization': 'Bearer $idToken'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['isPremium'] == true) {
          _remainingCredits = data['remainingCredits'] as int?;
          _freeTranslationsRemaining = null;
        } else {
          // Free-tier shape has no `remainingCredits` — it's used/limits
          // per feature instead (see index.js's /getAICredits).
          final used = data['used'] as Map<String, dynamic>? ?? {};
          final limits = data['limits'] as Map<String, dynamic>? ?? {};
          final usedThisMonth = used['translateText'] as int? ?? 0;
          final monthlyLimit = limits['translateText'] as int? ?? 1;
          _freeTranslationsRemaining =
              (monthlyLimit - usedThisMonth).clamp(0, monthlyLimit);
          _remainingCredits = null;
        }
        notifyListeners();
      }
    } catch (e) {
      print('refreshCreditBalance error: $e');
    }
  }

  /// Call this with whatever a translateText/processRepurposeAction
  /// response already returned, so the UI updates instantly without a
  /// second network round-trip just to re-fetch the same number.
  void updateCreditsFromResponse(int? remainingCredits) {
    if (remainingCredits == null) return;
    _remainingCredits = remainingCredits;
    notifyListeners();
  }

  Future<void> _grantPremiumFromPurchase(PurchaseDetails purchase) async {
    final plan = PurchaseService.planFromProductId(purchase.productID);
    if (plan == null) return;

    final verified = await _verifySubscriptionWithServer(
      productId: purchase.productID,
      purchaseToken: purchase.verificationData.serverVerificationData,
    );

    if (verified == null) {
      // Server couldn't confirm this with Google Play — do NOT grant
      // premium locally just because the client-side purchase callback
      // fired. That local callback is exactly what a modified client (or
      // a Frida/Xposed hook) could fake to get premium for free; the
      // server's confirmation with Google is the only thing that actually
      // proves a real purchase happened.
      _errorMessage = 'Could not verify this purchase with Google Play. '
          'If you were charged, contact support — your purchase token is saved.';
      notifyListeners();
      return;
    }

    await grantPremium(
      plan: plan,
      expiry: verified.expiryTime,
      purchaseToken: purchase.verificationData.serverVerificationData,
    );
  }

  /// Calls the server's /verifySubscriptionPurchase — the ONLY place that
  /// decides whether a subscription purchase is real, using Google Play's
  /// own record, not the client's. Returns null on any failure.
  Future<_VerifiedSubscription?> _verifySubscriptionWithServer({
    required String productId,
    required String purchaseToken,
  }) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) return null;

      final response = await http.post(
        Uri.parse('$_functionsBaseUrl/verifySubscriptionPurchase'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(
            {'productId': productId, 'purchaseToken': purchaseToken}),
      );

      if (response.statusCode != 200) {
        print('verifySubscriptionPurchase failed: ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final expiryStr = data['expiryTime'] as String?;
      if (expiryStr == null) return null;
      final expiry = DateTime.tryParse(expiryStr);
      if (expiry == null) return null;

      return _VerifiedSubscription(
          expiryTime: expiry, planId: data['planId'] as String?);
    } catch (e) {
      print('verifySubscriptionPurchase error: $e');
      return null;
    }
  }

  Future<void> grantPremium({
    required PurchasePlan plan,
    required DateTime expiry,
    String? purchaseToken,
  }) async {
    _isPremium = true;
    _plan = plan;
    _expiry = expiry;
    _trialUsed = true;
    _errorMessage = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsPremium, true);
    await prefs.setBool(_kTrialUsed, true);

    // Plan string — if/else instead of switch expression
    String planStr;
    if (plan == PurchasePlan.monthly) {
      planStr = 'monthly';
    } else if (plan == PurchasePlan.annual) {
      planStr = 'annual';
    } else {
      planStr = 'annual';
    }
    await prefs.setString(_kPlanId, planStr);
    await prefs.setString(_kExpiry, expiry.toIso8601String());
    if (purchaseToken != null) {
      await prefs.setString(_kPurchaseToken, purchaseToken);
    }

    // Local cache only, for instant UI (offline-friendly "you're Pro" state).
    // The real source of truth every server check reads is Firestore's
    // premiumExpiry field, which only ever gets written by
    // /verifySubscriptionPurchase after Google Play confirms the purchase —
    // this function no longer writes it directly.
    notifyListeners();
    print('✅ Premium granted: $plan until $expiry');
  }

  Future<void> _revokePremium(SharedPreferences prefs) async {
    _isPremium = false;
    _plan = null;
    _expiry = null;
    await prefs.setBool(_kIsPremium, false);
    await prefs.remove(_kPlanId);
    await prefs.remove(_kExpiry);
  }

  @override
  void dispose() {
    _purchaseService.dispose();
    super.dispose();
  }
}

class _VerifiedSubscription {
  final DateTime expiryTime;
  final String? planId;
  _VerifiedSubscription({required this.expiryTime, this.planId});
}
