// lib/playVerify.js
//
// Verifies a consumable purchase (a credit pack) directly with Google Play
// server-to-server, before crediting anything. This is what stops someone
// from just calling /redeemCreditPurchase with a made-up token and getting
// free credits — Play itself has to confirm the purchase is real first.
//
// SETUP REQUIRED (see functions_deployment_guide.md): the Cloud Function's
// own runtime service account needs to be linked in Play Console with
// permission to manage orders. Without that link, every call here fails
// with a permissions error — that's expected until you do the linking step.

const {google} = require("googleapis");

// Update this if your applicationId ever changes.
const PACKAGE_NAME = "com.princedevlabs.all_social_downloader";

async function getAndroidPublisher() {
  const auth = new google.auth.GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  const authClient = await auth.getClient();
  return google.androidpublisher({version: "v3", auth: authClient});
}

/**
 * Confirms the purchase is real and in the "purchased" state, then consumes
 * it server-side (marks it as used in Play's records, so the same token can
 * never be redeemed again and Play won't auto-refund it as "unacknowledged").
 *
 * @returns {Promise<{valid: boolean, reason?: string}>}
 */
async function verifyAndConsumePurchase(productId, purchaseToken) {
  const publisher = await getAndroidPublisher();

  let purchase;
  try {
    purchase = await publisher.purchases.products.get({
      packageName: PACKAGE_NAME,
      productId,
      token: purchaseToken,
    });
  } catch (e) {
    return {valid: false, reason: `Play verification request failed: ${e.message}`};
  }

  // purchaseState: 0 = purchased, 1 = canceled, 2 = pending.
  const purchaseState = purchase.data.purchaseState;
  if (purchaseState !== 0) {
    return {valid: false, reason: `purchaseState=${purchaseState}`};
  }

  try {
    await publisher.purchases.products.consume({
      packageName: PACKAGE_NAME,
      productId,
      token: purchaseToken,
    });
  } catch (e) {
    // "Already consumed" is fine — our own Firestore idempotency check in
    // index.js is what actually prevents double-crediting, this consume
    // call is a second, independent safety net at the Play level.
    if (!String(e.message || "").includes("consumed")) {
      return {valid: false, reason: `Consume failed: ${e.message}`};
    }
  }

  return {valid: true};
}

/**
 * Confirms a SUBSCRIPTION purchase is real and active, returning Google's
 * own record of its expiry time — never the client's. This is the missing
 * half of "payments happen on the backend": /redeemCreditPurchase already
 * verified consumable purchases this way, but subscription purchases had
 * NO server verification at all — the client just wrote premiumExpiry
 * straight to Firestore based on its own local purchase callback. Anyone
 * running a modified client (or just a Frida/Xposed hook faking a
 * successful PurchaseDetails object) could grant themselves premium
 * forever without paying a cent, because nothing ever checked with Google.
 *
 * subscriptionState values that count as genuinely active:
 * SUBSCRIPTION_STATE_ACTIVE, SUBSCRIPTION_STATE_IN_GRACE_PERIOD.
 *
 * @returns {Promise<{valid: boolean, reason?: string, expiryTime?: Date}>}
 */
async function verifySubscriptionPurchase(productId, purchaseToken) {
  const publisher = await getAndroidPublisher();

  let sub;
  try {
    sub = await publisher.purchases.subscriptionsv2.get({
      packageName: PACKAGE_NAME,
      token: purchaseToken,
    });
  } catch (e) {
    return {valid: false, reason: `Play verification request failed: ${e.message}`};
  }

  const data = sub.data;
  const state = data.subscriptionState;
  const validStates = ["SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"];
  if (!validStates.includes(state)) {
    return {valid: false, reason: `subscriptionState=${state}`};
  }

  // Confirm the line item actually matches the product this user claims
  // to have bought — otherwise someone could send a real token for a
  // cheaper product while claiming to have bought a pricier one.
  const lineItem = (data.lineItems || []).find(
    (item) => item.productId === productId,
  );
  if (!lineItem) {
    return {valid: false, reason: "productId does not match this purchase token"};
  }

  const expiryTime = lineItem.expiryTime ? new Date(lineItem.expiryTime) : null;
  if (!expiryTime || expiryTime.getTime() <= Date.now()) {
    return {valid: false, reason: "Subscription has already expired"};
  }

  try {
    await publisher.purchases.subscriptionsv2.acknowledge({
      packageName: PACKAGE_NAME,
      token: purchaseToken,
    });
  } catch (e) {
    // Already-acknowledged is fine — Firestore idempotency (a stored
    // purchaseToken per user) is the real guard against double-processing,
    // this is a secondary safety net at the Play level, same pattern as
    // the "already consumed" tolerance below for consumables.
    if (!String(e.message || "").toLowerCase().includes("acknowledg")) {
      console.error("Subscription acknowledge failed:", e.message);
    }
  }

  return {valid: true, expiryTime};
}

module.exports = {verifyAndConsumePurchase, verifySubscriptionPurchase, PACKAGE_NAME};