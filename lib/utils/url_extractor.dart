// utils/url_extractor.dart
class UrlExtractor {
  static String detectPlatform(String url) {
    url = url.toLowerCase();

    if (url.contains('instagram.com') || url.contains('instagr.am')) {
      return 'instagram';
    } else if (url.contains('facebook.com') ||
        url.contains('fb.com') ||
        url.contains('fb.watch')) {
      return 'facebook';
    } else if (url.contains('tiktok.com')) {
      return 'tiktok';
    } else if (url.contains('twitter.com') || url.contains('t.co')) {
      return 'twitter';
    } else {
      return 'unknown';
    }
  }

  static bool isValidUrl(String url) {
    final RegExp urlRegExp = RegExp(
        r'^(https?:\/\/)?([\da-z\.-]+)\.([a-z\.]{2,6})([\/\w \.-]*)*\/?$');
    return urlRegExp.hasMatch(url);
  }
}
