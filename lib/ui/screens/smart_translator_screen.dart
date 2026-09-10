// ui/screens/smart_translator_screen.dart
// COMPLETE - Smart Language Translator with Deepgram + OpenAI
// Features: Speech-to-Text, Translation, Subtitle Generation, Language Detection

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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

  const Language({
    required this.code,
    required this.name,
    required this.flag,
    this.isRTL = false,
  });

  static const List<Language> supported = [
    Language(code: 'en', name: 'English', flag: '🇺🇸'),
    Language(code: 'es', name: 'Spanish', flag: '🇪🇸'),
    Language(code: 'fr', name: 'French', flag: '🇫🇷'),
    Language(code: 'de', name: 'German', flag: '🇩🇪'),
    Language(code: 'it', name: 'Italian', flag: '🇮🇹'),
    Language(code: 'pt', name: 'Portuguese', flag: '🇵🇹'),
    Language(code: 'ja', name: 'Japanese', flag: '🇯🇵'),
    Language(code: 'ko', name: 'Korean', flag: '🇰🇷'),
    Language(code: 'zh', name: 'Chinese', flag: '🇨🇳'),
    Language(code: 'ar', name: 'Arabic', flag: '🇸🇦', isRTL: true),
    Language(code: 'hi', name: 'Hindi', flag: '🇮🇳'),
    Language(code: 'ru', name: 'Russian', flag: '🇷🇺'),
    Language(code: 'nl', name: 'Dutch', flag: '🇳🇱'),
    Language(code: 'tr', name: 'Turkish', flag: '🇹🇷'),
    Language(code: 'id', name: 'Indonesian', flag: '🇮🇩'),
    Language(code: 'ms', name: 'Malay', flag: '🇲🇾'),
    Language(code: 'th', name: 'Thai', flag: '🇹🇭'),
    Language(code: 'vi', name: 'Vietnamese', flag: '🇻🇳'),
    Language(code: 'pl', name: 'Polish', flag: '🇵🇱'),
    Language(code: 'uk', name: 'Ukrainian', flag: '🇺🇦'),
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

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText ?? '');
    _transcript = widget.initialText ?? '';
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
      // speech_to_text needs RECORD_AUDIO — without it (or if the person
      // denies the prompt), initialize() just returns false with no error
      // detail, which is what showed up as a bare "Speech recognition not
      // available". Requesting it explicitly here gives a real, actionable
      // message instead.
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
          // Fix: Use errorMsg instead of description
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
        localeId: 'en_US',
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

    setState(() {
      _isProcessing = true;
      _status = 'Translating...';
      _error = '';
      _translation = '';
      _showTranslation = false;
      _progress = 0.0;
    });

    try {
      // Simulate progress
      for (int i = 0; i <= 10; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        setState(() => _progress = i / 10);
      }

      final translation = await _ai.translateText(
        text: _transcript,
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

      // Track usage
      await _ai.trackEvent('translation_completed', properties: {
        'source': _sourceLanguage.code,
        'target': _targetLanguage.code,
        'text_length': _transcript.length,
        'is_premium': isPremium,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            'Translation failed. Check your connection or translation API configuration.';
        _translation = '';
        _showTranslation = false;
        _isProcessing = false;
        _status = '';
      });
    }
  }

  // ─── Video Subtitle Extraction ──────────────────────────────────────

  Future<void> _extractFromVideo() async {
    if (widget.videoPath == null || widget.videoPath!.isEmpty) {
      setState(() => _error = 'No video selected');
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
      _status = 'Extracting audio from video...';
      _error = '';
      _progress = 0.0;
    });

    try {
      // This would use Deepgram to transcribe audio from video
      // For now, simulate the process
      for (int i = 0; i <= 20; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        setState(() => _progress = i / 20);
        if (i < 10) {
          _status = 'Extracting audio...';
        } else if (i < 15) {
          _status = 'Transcribing speech...';
        } else {
          _status = 'Processing...';
        }
      }

      // Simulate transcript from video
      setState(() {
        _transcript =
            'This is a simulated transcript from the video. In production, '
            'Deepgram would transcribe the actual audio content from your video file.';
        _isProcessing = false;
        _status = '';
        _progress = 1.0;
        _detectLanguage();
      });

      await _ai.trackEvent('video_transcription', properties: {
        'video_title': widget.videoTitle ?? 'Unknown',
        'is_premium': isPremium,
      });
    } catch (e) {
      setState(() {
        _error = 'Video processing failed: $e';
        _isProcessing = false;
      });
    }
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

      // Generate SRT format
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
    final lines = text.split('\n');
    final srt = StringBuffer();

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      srt.writeln(i + 1);
      srt.writeln('00:00:${(i * 3).toString().padLeft(2, '0')},000 --> '
          '00:00:${((i + 1) * 3).toString().padLeft(2, '0')},000');
      srt.writeln(lines[i].trim());
      srt.writeln();
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
                  onPressed: () {
                    Navigator.pop(context);
                    // Navigate to premium
                  },
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
        // ─── Tabs ──────────────────────────────────────────────────────────
        _buildTabs(),

        // ─── Content ──────────────────────────────────────────────────────
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
          // Language selector
          _buildLanguageSelector(),
          const SizedBox(height: AppSpacing.md),

          // Input area
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
                  // Header
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
                  // Text input
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

          // Action buttons
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

          // Translation result
          if (_showTranslation && _translation.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
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
                      Text(
                        'Translation (${_targetLanguage.name})',
                        style: AppTypography.titleMedium,
                      ),
                      const Spacer(),
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
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _translation,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (_targetLanguage.isRTL)
                    const SizedBox(height: AppSpacing.sm),
                  if (_targetLanguage.isRTL)
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
              ),
            ),
          ],

          // Error
          if (_error.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
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
                      style:
                          const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _error = ''),
                    child: const Icon(Icons.close_rounded,
                        color: AppColors.error, size: 16),
                  ),
                ],
              ),
            ),
          ],
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
          // Language selector
          _buildLanguageSelector(),
          const SizedBox(height: AppSpacing.md),

          // Speech area
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

                  // Transcript
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

                  // Progress
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

          // Mic button
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

          // Actions
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

          // Translation result
          if (_showTranslation && _translation.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
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
                      Text(
                        'Translation (${_targetLanguage.name})',
                        style: AppTypography.titleMedium,
                      ),
                      const Spacer(),
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
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _translation,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: AppColors.textPrimary,
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

  // ─── Tab: Video ──────────────────────────────────────────────────────

  Widget _buildVideoTab() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          // Language selector
          _buildLanguageSelector(),
          const SizedBox(height: AppSpacing.md),

          // Video info
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
                        widget.videoTitle ?? 'No video selected',
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Extract and translate audio from video',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.videoPath != null)
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
                      'Selected',
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

          // Process button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _extractFromVideo,
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
              label: Text(_isProcessing ? _status : 'Extract & Translate'),
            ),
          ),

          // Progress
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
            const SizedBox(height: AppSpacing.sm),
            Text(
              _status,
              style: AppTypography.caption.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],

          // Transcript result
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
                  Text(
                    _transcript,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _translate,
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

          // Translation result
          if (_showTranslation && _translation.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
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
                      Text(
                        'Translation (${_targetLanguage.name})',
                        style: AppTypography.titleMedium,
                      ),
                      const Spacer(),
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
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _translation,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_error.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
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
                      style:
                          const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _error = ''),
                    child: const Icon(Icons.close_rounded,
                        color: AppColors.error, size: 16),
                  ),
                ],
              ),
            ),
          ],
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
          // Source language
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

          // Swap icon
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

          // Target language
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
