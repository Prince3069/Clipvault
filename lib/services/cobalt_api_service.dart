// services/cobalt_api_service.dart — MediaExtractorService
// COMPLETE VERSION — all platforms, all fixes merged:
//  • Content-type guard in _doDownload (stops saving HTML error pages as .mp4)
//  • Instagram: 7 API methods before browser fallback
//  • Vimeo: direct player config API
//  • Dailymotion: direct metadata API
//  • LinkedIn, Reddit, Pinterest, Twitch, SoundCloud, Tubidy, OK.ru etc → cobalt
//  • Updated isSupportedUrl() + detectPlatform() for all platforms
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

enum ExtractStatus { success, error }

class ExtractResult {
  final ExtractStatus status;
  final String? url;
  final String? filename;
  final List<ExtractItem>? items;
  final String? errorMessage;
  ExtractResult._(
      {required this.status,
      this.url,
      this.filename,
      this.items,
      this.errorMessage});
  factory ExtractResult.success(
          {required String url, String? filename, List<ExtractItem>? items}) =>
      ExtractResult._(
          status: ExtractStatus.success,
          url: url,
          filename: filename,
          items: items);
  factory ExtractResult.error(String msg) =>
      ExtractResult._(status: ExtractStatus.error, errorMessage: msg);
  bool get ok => status == ExtractStatus.success;
  bool get useBrowser => errorMessage == 'USE_BROWSER';
}

class ExtractItem {
  final String url;
  final String type;
  final String? thumb;
  ExtractItem({required this.url, required this.type, this.thumb});
}

enum CobaltStatus { redirect, tunnel, picker, error, rateLimited }

class CobaltMediaResult {
  final CobaltStatus status;
  final String? url;
  final String? filename;
  final List<CobaltPickerItem>? pickerItems;
  final String? errorMessage;
  final String? audioUrl;
  CobaltMediaResult(
      {required this.status,
      this.url,
      this.filename,
      this.pickerItems,
      this.errorMessage,
      this.audioUrl});
  bool get isSuccess =>
      status == CobaltStatus.redirect || status == CobaltStatus.tunnel;
  bool get hasPicker => status == CobaltStatus.picker;
}

class CobaltPickerItem {
  final String type;
  final String url;
  final String? thumb;
  CobaltPickerItem({required this.type, required this.url, this.thumb});
}

class MediaExtractorService {
  static const _ua =
      'Mozilla/5.0 (Linux; Android 13; SM-S918B) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
  static const _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const _cobaltInstances = [
    'https://cobalt.api.onrender.com/',
    'https://cobalt.urdad.org/',
    'https://co.wuk.sh/',
  ];

  // ═══════════════════════════════════════════════════════════════════
  Future<ExtractResult> extract(String url, {bool preferHD = true}) async {
    final lo = url.toLowerCase();
    try {
      if (_isTikTok(lo)) return await _tiktok(url, preferHD: preferHD);
      if (_isInstagram(lo)) return await _instagram(url);
      if (_isFacebook(lo)) return await _facebook(url);
      if (_isTwitter(lo)) return await _twitter(url);
      if (_isVimeo(lo)) return await _vimeo(url);
      if (_isDailymotion(lo)) return await _dailymotion(url);
      // LinkedIn, Reddit, Pinterest, Twitch, SoundCloud, Tubidy,
      // OK.ru, Streamable, Loom, Bilibili, Tumblr — all through cobalt
      return await _cobalt(url);
    } catch (e) {
      print('extract error: $e');
      return ExtractResult.error('USE_BROWSER');
    }
  }

  // ═══ TIKTOK ════════════════════════════════════════════════════════
  Future<ExtractResult> _tiktok(String url, {bool preferHD = true}) async {
    try {
      final r = await _tikwm(url, preferHD: preferHD);
      if (r != null) return r;
    } catch (_) {}
    try {
      final r = await _tiklydown(url);
      if (r != null) return r;
    } catch (_) {}
    try {
      final r = await _ssstik(url);
      if (r != null) return r;
    } catch (_) {}
    final r = await _cobalt(url);
    return r.ok ? r : ExtractResult.error('USE_BROWSER');
  }

  Future<ExtractResult?> _tikwm(String url, {bool preferHD = true}) async {
    final resp = await http
        .post(
          Uri.parse('https://www.tikwm.com/api/'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': _ua,
            'Referer': 'https://www.tikwm.com/',
            'Origin': 'https://www.tikwm.com'
          },
          body: 'url=${Uri.encodeComponent(url)}&hd=1',
        )
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if ((data['code'] as num?)?.toInt() == 0) {
        final d = data['data'] as Map<String, dynamic>;
        final v = preferHD
            ? _pick(d, ['hdplay', 'nwm_video_url_HQ', 'play', 'nwm_video_url'])
            : _pick(d, ['play', 'nwm_video_url', 'hdplay']);
        if (v != null && v.isNotEmpty) {
          final title = (d['title'] as String? ?? 'tiktok')
              .replaceAll(RegExp(r'[^\w\s-]'), '')
              .trim();
          return ExtractResult.success(
              url: v,
              filename:
                  'TikTok_${title.substring(0, title.length.clamp(0, 30))}_${DateTime.now().millisecondsSinceEpoch}.mp4');
        }
      }
    }
    return null;
  }

  Future<ExtractResult?> _tiklydown(String url) async {
    final resp = await http.get(
      Uri.parse(
          'https://api.tiklydown.eu.org/api/download?url=${Uri.encodeComponent(url)}'),
      headers: {'User-Agent': _ua},
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final video = data['video'] as Map<String, dynamic>?;
      final v =
          video?['noWatermark'] as String? ?? video?['watermark'] as String?;
      if (v != null && v.isNotEmpty) {
        return ExtractResult.success(
            url: v,
            filename: 'tiktok_${DateTime.now().millisecondsSinceEpoch}.mp4');
      }
    }
    return null;
  }

  Future<ExtractResult?> _ssstik(String url) async {
    final home = await http.get(Uri.parse('https://ssstik.io/en'),
        headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 10));
    final tokenM = RegExp(r'tt:\s*"([^"]+)"').firstMatch(home.body);
    final token = tokenM?.group(1);
    if (token == null) return null;
    final dl = await http
        .post(
          Uri.parse('https://ssstik.io/abc?url=dl'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Origin': 'https://ssstik.io',
            'Referer': 'https://ssstik.io/en',
            'User-Agent': _ua
          },
          body: 'id=${Uri.encodeComponent(url)}&locale=en&tt=$token',
        )
        .timeout(const Duration(seconds: 15));
    if (dl.statusCode == 200) {
      final m =
          RegExp(r'href="(https://[^"]+\.mp4[^"]*)"', caseSensitive: false)
              .firstMatch(dl.body);
      if (m?.group(1) != null) {
        return ExtractResult.success(
            url: m!.group(1)!,
            filename: 'tiktok_${DateTime.now().millisecondsSinceEpoch}.mp4');
      }
    }
    return null;
  }

  // ═══ INSTAGRAM (8 methods) ════════════════════════════════════════
  // Method order: embed → GraphQL → igram → saveig → snapinsta →
  //               snapsave → ddinstagram → reelsaver → cobalt → browser
  Future<ExtractResult> _instagram(String url) async {
    final shortcode = _igShortcode(url);
    // 1. Embed page parse (fastest, no external service)
    try {
      final r = await _instagramEmbed(shortcode);
      if (r != null) {
        print('✅ ig embed');
        return r;
      }
    } catch (e) {
      print('ig embed: $e');
    }
    // 2. Instagram GraphQL API (direct, no login needed for public posts)
    try {
      final r = await _instagramGraphQL(shortcode);
      if (r != null) {
        print('✅ ig graphql');
        return r;
      }
    } catch (e) {
      print('ig graphql: $e');
    }
    // 3-8. Third-party services
    try {
      final r = await _igram(url);
      if (r != null) {
        print('✅ igram');
        return r;
      }
    } catch (e) {
      print('igram: $e');
    }
    try {
      final r = await _saveig(url);
      if (r != null) {
        print('✅ saveig');
        return r;
      }
    } catch (e) {
      print('saveig: $e');
    }
    try {
      final r = await _snapinsta(url);
      if (r != null) {
        print('✅ snapinsta');
        return r;
      }
    } catch (e) {
      print('snapinsta: $e');
    }
    try {
      final r = await _snapsave(url);
      if (r != null) {
        print('✅ snapsave');
        return r;
      }
    } catch (e) {
      print('snapsave: $e');
    }
    try {
      final r = await _instagramDd(url);
      if (r != null) {
        print('✅ ddinstagram');
        return r;
      }
    } catch (e) {
      print('ddinstagram: $e');
    }
    try {
      final r = await _reelsaver(url);
      if (r != null) {
        print('✅ reelsaver');
        return r;
      }
    } catch (e) {
      print('reelsaver: $e');
    }
    final r = await _cobalt(url);
    if (r.ok) {
      print('✅ cobalt ig');
      return r;
    }
    return ExtractResult.error('USE_BROWSER');
  }

  // Instagram GraphQL API — works for public posts without login.
  // Uses Instagram's internal query endpoint with X-IG-App-ID header.
  // Source: PDF "Zero-Cost Hack" — doc_id 24368985919464652 is the media query.
  Future<ExtractResult?> _instagramGraphQL(String? shortcode) async {
    if (shortcode == null) return null;
    try {
      final resp = await http
          .post(
            Uri.parse('https://www.instagram.com/graphql/query'),
            headers: {
              'X-IG-App-ID': '936619743392459',
              'Content-Type': 'application/x-www-form-urlencoded',
              'User-Agent': _desktopUa,
              'Accept': '*/*',
              'Referer': 'https://www.instagram.com/',
              'X-Requested-With': 'XMLHttpRequest',
            },
            body:
                'variables=${Uri.encodeComponent('{"shortcode":"$shortcode","fetch_comment_count":0}')}'
                '&doc_id=24368985919464652',
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final media = ((data['data'] as Map?)
                    ?.cast<String, dynamic>()?['xdt_shortcode_v2']
                as Map<String, dynamic>?) ??
            ((data['data'] as Map?)?.cast<String, dynamic>()?['shortcode_media']
                as Map<String, dynamic>?);

        if (media != null) {
          // Direct video
          final videoUrl = media['video_url'] as String?;
          if (videoUrl != null && videoUrl.isNotEmpty) {
            return ExtractResult.success(
                url: videoUrl, filename: 'instagram_$shortcode.mp4');
          }
          // Carousel with video
          final edges = (media['edge_sidecar_to_children'] as Map?)
              ?.cast<String, dynamic>()?['edges'] as List?;
          if (edges != null) {
            for (final edge in edges) {
              final node = (edge as Map<String, dynamic>)['node'] as Map?;
              final u = node?['video_url'] as String?;
              if (u != null && u.isNotEmpty) {
                return ExtractResult.success(
                    url: u, filename: 'instagram_$shortcode.mp4');
              }
            }
          }
        }
      } else if (resp.statusCode == 429) {
        print('ig graphql: rate limited');
      }
    } catch (e) {
      print('_instagramGraphQL: $e');
    }
    return null;
  }

  Future<ExtractResult?> _igram(String url) async {
    final resp = await http
        .post(
          Uri.parse('https://igram.world/api/convert'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Origin': 'https://igram.world',
            'Referer': 'https://igram.world/',
            'User-Agent': _desktopUa,
            'X-Requested-With': 'XMLHttpRequest'
          },
          body: 'url=${Uri.encodeComponent(url)}',
        )
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode == 200) {
      try {
        final data = jsonDecode(resp.body);
        final items = data is List
            ? data
            : (data['data'] is List ? data['data'] as List : null);
        if (items != null) {
          for (final item in items) {
            final m = item as Map<String, dynamic>;
            final u = m['url'] as String? ?? m['src'] as String? ?? '';
            if (u.startsWith('http') &&
                !u.contains('.jpg') &&
                !u.contains('.jpeg')) {
              return ExtractResult.success(
                  url: u,
                  filename:
                      'instagram_${DateTime.now().millisecondsSinceEpoch}.mp4');
            }
          }
        }
        final u = data['url'] as String? ?? '';
        if (u.startsWith('http') && u.contains('mp4')) {
          return ExtractResult.success(
              url: u,
              filename:
                  'instagram_${DateTime.now().millisecondsSinceEpoch}.mp4');
        }
      } catch (_) {}
    }
    return null;
  }

  Future<ExtractResult?> _saveig(String url) async {
    final resp = await http
        .post(
          Uri.parse('https://saveig.app/api/ajaxSearch'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Origin': 'https://saveig.app',
            'Referer': 'https://saveig.app/',
            'User-Agent': _ua
          },
          body: 'q=${Uri.encodeComponent(url)}&t=media&lang=en',
        )
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode == 200) {
      try {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final html = data['data'] as String? ?? '';
        final m =
            RegExp(r'href="(https://[^"]+\.mp4[^"]*)"', caseSensitive: false)
                .firstMatch(html);
        if (m != null)
          return ExtractResult.success(
              url: m.group(1)!,
              filename:
                  'instagram_${DateTime.now().millisecondsSinceEpoch}.mp4');
      } catch (_) {}
    }
    return null;
  }

  String? _igShortcode(String url) =>
      RegExp(r'instagram\.com/(?:p|reel|tv|stories/[^/]+)/([A-Za-z0-9_-]+)')
          .firstMatch(url)
          ?.group(1);

  // Improved embed extraction — tries multiple URL formats and patterns
  // Also adds X-IG-App-ID which helps Instagram serve the full page JSON
  Future<ExtractResult?> _instagramEmbed(String? shortcode) async {
    if (shortcode == null) return null;

    // Try both reel and p URL formats, both captioned and plain embed
    final urls = [
      'https://www.instagram.com/reel/$shortcode/embed/',
      'https://www.instagram.com/p/$shortcode/embed/captioned/',
      'https://www.instagram.com/p/$shortcode/embed/',
      'https://www.instagram.com/reel/$shortcode/embed/captioned/',
    ];

    for (final embedUrl in urls) {
      try {
        final resp = await http.get(Uri.parse(embedUrl), headers: {
          'User-Agent': _desktopUa,
          'Accept': 'text/html,application/xhtml+xml',
          'Referer': 'https://www.instagram.com/',
          'Accept-Language': 'en-US,en;q=0.9',
          'X-IG-App-ID': '936619743392459', // helps get full JSON response
        }).timeout(const Duration(seconds: 15));

        if (resp.statusCode != 200) continue;
        final html = resp.body;

        // Multiple patterns to catch different embed page formats
        for (final p in [
          RegExp(r'"video_url"\s*:\s*"([^"]+)"'),
          RegExp(r'"clip_encode_url"\s*:\s*"([^"]+)"'),
          RegExp(r'"contentUrl"\s*:\s*"([^"]+)"'),
          RegExp(r'<source\s+src="([^"]+\.mp4[^"]*)"', caseSensitive: false),
          RegExp(r'"src"\s*:\s*"(https://[^"]+cdninstagram[^"]+)"'),
        ]) {
          final m = p.firstMatch(html);
          if (m != null) {
            final v = _decodeUrl(m.group(1)!);
            if (v.startsWith('http') &&
                !v.contains('.jpg') &&
                !v.contains('.jpeg')) {
              print('\u2705 ig embed from $embedUrl');
              return ExtractResult.success(
                  url: v, filename: 'instagram_$shortcode.mp4');
            }
          }
        }
      } catch (e) {
        print('embed $embedUrl: $e');
      }
    }
    return null;
  }

  Future<ExtractResult?> _snapinsta(String url) async {
    final home = await http.get(Uri.parse('https://snapinsta.app/'),
        headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 10));
    final token = RegExp(r'name="token"\s+value="([^"]+)"')
        .firstMatch(home.body)
        ?.group(1);
    if (token == null) return null;
    final dl = await http
        .post(
          Uri.parse('https://snapinsta.app/action.php'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': 'https://snapinsta.app/',
            'User-Agent': _ua
          },
          body: 'url=${Uri.encodeComponent(url)}&token=$token&lang=en',
        )
        .timeout(const Duration(seconds: 15));
    if (dl.statusCode == 200) {
      final m = RegExp(r'href="(https://[^"]+\.(mp4|jpg)[^"]*)"',
              caseSensitive: false)
          .firstMatch(dl.body);
      if (m?.group(1) != null)
        return ExtractResult.success(
            url: m!.group(1)!,
            filename:
                'instagram_${DateTime.now().millisecondsSinceEpoch}.${m.group(2)}');
    }
    return null;
  }

  Future<ExtractResult?> _snapsave(String url) async {
    final home = await http.get(Uri.parse('https://snapsave.app/'),
        headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 10));
    final token = RegExp(r'name="token"\s+value="([^"]+)"')
        .firstMatch(home.body)
        ?.group(1);
    if (token == null) return null;
    final dl = await http
        .post(
          Uri.parse('https://snapsave.app/action.php'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': 'https://snapsave.app/',
            'Origin': 'https://snapsave.app',
            'User-Agent': _ua
          },
          body: 'url=${Uri.encodeComponent(url)}&token=$token&lang=en',
        )
        .timeout(const Duration(seconds: 15));
    if (dl.statusCode == 200) {
      for (final p in [
        RegExp(r'href="(https://[^"]+\.mp4[^"]*)"[^>]*>[^<]*HD',
            caseSensitive: false),
        RegExp(r'href="(https://[^"]+\.mp4[^"]*)"', caseSensitive: false),
      ]) {
        final m = p.firstMatch(dl.body);
        if (m?.group(1) != null)
          return ExtractResult.success(
              url: m!.group(1)!,
              filename:
                  'instagram_${DateTime.now().millisecondsSinceEpoch}.mp4');
      }
    }
    return null;
  }

  Future<ExtractResult?> _instagramDd(String url) async {
    final ddUrl = url
        .replaceFirst(RegExp(r'https://(www\.)?instagram\.com'),
            'https://www.ddinstagram.com')
        .replaceFirst(
            RegExp(r'https://instagr\.am'), 'https://www.ddinstagram.com');
    final resp = await http.get(Uri.parse(ddUrl), headers: {
      'User-Agent': _desktopUa,
      'Accept': 'text/html,application/xhtml+xml',
      'Accept-Language': 'en-US,en;q=0.9'
    }).timeout(const Duration(seconds: 15));
    if (resp.statusCode == 200) {
      final html = resp.body;
      for (final p in [
        RegExp(r'"contentUrl"\s*:\s*"([^"]+)"'),
        RegExp(r'"url"\s*:\s*"(https://[^"]*\.mp4[^"]*)"',
            caseSensitive: false),
        RegExp(r'"video_url"\s*:\s*"([^"]+)"'),
      ]) {
        final m = p.firstMatch(html);
        if (m != null) {
          final v = _decodeUrl(m.group(1)!);
          if (v.startsWith('http') &&
              (v.contains('.mp4') || v.contains('cdninstagram'))) {
            return ExtractResult.success(
                url: v,
                filename:
                    'instagram_${DateTime.now().millisecondsSinceEpoch}.mp4');
          }
        }
      }
    }
    return null;
  }

  Future<ExtractResult?> _reelsaver(String url) async {
    final home = await http.get(Uri.parse('https://reelsaver.net/'), headers: {
      'User-Agent': _desktopUa
    }).timeout(const Duration(seconds: 10));
    final tokenM =
        RegExp(r'name="[_]token"\s+value="([^"]+)"').firstMatch(home.body) ??
            RegExp(r'"csrf_token"\s*:\s*"([^"]+)"').firstMatch(home.body);
    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
      'Referer': 'https://reelsaver.net/',
      'Origin': 'https://reelsaver.net',
      'User-Agent': _desktopUa,
      'X-Requested-With': 'XMLHttpRequest',
      if (tokenM != null) 'X-CSRF-TOKEN': tokenM.group(1)!,
    };
    final resp = await http
        .post(Uri.parse('https://reelsaver.net/api/process'),
            headers: headers, body: 'url=${Uri.encodeComponent(url)}')
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode == 200) {
      try {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        for (final key in [
          'url',
          'download_url',
          'video_url',
          'hd_url',
          'sd_url'
        ]) {
          final v = data[key] as String?;
          if (v != null && v.startsWith('http'))
            return ExtractResult.success(
                url: v,
                filename:
                    'instagram_${DateTime.now().millisecondsSinceEpoch}.mp4');
        }
        final links = data['links'] as List? ?? data['data'] as List? ?? [];
        for (final item in links) {
          final v = (item as Map<String, dynamic>)['url'] as String? ?? '';
          if (v.startsWith('http') && !v.contains('.jpg'))
            return ExtractResult.success(
                url: v,
                filename:
                    'instagram_${DateTime.now().millisecondsSinceEpoch}.mp4');
        }
      } catch (_) {
        final m = RegExp(r'"(https://[^"]+\.mp4[^"]*)"', caseSensitive: false)
            .firstMatch(resp.body);
        if (m != null)
          return ExtractResult.success(
              url: m.group(1)!,
              filename:
                  'instagram_${DateTime.now().millisecondsSinceEpoch}.mp4');
      }
    }
    return null;
  }

  // ═══ FACEBOOK ══════════════════════════════════════════════════════
  Future<ExtractResult> _facebook(String url) async {
    for (final fn in [
      () => _facebookMbasic(url),
      () => _fdownNet(url),
      () => _getfvid(url)
    ]) {
      try {
        final r = await fn();
        if (r != null) return r;
      } catch (e) {
        print('fb: $e');
      }
    }
    final r = await _cobalt(url);
    return r.ok ? r : ExtractResult.error('USE_BROWSER');
  }

  Future<ExtractResult?> _facebookMbasic(String url) async {
    var mUrl = url
        .replaceFirst(RegExp(r'https://(www|web|m)\.facebook\.com'),
            'https://mbasic.facebook.com')
        .replaceFirst('https://fb.com', 'https://mbasic.facebook.com');
    final resp = await http.get(Uri.parse(mUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36',
      'Accept': 'text/html',
      'Accept-Language': 'en-US,en;q=0.9'
    }).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) return null;
    for (final p in [
      RegExp(r'"hd_src"\s*:\s*"([^"]+)"'),
      RegExp(r'"browser_native_hd_url"\s*:\s*"([^"]+)"'),
      RegExp(r'"sd_src_no_ratelimit"\s*:\s*"([^"]+)"'),
      RegExp(r'"sd_src"\s*:\s*"([^"]+)"'),
      RegExp(r'"playable_url_quality_hd"\s*:\s*"([^"]+)"'),
      RegExp(r'"playable_url"\s*:\s*"([^"]+)"'),
    ]) {
      final m = p.firstMatch(resp.body);
      if (m != null) {
        final v = _decodeUrl(m.group(1)!);
        if (v.startsWith('http') &&
            (v.contains('.mp4') || v.contains('fbcdn'))) {
          return ExtractResult.success(
              url: v,
              filename:
                  'facebook_${DateTime.now().millisecondsSinceEpoch}.mp4');
        }
      }
    }
    return null;
  }

  Future<ExtractResult?> _fdownNet(String url) async {
    await http.get(Uri.parse('https://fdown.net/'), headers: {
      'User-Agent': _desktopUa
    }).timeout(const Duration(seconds: 10));
    final resp = await http
        .post(
          Uri.parse('https://fdown.net/download.php'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': 'https://fdown.net/',
            'Origin': 'https://fdown.net',
            'User-Agent': _desktopUa
          },
          body: 'URLz=${Uri.encodeComponent(url)}',
        )
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode == 200) {
      for (final p in [
        RegExp(r'id="hdlink"[^>]*href="([^"]+)"'),
        RegExp(r'id="sdlink"[^>]*href="([^"]+)"'),
        RegExp(r'href="([^"]+\.mp4[^"]*)"', caseSensitive: false)
      ]) {
        final m = p.firstMatch(resp.body);
        if (m != null && m.group(1)!.startsWith('http'))
          return ExtractResult.success(
              url: m.group(1)!,
              filename:
                  'facebook_${DateTime.now().millisecondsSinceEpoch}.mp4');
      }
    }
    return null;
  }

  Future<ExtractResult?> _getfvid(String url) async {
    final resp = await http
        .post(
          Uri.parse('https://getfvid.com/downloader'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': 'https://getfvid.com/',
            'User-Agent': _desktopUa
          },
          body: 'url=${Uri.encodeComponent(url)}',
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 200) {
      final m =
          RegExp(r'href="(https://[^"]+\.mp4[^"]*)"', caseSensitive: false)
              .firstMatch(resp.body);
      if (m != null)
        return ExtractResult.success(
            url: m.group(1)!,
            filename: 'facebook_${DateTime.now().millisecondsSinceEpoch}.mp4');
    }
    return null;
  }

  // ═══ TWITTER ═══════════════════════════════════════════════════════
  Future<ExtractResult> _twitter(String url) async {
    try {
      final id = RegExp(r'/status/(\d+)').firstMatch(url)?.group(1);
      if (id != null) {
        final resp = await http.get(
            Uri.parse('https://api.fxtwitter.com/status/$id'),
            headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          if ((data['code'] as num?)?.toInt() == 200) {
            final media =
                (data['tweet'] as Map?)?.cast<String, dynamic>()?['media'];
            final videos =
                (media as Map?)?.cast<String, dynamic>()?['videos'] as List?;
            if (videos != null && videos.isNotEmpty) {
              String? bestUrl;
              int bestWidth = 0;
              for (final v in videos) {
                final vm = v as Map<String, dynamic>;
                final u = vm['url'] as String?;
                final w = (vm['width'] as num?)?.toInt() ?? 0;
                if (u != null && w > bestWidth) {
                  bestUrl = u;
                  bestWidth = w;
                }
              }
              bestUrl ??=
                  (videos.first as Map<String, dynamic>)['url'] as String?;
              if (bestUrl != null)
                return ExtractResult.success(
                    url: bestUrl, filename: 'twitter_$id.mp4');
            }
          }
        }
      }
    } catch (e) {
      print('FxTwitter: $e');
    }
    return ExtractResult.error('USE_BROWSER');
  }

  // ═══ VIMEO ═════════════════════════════════════════════════════════
  // Direct player config API — no auth needed for public videos
  Future<ExtractResult> _vimeo(String url) async {
    final id = RegExp(r'vimeo\.com/(?:video/)?(\d+)').firstMatch(url)?.group(1);
    if (id != null) {
      try {
        final resp = await http.get(
          Uri.parse('https://player.vimeo.com/video/$id/config'),
          headers: {
            'User-Agent': _desktopUa,
            'Referer': 'https://vimeo.com/',
            'Accept': 'application/json'
          },
        ).timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final request = (data['request'] as Map?)?.cast<String, dynamic>();
          final files = (request?['files'] as Map?)?.cast<String, dynamic>();
          final progressive = files?['progressive'] as List?;
          if (progressive != null && progressive.isNotEmpty) {
            // Sort by width descending (best quality first)
            final sorted = List.from(progressive)
              ..sort((a, b) => ((b as Map)['width'] as int? ?? 0)
                  .compareTo((a as Map)['width'] as int? ?? 0));
            final best = sorted.first as Map<String, dynamic>;
            final u = best['url'] as String?;
            if (u != null && u.isNotEmpty) {
              print(
                  '✅ Vimeo direct: ${best['quality']} ${best['width']}x${best['height']}');
              return ExtractResult.success(url: u, filename: 'vimeo_$id.mp4');
            }
          }
          // Also check HLS if progressive not available
          final hls = (files?['hls'] as Map?)?.cast<String, dynamic>();
          final hlsUrl = hls?['url'] as String?;
          if (hlsUrl != null && hlsUrl.isNotEmpty) {
            return ExtractResult.success(
                url: hlsUrl, filename: 'vimeo_$id.mp4');
          }
        }
      } catch (e) {
        print('Vimeo direct: $e');
      }
    }
    // Fallback to cobalt
    final r = await _cobalt(url);
    return r.ok ? r : ExtractResult.error('USE_BROWSER');
  }

  // ═══ DAILYMOTION ═══════════════════════════════════════════════════
  // Public metadata API — works for all public videos
  Future<ExtractResult> _dailymotion(String url) async {
    final id = RegExp(r'dailymotion\.com/video/([a-zA-Z0-9]+)')
            .firstMatch(url)
            ?.group(1) ??
        RegExp(r'dai\.ly/([a-zA-Z0-9]+)').firstMatch(url)?.group(1);
    if (id != null) {
      try {
        final resp = await http.get(
          Uri.parse(
              'https://www.dailymotion.com/player/metadata/video/$id?embedder=https://www.dailymotion.com&locale=en&autoplay=on'),
          headers: {
            'User-Agent': _desktopUa,
            'Referer': 'https://www.dailymotion.com/'
          },
        ).timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final qualities = data['qualities'] as Map?;
          for (final q in ['1080', '720', '480', '380', '240', 'auto']) {
            final streams = qualities?[q] as List?;
            if (streams != null && streams.isNotEmpty) {
              for (final stream in streams) {
                final u = (stream as Map)['url'] as String?;
                if (u != null && u.isNotEmpty && !u.contains('.m3u8')) {
                  print('✅ Dailymotion direct: ${q}p');
                  return ExtractResult.success(
                      url: u, filename: 'dailymotion_$id.mp4');
                }
              }
              // Accept HLS too if no direct MP4 found
              for (final stream in streams) {
                final u = (stream as Map)['url'] as String?;
                if (u != null && u.isNotEmpty) {
                  return ExtractResult.success(
                      url: u, filename: 'dailymotion_$id.mp4');
                }
              }
            }
          }
        }
      } catch (e) {
        print('Dailymotion direct: $e');
      }
    }
    final r = await _cobalt(url);
    return r.ok ? r : ExtractResult.error('USE_BROWSER');
  }

  // ═══ COBALT ════════════════════════════════════════════════════════
  Future<ExtractResult> _cobalt(String url) async {
    for (final instance in _cobaltInstances) {
      try {
        final resp = await http
            .post(
              Uri.parse(instance),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'User-Agent': _ua
              },
              body: jsonEncode({
                'url': url,
                'videoQuality': '1080',
                'downloadMode': 'auto',
                'filenameStyle': 'pretty'
              }),
            )
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final status = data['status'] as String? ?? 'error';
          if (status == 'redirect' || status == 'tunnel') {
            final u = data['url'] as String?;
            if (u != null && u.isNotEmpty)
              return ExtractResult.success(
                  url: u, filename: data['filename'] as String?);
          }
          if (status == 'picker') {
            final items = (data['picker'] as List? ?? [])
                .map((i) => ExtractItem(
                    url: (i as Map<String, dynamic>)['url'] as String? ?? '',
                    type: i['type'] as String? ?? 'video'))
                .where((i) => i.url.isNotEmpty)
                .toList();
            if (items.isNotEmpty) {
              final best = items.firstWhere((i) => i.type == 'video',
                  orElse: () => items.first);
              return ExtractResult.success(url: best.url, items: items);
            }
          }
          final code =
              ((data['error'] as Map?)?.cast<String, dynamic>()?['code'] ?? '')
                  as String;
          if (code.contains('auth')) continue;
        }
      } catch (_) {}
    }
    return ExtractResult.error('cobalt failed');
  }

  // ═══ HELPERS ═══════════════════════════════════════════════════════
  String _decodeUrl(String s) => s
      .replaceAll(r'\/', '/')
      .replaceAll(r'\u0026', '&')
      .replaceAll('&amp;', '&')
      .replaceAll(r'\n', '')
      .trim();
  String? _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k] as String?;
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  bool _isTikTok(String u) =>
      u.contains('tiktok.com') || u.contains('vm.tiktok.com');
  bool _isTwitter(String u) =>
      u.contains('twitter.com') || u.contains('x.com/') || u.contains('t.co/');
  bool _isFacebook(String u) =>
      u.contains('facebook.com') ||
      u.contains('fb.com') ||
      u.contains('fb.watch');
  bool _isInstagram(String u) =>
      u.contains('instagram.com') || u.contains('instagr.am');
  bool _isVimeo(String u) => u.contains('vimeo.com');
  bool _isDailymotion(String u) =>
      u.contains('dailymotion.com') || u.contains('dai.ly/');

  static bool isSupportedUrl(String url) {
    final l = url.toLowerCase();
    return l.contains('tiktok.com') ||
        l.contains('instagram.com') ||
        l.contains('instagr.am') ||
        l.contains('twitter.com') ||
        l.contains('x.com/') ||
        l.contains('t.co/') ||
        l.contains('facebook.com') ||
        l.contains('fb.com') ||
        l.contains('fb.watch') ||
        l.contains('vimeo.com') ||
        l.contains('dailymotion.com') ||
        l.contains('dai.ly/') ||
        l.contains('reddit.com') ||
        l.contains('redd.it') ||
        l.contains('pinterest.com') ||
        l.contains('pin.it') ||
        l.contains('twitch.tv') ||
        l.contains('soundcloud.com') ||
        l.contains('linkedin.com') ||
        l.contains('lnkd.in') ||
        l.contains('bilibili.com') ||
        l.contains('b23.tv') ||
        l.contains('tubidy.com') ||
        l.contains('tubidy.mobi') ||
        l.contains('ok.ru') ||
        l.contains('odnoklassniki.ru') ||
        l.contains('streamable.com') ||
        l.contains('loom.com') ||
        l.contains('tumblr.com') ||
        l.contains('rutube.ru') ||
        l.contains('kick.com') ||
        l.contains('triller.co') ||
        l.contains('rumble.com') ||
        l.contains('bitchute.com') ||
        l.contains('clips.twitch.tv');
  }

  static String detectPlatform(String url) {
    final l = url.toLowerCase();
    if (l.contains('tiktok.com')) return 'tiktok';
    if (l.contains('instagram.com') || l.contains('instagr.am'))
      return 'instagram';
    if (l.contains('twitter.com') || l.contains('x.com') || l.contains('t.co'))
      return 'twitter';
    if (l.contains('facebook.com') ||
        l.contains('fb.com') ||
        l.contains('fb.watch')) return 'facebook';
    if (l.contains('vimeo.com')) return 'vimeo';
    if (l.contains('dailymotion.com') || l.contains('dai.ly'))
      return 'dailymotion';
    if (l.contains('reddit.com') || l.contains('redd.it')) return 'reddit';
    if (l.contains('pinterest.com') || l.contains('pin.it')) return 'pinterest';
    if (l.contains('twitch.tv') || l.contains('clips.twitch')) return 'twitch';
    if (l.contains('soundcloud.com')) return 'soundcloud';
    if (l.contains('linkedin.com') || l.contains('lnkd.in')) return 'linkedin';
    if (l.contains('bilibili.com') || l.contains('b23.tv')) return 'bilibili';
    if (l.contains('tubidy.com') || l.contains('tubidy.mobi')) return 'tubidy';
    if (l.contains('ok.ru') || l.contains('odnoklassniki')) return 'okru';
    if (l.contains('streamable.com')) return 'streamable';
    if (l.contains('loom.com')) return 'loom';
    if (l.contains('rumble.com')) return 'rumble';
    if (l.contains('kick.com')) return 'kick';
    return 'unknown';
  }

  // ═══ FILE DOWNLOAD ══════════════════════════════════════════════════
  static Future<String?> downloadFile(
    String downloadUrl,
    String savePath, {
    Map<String, String>? extraHeaders,
    int minSizeBytes = 1024,
    void Function(double)? onProgress,
    void Function(String)? onError,
  }) async {
    if (downloadUrl.startsWith('blob:')) {
      onError?.call('Cannot download blob URL');
      return null;
    }
    for (int attempt = 1; attempt <= 2; attempt++) {
      final result = await _doDownload(downloadUrl, savePath,
          extraHeaders: extraHeaders,
          minSizeBytes: minSizeBytes,
          onProgress: onProgress,
          onError: attempt == 2 ? onError : null);
      if (result != null) return result;
      if (attempt == 1) await Future.delayed(const Duration(seconds: 2));
    }
    onError?.call('Download failed after 2 attempts.');
    return null;
  }

  static Future<String?> _doDownload(
    String downloadUrl,
    String savePath, {
    Map<String, String>? extraHeaders,
    int minSizeBytes = 1024,
    void Function(double)? onProgress,
    void Function(String)? onError,
  }) async {
    HttpClient? client;
    IOSink? sink;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30)
        ..badCertificateCallback = (_, __, ___) => true;

      final request = await client.getUrl(Uri.parse(downloadUrl));
      request.headers.set('User-Agent', _ua);
      request.headers.set('Accept', '*/*');
      request.headers.set('Accept-Language', 'en-US,en;q=0.9');

      if (extraHeaders != null) {
        for (final e in extraHeaders.entries) {
          request.headers.set(e.key, e.value);
        }
      } else {
        final lo = downloadUrl.toLowerCase();
        if (lo.contains('cdninstagram.com')) {
          request.headers.set('Referer', 'https://www.instagram.com/');
        } else if (lo.contains('fbcdn.net')) {
          request.headers.set('Referer', 'https://www.facebook.com/');
        } else if (lo.contains('video.twimg.com')) {
          request.headers.set('Referer', 'https://twitter.com/');
          request.headers.set('Origin', 'https://twitter.com');
        } else {
          request.headers.set('Referer', 'https://www.google.com/');
        }
      }

      final response =
          await request.close().timeout(const Duration(seconds: 120));
      if (response.statusCode != 200 && response.statusCode != 206) {
        onError?.call('Server error: HTTP ${response.statusCode}');
        return null;
      }

      // ── CONTENT-TYPE GUARD ────────────────────────────────────────────────
      // Instagram/Facebook CDN returns 200 OK with HTML when the session is
      // invalid or the URL has expired. Without this check we save an HTML
      // file as .mp4 — it's ~50KB, passes the size check, but is unusable.
      final contentType = response.headers.value('content-type') ?? '';
      if (contentType.contains('text/html') ||
          contentType.contains('text/xml')) {
        onError?.call(
            'CDN returned a webpage instead of video (URL expired or blocked). content-type: $contentType');
        try {
          await File(savePath).delete();
        } catch (_) {}
        return null;
      }
      // ── END CONTENT-TYPE GUARD ────────────────────────────────────────────

      final contentLength = response.contentLength;
      final file = File(savePath);
      await file.parent.create(recursive: true);
      sink = file.openWrite();
      int received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          onProgress?.call(received / contentLength);
        } else {
          onProgress?.call(0.3 + (received % 5000000) / 15000000);
        }
      }
      await sink.flush();
      await sink.close();
      client.close();

      final fileSize = await file.length();
      if (fileSize < minSizeBytes) {
        await file.delete();
        onError?.call(
            'File too small (${fileSize}B) — possibly private or restricted content');
        return null;
      }
      onProgress?.call(1.0);
      print('✅ Downloaded ${fileSize ~/ 1024}KB → $savePath');
      return savePath;
    } catch (e) {
      print('_doDownload error: $e');
      try {
        await sink?.close();
      } catch (_) {}
      client?.close(force: true);
      try {
        final f = File(savePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      onError?.call(
          e.toString().length > 80 ? e.toString().substring(0, 80) : '$e');
      return null;
    }
  }
}

typedef CobaltApiService = MediaExtractorService;
