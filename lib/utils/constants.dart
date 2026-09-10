// utils/constants.dart
// ignore_for_file: constant_identifier_names

class Constants {
  static const String appName = 'Status & Video Downloader';
  static const String defaultDownloadPath =
      '/storage/emulated/0/Download/VideoDownloader';
  // static const String USER_AGENT =
  //     'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';
  // static const String MOBILE_USER_AGENT =
  //     'Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Mobile/15E148 Safari/604.1';
  // // other constants...
  static const String USER_AGENT =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/98.0.4758.102 Safari/537.36';
  static const String MOBILE_USER_AGENT =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 14_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1';
  // WhatsApp paths
  static const String whatsAppStatusPath =
      '/storage/emulated/0/WhatsApp/Media/.Statuses';
  static const String whatsAppBusinessStatusPath =
      '/storage/emulated/0/WhatsApp Business/Media/.Statuses';

  // Alternative WhatsApp paths (Android 11+)
  static const String altWhatsAppStatusPath =
      '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/.Statuses';
  static const String altWhatsAppBusinessStatusPath =
      '/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp Business/Media/.Statuses';

  // Supported social media apps
  static const Map<String, String> socialMediaPackages = {
    'instagram': 'com.instagram.android',
    'facebook': 'com.facebook.katana',
    'tiktok': 'com.zhiliaoapp.musically',
    'twitter': 'com.twitter.android',
  };
}
