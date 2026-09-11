// ui/screens/browser_download_screen.dart
// ignore_for_file: avoid_print, use_build_context_synchronously

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../providers/media_provider.dart';
import '../../providers/premium_provider.dart';
import '../../services/cobalt_api_service.dart';
import '../themes/app_theme.dart';

class BrowserDownloadScreen extends StatefulWidget {
  final String url;
  const BrowserDownloadScreen({Key? key, required this.url}) : super(key: key);
  @override
  State<BrowserDownloadScreen> createState() => _BrowserDownloadScreenState();
}

class _BrowserDownloadScreenState extends State<BrowserDownloadScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _loadProgress = 0.0;
  _VideoCandidate? _bestCandidate;
  bool _isDownloading = false;
  String _dlStatus = '';
  double _dlProgress = 0.0;
  String _platform = '';
  String? _lastError;
  bool _autoDownloadTriggered = false;

  static const _cookieChannel = MethodChannel('MediaNest/cookies');
  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Safari/537.36';

  static const _js = r"""
(function(){
  'use strict';
  var bestScore = 0;
  var seen = {};

  function scoreUrl(url) {
    if (!url || typeof url !== 'string') return 0;
    if (!url.startsWith('http')) return 0;
    if (url.startsWith('blob:')) return 0;
    var lo = url.toLowerCase();
    if (/\.(jpg|jpeg|png|webp|gif|svg|ico|css|woff|woff2)(\?|$)/.test(lo)) return 0;
    if (lo.includes('pbs.twimg.com')) return 0;
    if (lo.includes('/t51.') || lo.includes('/t50.') || lo.includes('/profile_pic')) return 0;
    if (lo.includes('/e15/') || lo.includes('/e35/') || lo.includes('_thumbnail')) return 0;
    if (lo.includes('doubleclick') || lo.includes('/ads/') || lo.includes('analytics')) return 0;

    var s = 0;
    if (lo.includes('video.twimg.com')) s += 500;
    if (lo.includes('') && lo.includes('videoplayback')) {
      s += 480;
      if (lo.includes('itag=22'))  s += 120;
      if (lo.includes('itag=18'))  s += 100;
      if (lo.includes('itag=137')) s += 130;
    }
    if (lo.includes('video.xx.fbcdn.net') || (lo.includes('fbcdn.net') && lo.includes('video'))) s += 460;
    else if (lo.includes('fbcdn.net') && lo.includes('.mp4')) s += 300;

    // Instagram CDN — permissive match
    if (lo.includes('cdninstagram.com')) {
      s += 350;
      if (lo.includes('/v/') || lo.includes('.mp4') || lo.includes('video')) s += 90;
    }

    if (lo.includes('tiktokcdn') || lo.includes('tiktok.com/video') || lo.includes('muscdn.com')) s += 420;

    // LinkedIn
    if (lo.includes('media.licdn.com') || lo.includes('dms.licdn.com') || lo.includes('licdn.com/dms')) {
      s += 480;
      if (lo.includes('video') || lo.includes('.mp4') || lo.includes('playback')) s += 40;
    }

    if (lo.includes('vimeocdn.com') || lo.includes('vod-progressive.akamaized.net')) s += 460;
    if (lo.includes('dm-b.akamaized.net') || (lo.includes('dailymotion') && lo.includes('.mp4'))) s += 440;

    if (lo.includes('.mp4'))         s += 80;
    if (lo.includes('mime=video') || lo.includes('video/mp4')) s += 70;
    if (lo.includes('.m3u8') && s > 0) s += 30;

    return s;
  }

  function report(url) {
    if (!url || seen[url]) return;
    var s = scoreUrl(url);
    if (s <= 0) return;
    seen[url] = true;
    if (s > bestScore) {
      bestScore = s;
      try { VideoDetector.postMessage(s + '|||' + url); } catch(e){}
    }
  }

  function scanPageJSON() {
    var html = '';
    try { html = document.documentElement.innerHTML; } catch(e){ return; }
    var patterns = [
      /"hd_src"\s*:\s*"([^"]+)"/g,
      /"browser_native_hd_url"\s*:\s*"([^"]+)"/g,
      /"sd_src_no_ratelimit"\s*:\s*"([^"]+)"/g,
      /"sd_src"\s*:\s*"([^"]+)"/g,
      /"playable_url_quality_hd"\s*:\s*"([^"]+)"/g,
      /"playable_url"\s*:\s*"([^"]+)"/g,
      /"video_url"\s*:\s*"([^"]+)"/g,
      /"clip_encode_url"\s*:\s*"([^"]+)"/g,
      /"contentUrl"\s*:\s*"([^"]+)"/g,
      /"url"\s*:\s*"(https:\/\/[^"]+cdninstagram[^"]+)"/g,
      /"url"\s*:\s*"(https:\/\/media\.licdn\.com[^"]+)"/g,
      /"url"\s*:\s*"(https:\/\/dms\.licdn\.com[^"]+)"/g,
      /"url"\s*:\s*"(https:\/\/[^"]+vimeocdn[^"]+)"/g,
    ];
    patterns.forEach(function(re) {
      var m;
      re.lastIndex = 0;
      while ((m = re.exec(html)) !== null) {
        var u = m[1].replace(/\\\//g,'/').replace(/\\u0026/g,'&');
        if (u.startsWith('http')) report(u);
      }
    });

    // Also scan <script> tag contents directly for Instagram's JSON data
    document.querySelectorAll('script').forEach(function(s) {
      if (s.textContent && s.textContent.includes('video_url')) {
        var mm = s.textContent.match(/"video_url":"([^"]+)"/);
        if (mm) {
          var u2 = mm[1].replace(/\\\//g,'/').replace(/\\u0026/g,'&');
          if (u2.startsWith('http')) report(u2);
        }
      }
    });
  }

  function scanOGTags() {
    ['og:video','og:video:url','og:video:secure_url'].forEach(function(prop) {
      var el = document.querySelector('meta[property="'+prop+'"]');
      if (el) { var u = el.content || el.getAttribute('content'); if (u) report(u); }
    });
  }

  function scanDOM() {
    document.querySelectorAll('video,source').forEach(function(el) {
      if (el.src && el.src.startsWith('http')) report(el.src);
      if (el.currentSrc && el.currentSrc.startsWith('http')) report(el.currentSrc);
    });
  }

  var sDesc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
  if (sDesc && sDesc.set) {
    Object.defineProperty(HTMLMediaElement.prototype, 'src', {
      set: function(v) { if(v) report(v); sDesc.set.call(this,v); },
      get: sDesc.get, configurable: true
    });
  }
  var origPlay = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function() {
    if (this.currentSrc) report(this.currentSrc);
    if (this.src) report(this.src);
    return origPlay.apply(this, arguments);
  };

  var origOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(m, url) {
    if (typeof url === 'string') report(url);
    return origOpen.apply(this, arguments);
  };

  var origFetch = window.fetch;
  if (origFetch) {
    window.fetch = function(input, init) {
      var url = typeof input === 'string' ? input : (input && input.url);
      if (url) report(url);
      return origFetch.apply(this, arguments);
    };
  }

  // Expand video elements to fill screen width — fixes Facebook small video issue
  function expandVideos() {
    document.querySelectorAll('video').forEach(function(v) {
      v.style.width = '100%';
      v.style.maxHeight = '85vh';
      v.style.display = 'block';
    });
    // Inject CSS to override Facebook/LinkedIn container constraints
    if (!document.getElementById('_MediaNest_css')) {
      var s = document.createElement('style');
      s.id = '_MediaNest_css';
      s.textContent = [
        'video { width:100%!important; max-height:85vh!important; display:block!important; }',
        '[data-pagelet="RightRail"] { display:none!important; }',
        // Facebook: hide sidebars, expand video column
        '._9zta, ._9zt9, ._9zt8 { display:none!important; }',
        // LinkedIn: expand video container
        '.feed-shared-external-video__meta { display:none!important; }',
      ].join(' ');
      (document.head || document.documentElement).appendChild(s);
    }
  }

  function dismissOverlays() {
    var phrases = [
      'Log in to Facebook','Sign Up for Facebook','Log in','Sign up',
      'See more on Facebook','Get started','Join active smart',
      'Sign up for Instagram','Log in to continue'
    ];
    ['[aria-label="Close"]','[aria-label="close"]','[data-testid="dialog-close-button"]'].forEach(function(sel) {
      document.querySelectorAll(sel).forEach(function(el) { try { el.click(); } catch(_){} });
    });
    document.querySelectorAll('[role="dialog"]').forEach(function(dialog) {
      var t = dialog.innerText || '';
      if (phrases.some(function(p){ return t.includes(p); }) && dialog.offsetHeight > 100) {
        dialog.style.cssText = 'display:none!important;visibility:hidden!important;pointer-events:none!important;';
      }
    });
    document.body.style.overflow = 'auto';
    document.documentElement.style.overflow = 'auto';
  }

  new MutationObserver(function(){ scanDOM(); dismissOverlays(); expandVideos(); })
    .observe(document.documentElement, {childList:true, subtree:true});

  function runAll() {
    dismissOverlays(); expandVideos(); scanOGTags(); scanPageJSON(); scanDOM();
  }

  dismissOverlays();
  setTimeout(runAll, 300);
  setTimeout(runAll, 800);
  setTimeout(runAll, 2000);
  setTimeout(runAll, 4000);
  setTimeout(runAll, 6000);
  setInterval(dismissOverlays, 800);
  setInterval(scanPageJSON, 1500);
})();
""";

  @override
  void initState() {
    super.initState();
    _platform = MediaExtractorService.detectPlatform(widget.url);
    _initWebView();
  }

  String _prepareUrl(String url) {
    final lo = url.toLowerCase();
    // Instagram: load embed URL — video autoplays, video_url in page JSON
    if (lo.contains('instagram.com') || lo.contains('instagr.am')) {
      final m = RegExp(r'instagram\.com/(?:reel|p|tv)/([A-Za-z0-9_-]+)')
          .firstMatch(url);
      if (m != null) {
        return 'https://www.instagram.com/reel/${m.group(1)}/embed/';
      }
    }
    if (lo.contains('facebook.com') ||
        lo.contains('fb.watch') ||
        lo.contains('fb.com')) {
      // m.facebook.com gives a mobile-optimised layout where videos fill the screen
      // instead of the desktop layout with small centered video card + sidebars
      if (lo.contains('fb.watch')) {
        return 'https://m.facebook.com/watch/?v=${url.split('/').last.split('?').first}';
      }
      if (lo.contains('://fb.com/')) {
        return url.replaceFirst('://fb.com/', '://m.facebook.com/');
      }
      return url
          .replaceFirst('://www.facebook.com', '://m.facebook.com')
          .replaceFirst('://web.facebook.com', '://m.facebook.com');
    }
    return url;
  }

  String? _ytId(String url) {
    for (final p in [
      RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})'),
      RegExp(r'shorts/([a-zA-Z0-9_-]{11})'),
    ]) {
      final m = p.firstMatch(url);
      if (m != null) return m.group(1);
    }
    return null;
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_ua)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('VideoDetector', onMessageReceived: _onDetected)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          setState(() {
            _isLoading = true;
            _loadProgress = 0;
          });
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted) _controller.runJavaScript(_js);
          });
        },
        onProgress: (p) => setState(() => _loadProgress = p / 100.0),
        onPageFinished: (_) {
          setState(() {
            _isLoading = false;
            _loadProgress = 1;
          });
          _controller.runJavaScript(_js);
        },
        onWebResourceError: (e) => print('WV: ${e.description}'),
        onNavigationRequest: (req) {
          if (req.url.startsWith('intent:') || req.url.startsWith('market:')) {
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(_prepareUrl(widget.url)));

    if (_controller.platform is AndroidWebViewController) {
      (_controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
  }

  void _onDetected(JavaScriptMessage msg) {
    try {
      final raw = msg.message;
      final sep = raw.indexOf('|||');
      if (sep < 0) return;
      final score = int.tryParse(raw.substring(0, sep)) ?? 0;
      final url = raw.substring(sep + 3);
      if (url.isEmpty || url.startsWith('blob:')) return;

      if (_bestCandidate == null || score > _bestCandidate!.score) {
        print(
            '🎬 [$_platform/$score] ${url.substring(0, url.length.clamp(0, 100))}');
        setState(() {
          _bestCandidate = _VideoCandidate(url: url, score: score);
          _lastError = null;
        });
        // Auto-download for Instagram AND LinkedIn the moment CDN URL is detected.
        // Both platforms use signed URLs that expire — download immediately.
        if ((_platform == 'instagram' || _platform == 'linkedin') &&
            score >= 350 &&
            !_isDownloading &&
            !_autoDownloadTriggered) {
          _autoDownloadTriggered = true;
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && !_isDownloading) _download();
          });
        }
      }
    } catch (e) {
      print('detect: $e');
    }
  }

  // Referer to send for each CDN type
  String _refererFor(String url) {
    final lo = url.toLowerCase();
    if (lo.contains('cdninstagram.com')) return 'https://www.instagram.com/';
    if (lo.contains('fbcdn.net')) return 'https://www.facebook.com/';
    if (lo.contains('twimg.com')) return 'https://twitter.com/';
    if (lo.contains('licdn.com')) return 'https://www.linkedin.com/';
    if (lo.contains('vimeocdn.com')) return 'https://vimeo.com/';
    return 'https://www.google.com/';
  }

  Map<String, String> _cdnHeaders(String url) {
    final lo = url.toLowerCase();
    if (lo.contains('cdninstagram.com'))
      return {'Referer': 'https://www.instagram.com/'};
    if (lo.contains('fbcdn.net'))
      return {'Referer': 'https://www.facebook.com/'};
    if (lo.contains('video.twimg.com'))
      return {
        'Referer': 'https://twitter.com/',
        'Origin': 'https://twitter.com'
      };
    if (lo.contains('licdn.com'))
      return {
        'Referer': 'https://www.linkedin.com/',
        'Origin': 'https://www.linkedin.com'
      };
    if (lo.contains('vimeocdn.com')) return {'Referer': 'https://vimeo.com/'};
    return {};
  }

  Future<void> _download() async {
    final candidate = _bestCandidate;
    if (candidate == null) return;
    setState(() {
      _isDownloading = true;
      _dlProgress = 0;
      _dlStatus = 'Downloading...';
      _lastError = null;
    });

    try {
      final ext = candidate.url.contains('.webm') ? '.webm' : '.mp4';
      final filename =
          '${_platform}_${DateTime.now().millisecondsSinceEpoch}$ext';
      final dir = Directory('/storage/emulated/0/Download/MediaNest/$_platform');
      await dir.create(recursive: true);
      final savePath = '${dir.path}/$filename';
      final minSize = _platform == 'twitter' ? 50 * 1024 : 80 * 1024;

      // ── Attempt 1: Dart HTTP with CDN headers ─────────────────────────────
      String? result = await MediaExtractorService.downloadFile(
        candidate.url,
        savePath,
        extraHeaders: {
          ..._cdnHeaders(candidate.url),
          'Range': 'bytes=0-',
          'Accept': 'video/mp4,video/webm,video/*;q=0.9,*/*;q=0.5',
        },
        minSizeBytes: minSize,
        onProgress: (p) {
          if (mounted)
            setState(() {
              _dlProgress = p;
              _dlStatus = '${(p * 100).toInt()}%';
            });
        },
        onError: (e) => print('Attempt1: $e'),
      );

      // ── Attempt 2: Native Kotlin download (Android-level WebView cookies) ──
      // Uses HttpURLConnection + CookieManager.getCookie() at the Android level.
      // This gets ALL cookies including HttpOnly ones (sessionid, etc.) which
      // Dart HTTP and JS document.cookie cannot access.
      // This is the key fix for Instagram/LinkedIn CDN authentication.
      if (result == null) {
        if (mounted)
          setState(() => _dlStatus = 'Retrying with native session...');
        try {
          final referer = _refererFor(candidate.url);
          final nativeResult =
              await _cookieChannel.invokeMethod<Map>('nativeDownload', {
            'url': candidate.url,
            'savePath': savePath,
            'referer': referer,
          });
          final success = nativeResult?['success'] as bool? ?? false;
          if (success) {
            result = nativeResult?['path'] as String?;
            print('✅ Native download success');
          } else {
            print('Native download: ${nativeResult?['error']}');
          }
        } catch (e) {
          print('nativeDownload channel: $e');
        }
      }

      // ── Attempt 3 (Instagram): API extraction chain ───────────────────────
      if (result == null && _platform == 'instagram') {
        if (mounted) setState(() => _dlStatus = 'Trying API extraction...');
        try {
          final extracted = await MediaExtractorService().extract(widget.url);
          if (extracted.ok && extracted.url != null) {
            print('✅ API extraction got URL');
            result = await MediaExtractorService.downloadFile(
              extracted.url!,
              savePath,
              minSizeBytes: minSize,
              onProgress: (p) {
                if (mounted)
                  setState(() {
                    _dlProgress = p;
                    _dlStatus = '${(p * 100).toInt()}%';
                  });
              },
              onError: (e) => print('Attempt3: $e'),
            );
          }
        } catch (e) {
          print('API re-extract: $e');
        }
      }

      if (mounted) {
        setState(() => _isDownloading = false);
        if (result != null) {
          final size = await File(result).length();
          _snack('✅ Saved! ${_fmt(size)}');
          // Clear the "Starting download automatically" banner after 3 seconds
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) setState(() => _autoDownloadTriggered = false);
          });
          try {
            Provider.of<MediaProvider>(context, listen: false)
                .refreshAllMedia();
          } catch (_) {}
          try {
            Provider.of<PremiumProvider>(context, listen: false)
                .recordDownload();
          } catch (_) {}
        } else {
          setState(() {
            _autoDownloadTriggered = false;
            _lastError = 'Could not download. Tap DOWNLOAD VIDEO to retry.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _autoDownloadTriggered = false;
          _lastError = 'Error. Tap DOWNLOAD VIDEO to retry.';
        });
      }
    }
  }

  String _fmt(int b) {
    if (b < 1024) return '${b}B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)}KB';
    return '${(b / 1048576).toStringAsFixed(1)}MB';
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? Colors.red.shade300 : Colors.green.shade300,
            size: 18),
        const SizedBox(width: 8),
        Expanded(
            child: Text(msg,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                maxLines: 3)),
      ]),
      backgroundColor: AppColors.textPrimary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 6),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Column(children: [
        _buildActionBar(),
        if (_lastError != null) _buildErrorBanner(),
        Expanded(
            child: Stack(children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: _loadProgress > 0 ? _loadProgress : null,
                  minHeight: 3,
                  backgroundColor: Colors.transparent,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.primary),
                )),
        ])),
      ]),
    );
  }

  Widget _buildActionBar() {
    if (_isDownloading) {
      return Container(
        width: double.infinity,
        decoration: const BoxDecoration(
            gradient:
                LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3D36AA)])),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(children: [
          Row(children: [
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white)),
            const SizedBox(width: 12),
            Expanded(
                child: Text(_dlStatus,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700))),
            Text('${(_dlProgress * 100).toInt()}%',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _dlProgress > 0 ? _dlProgress : null,
                backgroundColor: Colors.white.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                minHeight: 6,
              )),
        ]),
      );
    }

    if (_platform == 'instagram' &&
        _autoDownloadTriggered &&
        _bestCandidate != null) {
      return Container(
        width: double.infinity,
        decoration: const BoxDecoration(
            gradient:
                LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3D36AA)])),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child:
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white)),
          SizedBox(width: 10),
          Text('⚡ Starting download automatically...',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ]),
      );
    }

    if (_bestCandidate != null) {
      return GestureDetector(
        onTap: _download,
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF3D36AA)])),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child:
              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.download_rounded, color: Colors.white, size: 24),
            SizedBox(width: 12),
            Text('DOWNLOAD VIDEO',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5)),
          ]),
        ),
      );
    }

    String hint;
    if (_platform == 'instagram')
      hint = 'Loading video — download starts automatically...';
    else if (_platform == 'facebook')
      hint = 'Tap the video to start playback';
    else if (_platform == 'twitter')
      hint = 'Tap the video thumbnail to play';
    else if (_platform == 'linkedin')
      hint = 'Tap the video to play it';
    else
      hint = 'Play the video to detect it';

    return Container(
      width: double.infinity,
      color: const Color(0xFFF0EEFF),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary)),
        const SizedBox(width: 10),
        Expanded(
            child: Text(hint,
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.center)),
      ]),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.error.withValues(alpha: 0.08),
      child: Row(children: [
        const Icon(Icons.info_outline_rounded,
            color: AppColors.error, size: 16),
        const SizedBox(width: 8),
        Expanded(
            child: Text(_lastError!,
                style: const TextStyle(
                    color: AppColors.error, fontSize: 12, height: 1.4))),
        GestureDetector(
          onTap: () => setState(() => _lastError = null),
          child:
              const Icon(Icons.close_rounded, color: AppColors.error, size: 16),
        ),
      ]),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final titles = {
      'facebook': 'Facebook Download',
      'instagram': 'Instagram Download',
      'twitter': 'Twitter/X Download',
      'tiktok': 'TikTok Download',
      'linkedin': 'LinkedIn Download',
      'vimeo': 'Vimeo Download',
      'dailymotion': 'Dailymotion Download',
    };
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded,
            color: AppColors.textPrimary, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titles[_platform] ?? 'Browser Download',
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        Text(_host(widget.url),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
      ]),
      actions: [
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppColors.textSecondary, size: 20),
          onPressed: () async {
            if (await _controller.canGoBack()) _controller.goBack();
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded,
              color: AppColors.textSecondary, size: 20),
          onPressed: () {
            setState(() {
              _bestCandidate = null;
              _lastError = null;
              _autoDownloadTriggered = false;
            });
            _controller.reload();
          },
        ),
      ],
    );
  }

  String _host(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }
}

class _VideoCandidate {
  final String url;
  final int score;
  _VideoCandidate({required this.url, required this.score});
}
