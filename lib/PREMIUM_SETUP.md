# ClipVault Pro — Setup Guide

## 1. Add to pubspec.yaml

```yaml
dependencies:
  in_app_purchase: ^3.1.0
  in_app_purchase_android: ^0.3.0
  local_auth: ^2.2.0
  flutter_secure_storage: ^9.0.0
  crypto: ^3.0.0
  url_launcher: ^6.2.0
```

## 2. Android permissions (android/app/src/main/AndroidManifest.xml)

```xml
<!-- Biometric (vault) -->
<uses-permission android:name="android.permission.USE_BIOMETRIC"/>
<uses-permission android:name="android.permission.USE_FINGERPRINT"/>

<!-- Google Play Billing is added automatically -->
```

## 3. Google Play Console — Create Products

### Subscriptions
| Product ID               | Price   | Billing Period | Free Trial |
|--------------------------|---------|----------------|------------|
| saveit_premium_monthly   | Play localized price | Monthly | Configure in Play Console |
| saveit_premium_annual    | Play localized price | Yearly  | Configure in Play Console |

## 4. Pricing notes
- Keep monthly and annual offers only; do not create or advertise a one-time Lifetime product.
- Use localized prices from Google Play product details in the app.
- Google Play handles local currency conversion and billing-period presentation.

## 5. Free tier limits
- 10 downloads per day
- Resets at midnight
- Counter shows in Download tab nav badge

## 6. Premium features
- Unlimited downloads
- HD/1080p+ quality  
- Private Vault (biometric/PIN)
- Batch download
- Auto-backup WhatsApp statuses
- Cloud Vault Pro 3GB synced storage
