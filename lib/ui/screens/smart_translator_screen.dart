// ui/screens/smart_translator_screen.dart
// COMPLETE - Smart Language Translator with video transcription
// Features: Speech-to-Text, Translation, Subtitle Generation, Language Detection
//
// VIDEO TAB — this used to be dead: it accepted a videoPath constructor
// argument and did nothing else, so tapping "Extract & Translate" on a
// screen launched without a path just showed "No video selected". It now
// has a real picker, uploads the chosen video for transcription, and
// translates the resulting transcript. Same pipeline Repurpose Studio
// uses, so a video analyzed once for Repurpose is not re-analyzed here.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
// ignore: depend_on_referenced_packages
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../../services/ai_service.dart';
import '../../providers/premium_provider.dart';
import '../../providers/download_provider.dart';
import '../themes/app_theme.dart';
import '../../services/storage_service.dart';

// ─── Language Model ──────────────────────────────────────────────────────

class Language {
  final String code;
  final String name;
  final String flag;
  final bool isRTL;
  final String? sttLocaleId;

  const Language({
    required this.code,
    required this.name,
    required this.flag,
    this.isRTL = false,
    this.sttLocaleId,
  });

  static const List<Language> supported = [
    Language(code: 'en', name: 'English', flag: '🇺🇸', sttLocaleId: 'en_US'),
    Language(code: 'es', name: 'Spanish', flag: '🇪🇸', sttLocaleId: 'es_ES'),
    Language(code: 'fr', name: 'French', flag: '🇫🇷', sttLocaleId: 'fr_FR'),
    Language(code: 'de', name: 'German', flag: '🇩🇪', sttLocaleId: 'de_DE'),
    Language(code: 'it', name: 'Italian', flag: '🇮🇹', sttLocaleId: 'it_IT'),
    Language(
        code: 'pt', name: 'Portuguese', flag: '🇵🇹', sttLocaleId: 'pt_PT'),
    Language(code: 'ja', name: 'Japanese', flag: '🇯🇵', sttLocaleId: 'ja_JP'),
    Language(code: 'ko', name: 'Korean', flag: '🇰🇷', sttLocaleId: 'ko_KR'),
    Language(code: 'zh', name: 'Chinese', flag: '🇨🇳', sttLocaleId: 'zh_CN'),
    Language(
        code: 'ar',
        name: 'Arabic',
        flag: '🇸🇦',
        isRTL: true,
        sttLocaleId: 'ar_SA'),
    Language(code: 'hi', name: 'Hindi', flag: '🇮🇳', sttLocaleId: 'hi_IN'),
    Language(code: 'ru', name: 'Russian', flag: '🇷🇺', sttLocaleId: 'ru_RU'),
    Language(code: 'nl', name: 'Dutch', flag: '🇳🇱', sttLocaleId: 'nl_NL'),
    Language(code: 'tr', name: 'Turkish', flag: '🇹🇷', sttLocaleId: 'tr_TR'),
    Language(
        code: 'id', name: 'Indonesian', flag: '🇮🇩', sttLocaleId: 'id_ID'),
    Language(code: 'ms', name: 'Malay', flag: '🇲🇾', sttLocaleId: 'ms_MY'),
    Language(code: 'th', name: 'Thai', flag: '🇹🇭', sttLocaleId: 'th_TH'),
    Language(
        code: 'vi', name: 'Vietnamese', flag: '🇻🇳', sttLocaleId: 'vi_VN'),
    Language(code: 'pl', name: 'Polish', flag: '🇵🇱', sttLocaleId: 'pl_PL'),
    Language(code: 'uk', name: 'Ukrainian', flag: '🇺🇦', sttLocaleId: 'uk_UA'),
  ];

  static Language? fromCode(String code) {
    return supported.firstWhere((l) => l.code == code,
        orElse: () => supported.first);
  }
}

// ─── Screen ──────────────────────────────────────────────────────────────

class SmartTranslatorScreen extends StatefulWidget {
  final String? videoPath;
  final String? videoTitle;
  final String? initialText;

  const SmartTranslatorScreen({
    Key? key,
    this.videoPath,
    this.videoTitle,
    this.initialText,
  }) : super(key: key);

  @override
  State<SmartTranslatorScreen> createState() => _SmartTranslatorScreenState();
}

class _SmartTranslatorScreenState extends State<SmartTranslatorScreen>
    with SingleTickerProviderStateMixin {
  // ─── Services ──────────────────────────────────────────────────────────
  final AIService _ai = AIService();
  final StorageService _storage = StorageService();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final ImagePicker _imagePicker = ImagePicker();

  // ─── State ─────────────────────────────────────────────────────────────
  bool _isInitialized = false;
  bool _isListening = false;
  bool _isProcessing = false;
  String _transcript = '';
  String _translation = '';
  String _detectedLanguage = 'en';
  bool _showTranslation = false;
  String _error = '';
  double _progress = 0.0;
  String _status = '';

  // ─── Video state ──────────────────────────────────────────────────────
  String? _pickedVideoPath;
  String? _pickedVideoTitle;
  bool _isPickingVideo = false;
  bool _transcriptTruncated = false;

  // ─── Language Selection ──────────────────────────────────────────────
  Language _sourceLanguage = Language.supported.first;
  Language _targetLanguage = Language.supported.firstWhere(
    (l) => l.code == 'es',
    orElse: () => Language.supported[1],
  );

  // ─── Text input ───────────────────────────────────────────────────────
  late final TextEditingController _textController;

  // ─── Animation ────────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ─── Tabs ─────────────────────────────────────────────────────────────
  int _selectedTab = 0; // 0: Text, 1: Speech, 2: Video

  /// Server-side cap on /translateText — see functions/index.js. Chunking
  /// here would produce fragmented translations that read badly when
  /// stitched; truncating at a sentence boundary and being upfront about
  /// it is more honest than silently translating part of the video.
  static const int _maxTranslateChars = 4000;
  static const int _softTranslateChars = 3800; // leave headroom for "…"

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText ?? '');
    _transcript = widget.initialText ?? '';
    _pickedVideoPath = widget.videoPath;
    _pickedVideoTitle = widget.videoTitle;
    _initSpeech();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (_transcript.trim().isNotEmpty) {
      _detectLanguage();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<PremiumProvider>(context, listen: false)
            .refreshCreditBalance();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _textController.dispose();
    _speech.stop();
    super.dispose();
  }

  // ─── Initialization ─────────────────────────────────────────────────

  Future<void> _initSpeech() async {
    try {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        setState(() => _error = micStatus.isPermanentlyDenied
            ? 'Microphone access is turned off for this app. Enable it in '
                'Settings → Apps → ClipVault → Permissions.'
            : 'Microphone permission is needed for speech input.');
        return;
      }

      _isInitialized = await _speech.initialize(
        onError: (error) {
          setState(() => _error = error.errorMsg ?? 'Speech recognition error');
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
      );
      if (!_isInitialized) {
        setState(() => _error = 'Speech recognition not available on this '
            'device. Make sure Google app / Google Speech Services is '
            'installed and enabled.');
      }
    } catch (e) {
      setState(() => _error = 'Failed to initialize speech: $e');
    }
  }

  // ─── Language Detection ──────────────────────────────────────────────

  Future<void> _detectLanguage() async {
    if (_transcript.isEmpty) return;

    final isPremium =
        Provider.of<PremiumProvider>(context, listen: false).isPremium;
    if (!isPremium) return;

    setState(() {
      _isProcessing = true;
      _status = 'Detecting language...';
    });

    try {
      final detected = await _ai.detectLanguage(_transcript);
      setState(() {
        _detectedLanguage = detected;
        _sourceLanguage =
            Language.fromCode(detected) ?? Language.supported.first;
        _isProcessing = false;
        _status = '';
      });
    } catch (e) {
      setState(() {
        _error = 'Language detection failed: $e';
        _isProcessing = false;
      });
    }
  }

  // ─── Speech Recognition ──────────────────────────────────────────────

  Future<void> _startListening() async {
    if (!_isInitialized) {
      setState(() => _error = 'Speech not initialized');
      return;
    }

    final isPremium =
        Provider.of<PremiumProvider>(context, listen: false).isPremium;
    if (!isPremium) {
      _showPremiumDialog();
      return;
    }

    _textController.clear();
    setState(() {
      _isListening = true;
      _transcript = '';
      _translation = '';
      _error = '';
      _showTranslation = false;
    });

    try {
      await _speech.listen(
        onResult: (result) {
          _textController.value = _textController.value.copyWith(
            text: result.recognizedWords,
            selection: TextSelection.collapsed(
              offset: result.recognizedWords.length,
            ),
            composing: TextRange.empty,
          );
          setState(() {
            _transcript = result.recognizedWords;
            if (result.finalResult) {
              _isListening = false;
              _detectLanguage();
            }
          });
        },
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 5),
        partialResults: true,
        // Use the SOURCE language's locale — hardcoding en_US broke every
        // non-English speaker. This maps the picker selection through to
        // the recognizer; when a language has no sttLocaleId, fall back
        // to the platform default so behavior is no worse than before.
        localeId: _sourceLanguage.sttLocaleId ?? 'en_US',
      );
    } catch (e) {
      setState(() {
        _error = 'Listening failed: $e';
        _isListening = false;
      });
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  // ─── Translation ─────────────────────────────────────────────────────

  Future<void> _translate() async {
    if (_transcript.trim().isEmpty) {
      setState(() => _error = 'No text to translate');
      return;
    }
    if (_sourceLanguage.code == _targetLanguage.code) {
      setState(
          () => _error = 'Choose a different target language to translate.');
      return;
    }

    final isPremium =
        Provider.of<PremiumProvider>(context, listen: false).isPremium;

    // Server caps input at 4000 chars. A 10-minute video transcript can
    // easily exceed that, so trim at a sentence boundary rather than
    // silently failing on the server — and tell the user, so the result
    // isn't mistaken for a complete translation.
    String textToTranslate = _transcript;
    bool truncated = false;
    if (textToTranslate.length > _maxTranslateChars) {
      final cut = textToTranslate.substring(0, _softTranslateChars);
      final lastStop = cut.lastIndexOf(RegExp(r'[.!?。！？]\s'));
      textToTranslate =
          (lastStop > 200 ? cut.substring(0, lastStop + 1) : cut).trimRight();
      truncated = true;
    }

    setState(() {
      _isProcessing = true;
      _status = 'Translating...';
      _error = '';
      _translation = '';
      _showTranslation = false;
      _progress = 0.0;
      _transcriptTruncated = truncated;
    });

    try {
      for (int i = 0; i <= 10; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) setState(() => _progress = i / 10);
      }

      final translation = await _ai.translateText(
        text: textToTranslate,
        targetLanguage: _targetLanguage.code,
        sourceLanguage: _sourceLanguage.code,
      );

      setState(() {
        _translation = translation;
        _showTranslation = true;
        _isProcessing = false;
        _status = '';
        _progress = 1.0;
      });

      if (mounted) {
        Provider.of<PremiumProvider>(context, listen: false)
            .refreshCreditBalance();
      }

      await _ai.trackEvent('translation_completed', properties: {
        'source': _sourceLanguage.code,
        'target': _targetLanguage.code,
        'text_length': textToTranslate.length,
        'truncated': truncated,
        'is_premium': isPremium,
      });
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _error = message;
        _translation = '';
        _showTranslation = false;
        _isProcessing = false;
        _status = '';
      });
      if (mounted) {
        Provider.of<PremiumProvider>(context, listen: false)
            .refreshCreditBalance();
      }
    }
  }

  // ─── Video Picking & Extraction ─────────────────────────────────────

  /// Requests Android/iOS media permissions before launching the picker.
  /// image_picker on Android 13+ normally uses the system Photo Picker
  /// (no permission needed) — but on many OEM builds (Xiaomi, Realme,
  /// Tecno, Infinix, Samsung One UI etc.) it silently falls back to
  /// ACTION_GET_CONTENT, which returns null when media read is denied.
  /// That's the exact bug this is here to prevent.
  Future<bool> _ensureMediaPermission({required bool forVideo}) async {
    if (!Platform.isAndroid) return true; // iOS handled by Info.plist prompt

    try {
      // Android 13+ modern permission first.
      final modern = forVideo ? Permission.videos : Permission.photos;
      if (await modern.isGranted) return true;
      var s = await modern.request();
      if (s.isGranted || s.isLimited) return true;

      // Fall back to legacy storage permission for Android 12 and below
      // (also covers devices where the modern permission type is a no-op).
      if (await Permission.storage.isGranted) return true;
      s = await Permission.storage.request();
      return s.isGranted;
    } catch (_) {
      return true;
    }
  }

  Future<void> _pickVideoFromDevice() async {
    if (_isPickingVideo) return;
    setState(() {
      _isPickingVideo = true;
      _error = '';
    });

    try {
      final ok = await _ensureMediaPermission(forVideo: true);
      if (!ok) {
        if (mounted) {
          setState(() {
            _isPickingVideo = false;
            _error = 'Media access is required to choose a video. Enable '
                'it in Settings → Apps → MediaNest → Permissions.';
          });
        }
        return;
      }

      final XFile? picked = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 10),
      );

      if (!mounted) return;

      if (picked == null) {
        // Two possible reasons: user cancelled, or the picker silently
        // failed. We can't distinguish them, but the second case is the
        // real bug users hit — surface a helpful message either way.
        setState(() {
          _isPickingVideo = false;
          _error = 'No video selected. If the picker didn\'t open, check '
              'that MediaNest has permission to access videos.';
        });
        return;
      }

      setState(() {
        _pickedVideoPath = picked.path;
        _pickedVideoTitle = picked.name;
        _isPickingVideo = false;
        _error = '';
      });
    } catch (e) {
      debugPrint('Pick video error: $e');
      if (mounted) {
        setState(() {
          _isPickingVideo = false;
          _error = 'Could not open the picker: $e';
        });
      }
    }
  }

  Future<void> _extractFromVideo() async {
    final path = _pickedVideoPath;
    if (path == null || path.isEmpty) {
      setState(() => _error = 'Choose a video first');
      return;
    }

    final isPremium =
        Provider.of<PremiumProvider>(context, listen: false).isPremium;
    if (!isPremium) {
      _showPremiumDialog();
      return;
    }

    setState(() {
      _isProcessing = true;
      _status = 'Uploading video for transcription...';
      _error = '';
      _progress = 0.0;
      _transcript = '';
      _translation = '';
      _showTranslation = false;
      _transcriptTruncated = false;
    });

    try {
      // Fake progress during the (unprogressable) upload+transcribe step.
      // The real signal is the analyzeVideoFileFull() return, not these
      // ticks — this exists only so the UI isn't frozen on "0%".
      _tickProgress();

      final result = await _ai.analyzeVideoFileFull(path);

      if (!mounted) return;

      if (result == null) {
        setState(() {
          _isProcessing = false;
          _progress = 0;
          _status = '';
          _error = 'Could not analyze this video. It may be too large '
              '(over 24MB), a format the analyzer can\'t read, or the '
              'upload was interrupted.';
        });
        return;
      }

      final transcript = (result['transcript'] as String?)?.trim() ?? '';
      if (transcript.isEmpty) {
        setState(() {
          _isProcessing = false;
          _progress = 1.0;
          _status = '';
          _error = 'No speech detected in this video — nothing to '
              'translate. If it has voiceover, check that the audio '
              'isn\'t muted.';
        });
        return;
      }

      setState(() {
        _transcript = transcript;
        _textController.text = transcript;
        _isProcessing = false;
        _progress = 1.0;
        _status = '';
      });

      await _ai.trackEvent('video_transcription', properties: {
        'video_title': _pickedVideoTitle ?? 'unknown',
        'transcript_length': transcript.length,
        'is_premium': isPremium,
      });

      if (mounted) {
        Provider.of<PremiumProvider>(context, listen: false)
            .refreshCreditBalance();
      }
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _error = message;
        _isProcessing = false;
        _status = '';
      });
    }
  }

  /// Animates _progress up to ~0.9 while the real work happens, then
  /// stops. _extractFromVideo jumps it to 1.0 on success.
  void _tickProgress() {
    Future<void> ticker() async {
      for (int i = 0; i < 18; i++) {
        await Future.delayed(const Duration(milliseconds: 400));
        if (!mounted || !_isProcessing) return;
        if (_progress >= 0.9) return;
        setState(() {
          _progress += 0.05;
          if (_progress < 0.3) {
            _status = 'Uploading video...';
          } else if (_progress < 0.7) {
            _status = 'Transcribing speech...';
          } else {
            _status = 'Almost done...';
          }
        });
      }
    }

    ticker();
  }

  // ─── Export Functions ────────────────────────────────────────────────

  Future<void> _exportTranslation() async {
    if (_translation.isEmpty && _transcript.isEmpty) {
      setState(() => _error = 'Nothing to export');
      return;
    }

    try {
      final content = _showTranslation
          ? 'Original (${_sourceLanguage.name}):\n$_transcript\n\n'
              'Translation (${_targetLanguage.name}):\n$_translation'
          : 'Transcript (${_sourceLanguage.name}):\n$_transcript';

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'translation_$timestamp.txt';
      final path = await _storage.getPlatformDownloadPath('Translations');
      final fullPath = '$path/$fileName';

      final file = File(fullPath);
      await file.writeAsString(content);

      await _storage.scanMediaFile(fullPath);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Saved to $fileName'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      setState(() => _error = 'Export failed: $e');
    }
  }

  Future<void> _exportSubtitles() async {
    if (_translation.isEmpty && _transcript.isEmpty) {
      setState(() => _error = 'No content to export');
      return;
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'subtitles_$timestamp.srt';
      final path = await _storage.getPlatformDownloadPath('Subtitles');
      final fullPath = '$path/$fileName';

      final content = _generateSRT();
      final file = File(fullPath);
      await file.writeAsString(content);

      await _storage.scanMediaFile(fullPath);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Subtitles saved to $fileName'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      setState(() => _error = 'Subtitle export failed: $e');
    }
  }

  String _generateSRT() {
    final text = _showTranslation ? _translation : _transcript;
    final lines = text.split(RegExp(r'[\n.!?]+'));
    final srt = StringBuffer();

    var i = 0;
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      srt.writeln(i + 1);
      srt.writeln('00:00:${(i * 3).toString().padLeft(2, '0')},000 --> '
          '00:00:${((i + 1) * 3).toString().padLeft(2, '0')},000');
      srt.writeln(line);
      srt.writeln();
      i++;
    }

    return srt.toString();
  }

  // ─── Dialogs ─────────────────────────────────────────────────────────

  void _showPremiumDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Icon(
                Icons.workspace_premium_rounded,
                color: AppColors.primary,
                size: 48,
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Video Transcription',
                style: AppTypography.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Extract and translate audio from videos with AI.',
                style: AppTypography.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Upgrade to Pro'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Maybe Later'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguageSelector(bool isSource) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                isSource ? 'Select Source Language' : 'Select Target Language',
                style: AppTypography.headlineMedium,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: ListView.builder(
                itemCount: Language.supported.length,
                itemBuilder: (context, index) {
                  final lang = Language.supported[index];
                  final isSelected = isSource
                      ? lang.code == _sourceLanguage.code
                      : lang.code == _targetLanguage.code;
                  return ListTile(
                    leading:
                        Text(lang.flag, style: const TextStyle(fontSize: 24)),
                    title: Text(
                      lang.name,
                      style: TextStyle(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    subtitle: Text(
                      lang.code.toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle_rounded,
                            color: AppColors.primary)
                        : null,
                    onTap: () {
                      setState(() {
                        if (isSource) {
                          _sourceLanguage = lang;
                          _detectedLanguage = lang.code;
                        } else {
                          _targetLanguage = lang;
                        }
                        _showTranslation = false;
                      });
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── UI ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(),
      body: _buildContent(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: const Row(
        children: [
          Icon(
            Icons.translate_rounded,
            color: AppColors.primary,
            size: 20,
          ),
          SizedBox(width: AppSpacing.sm),
          Text('Smart Translator'),
        ],
      ),
      actions: [
        Consumer<PremiumProvider>(
          builder: (_, premium, __) {
            final String? label;
            if (premium.isPremium) {
              final credits = premium.remainingCredits;
              label = credits == null ? null : '$credits credits';
            } else {
              final remaining = premium.freeTranslationsRemaining;
              label = remaining == null
                  ? null
                  : (remaining > 0 ? '$remaining free left' : 'Free used up');
            }
            if (label == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: premium.isPremium
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: premium.isPremium
                        ? AppColors.primary
                        : AppColors.warning,
                  ),
                ),
              ),
            );
          },
        ),
        if (_transcript.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.content_copy_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _transcript));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        _buildTabs(),
        Expanded(
          child: IndexedStack(
            index: _selectedTab,
            children: [
              _buildTextTab(),
              _buildSpeechTab(),
              _buildVideoTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          _buildTab('Text', 0, Icons.text_fields_rounded),
          _buildTab('Speech', 1, Icons.mic_rounded),
          _buildTab('Video', 2, Icons.videocam_rounded),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index, IconData icon) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : AppColors.textMuted,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Tab: Text ─────────────────────────────────────────────────────────

  Widget _buildTextTab() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          _buildLanguageSelector(),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.borderLight),
                boxShadow: AppShadows.soft,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        const Text(
                          'Source Text',
                          style: AppTypography.titleMedium,
                        ),
                        const Spacer(),
                        if (_transcript.isNotEmpty)
                          Text(
                            '${_transcript.split(' ').length} words',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: TextField(
                      maxLines: null,
                      decoration: const InputDecoration(
                        hintText: 'Paste text to translate...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(AppSpacing.md),
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: AppColors.textPrimary,
                      ),
                      textDirection: _sourceLanguage.isRTL
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      textAlign: _sourceLanguage.isRTL
                          ? TextAlign.right
                          : TextAlign.left,
                      onChanged: (value) {
                        setState(() {
                          _transcript = value;
                          _showTranslation = false;
                          _translation = '';
                        });
                        if (value.trim().length > 10) {
                          _detectLanguage();
                        }
                      },
                      controller: _textController,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _translate,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.translate_rounded, size: 18),
                  label: Text(_isProcessing ? 'Translating...' : 'Translate'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (_translation.isNotEmpty)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _exportTranslation,
                    icon: const Icon(Icons.save_rounded, size: 18),
                    label: const Text('Export'),
                  ),
                ),
            ],
          ),
          if (_showTranslation && _translation.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _buildTranslationResult(),
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _buildErrorBox(),
          ],
        ],
      ),
    );
  }

  Widget _buildTranslationResult() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 16,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Translation (${_targetLanguage.name})',
                  style: AppTypography.titleMedium,
                ),
              ),
              IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _translation));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Translation copied'),
                      backgroundColor: AppColors.success,
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          if (_transcriptTruncated) ...[
            const SizedBox(height: 4),
            const Text(
              'Showing first ~3800 characters only.',
              style: TextStyle(color: AppColors.warning, fontSize: 11),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            _translation,
            style: const TextStyle(
              fontSize: 16,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
          ),
          if (_targetLanguage.isRTL) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.info,
                    size: 14,
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Text(
                    'Right-to-Left language detected',
                    style: TextStyle(
                      color: AppColors.info,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorBox() {
    if (_error.toLowerCase().contains('free translation')) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text(
                    'That was your free translation for this month',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontSize: 13,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _error = ''),
                  child: const Icon(Icons.close_rounded,
                      color: AppColors.primary, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Go Pro for unlimited translation, or wait until next '
              'month for another free one.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _showPremiumDialog,
                child: const Text('Upgrade to Pro'),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
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
            child: Text(
              _error,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _error = ''),
            child: const Icon(Icons.close_rounded,
                color: AppColors.error, size: 16),
          ),
        ],
      ),
    );
  }

  // ─── Tab: Speech ──────────────────────────────────────────────────────

  Widget _buildSpeechTab() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          _buildLanguageSelector(),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.borderLight),
                boxShadow: AppShadows.soft,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        const Text(
                          'Speech Recognition',
                          style: AppTypography.titleMedium,
                        ),
                        const Spacer(),
                        if (_isListening)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppColors.error,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'Listening...',
                                  style: TextStyle(
                                    color: AppColors.error,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        _transcript.isEmpty
                            ? 'Tap the mic button and speak...'
                            : _transcript,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: _transcript.isEmpty
                              ? AppColors.textMuted
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  if (_isProcessing) ...[
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _progress > 0 ? _progress : null,
                          backgroundColor: AppColors.border,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.primary),
                          minHeight: 4,
                        ),
                      ),
                    ),
                    Text(
                      _status,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _isListening ? _stopListening : _startListening,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isListening ? AppColors.error : AppColors.primary,
                    boxShadow: [
                      BoxShadow(
                        color:
                            (_isListening ? AppColors.error : AppColors.primary)
                                .withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (_transcript.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _translate,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.translate_rounded, size: 18),
                    label: Text(_isProcessing ? 'Translating...' : 'Translate'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (_translation.isNotEmpty)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _exportTranslation,
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: const Text('Export'),
                    ),
                  ),
              ],
            ),
          if (_showTranslation && _translation.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _buildTranslationResult(),
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _buildErrorBox(),
          ],
        ],
      ),
    );
  }

  // ─── Tab: Video ──────────────────────────────────────────────────────

  Widget _buildVideoTab() {
    final hasVideo = _pickedVideoPath != null && _pickedVideoPath!.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          _buildLanguageSelector(),
          const SizedBox(height: AppSpacing.md),

          // Video slot — shows selected video or invites selection
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.borderLight),
              boxShadow: AppShadows.soft,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Icon(
                    Icons.videocam_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasVideo
                            ? (_pickedVideoTitle ?? 'Selected video')
                            : 'No video selected',
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        hasVideo
                            ? 'Ready to extract and translate'
                            : 'Choose a video to extract its speech',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasVideo)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Text(
                      'Ready',
                      style: TextStyle(
                        color: AppColors.success,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Choose video button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isPickingVideo ? null : _pickVideoFromDevice,
              icon: _isPickingVideo
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.video_library_rounded, size: 18),
              label: Text(
                hasVideo ? 'Choose a different video' : 'Choose a video',
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          // Extract & Translate button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  (_isProcessing || !hasVideo) ? null : _extractFromVideo,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_circle_rounded, size: 18),
              label: Text(_isProcessing
                  ? (_status.isEmpty ? 'Processing...' : _status)
                  : 'Extract & Translate'),
            ),
          ),

          if (_isProcessing) ...[
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: AppColors.border,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.primary),
                minHeight: 6,
              ),
            ),
          ],

          if (_transcript.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Transcript',
                        style: AppTypography.titleMedium,
                      ),
                      const Spacer(),
                      Text(
                        _detectedLanguage.toUpperCase(),
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      child: Text(
                        _transcript,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing ? null : _translate,
                          icon: const Icon(Icons.translate_rounded, size: 16),
                          label: const Text('Translate'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: _exportSubtitles,
                        icon:
                            const Icon(Icons.closed_caption_rounded, size: 16),
                        label: const Text('SRT'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          if (_showTranslation && _translation.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _buildTranslationResult(),
          ],

          if (_error.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _buildErrorBox(),
          ],

          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  // ─── Language Selector ──────────────────────────────────────────────

  Widget _buildLanguageSelector() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _showLanguageSelector(true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _sourceLanguage.flag,
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _sourceLanguage.code.toUpperCase(),
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Icon(
                      Icons.arrow_drop_down_rounded,
                      color: AppColors.textMuted,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                final temp = _sourceLanguage;
                _sourceLanguage = _targetLanguage;
                _targetLanguage = temp;
                _detectedLanguage = _sourceLanguage.code;
                _showTranslation = false;
                _translation = '';
              });
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              child: const Icon(
                Icons.swap_horiz_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _showLanguageSelector(false),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _targetLanguage.flag,
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _targetLanguage.code.toUpperCase(),
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Icon(
                      Icons.arrow_drop_down_rounded,
                      color: AppColors.textMuted,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
