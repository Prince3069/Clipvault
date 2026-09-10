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

module.exports = {verifyAndConsumePurchase, PACKAGE_NAME};