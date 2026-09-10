import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/premium_provider.dart';
import 'creator_library_screen.dart';
import 'home_screen.dart';
import 'saved_screen.dart';
import 'settings_screen.dart';
import 'whatsapp_status_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({Key? key}) : super(key: key);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  static const _ink = Color(0xFF101326);
  static const _muted = Color(0xFF73798F);
  static const _violet = Color(0xFF7357FF);
  static const _cyan = Color(0xFFDCD4FF);
  static const _canvas = Color(0xFFF4F5FA);

  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    CreatorLibraryScreen(),
    WhatsAppStatusScreen(),
    SavedScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: _canvas,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      extendBody: true,
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _buildDock(),
    );
  }

  Widget _buildDock() {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: _ink,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: _ink.withValues(alpha: 0.24),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            _dockItem(0, Icons.home_rounded, Icons.home_outlined, 'Home'),
            _dockItem(1, Icons.dashboard_rounded, Icons.dashboard_outlined, 'Library'),
            _dockItem(2, Icons.chat_bubble_rounded, Icons.chat_bubble_outline_rounded, 'Status', color: _violet),
            _dockItem(3, Icons.folder_rounded, Icons.folder_outlined, 'Saved'),
            Consumer<PremiumProvider>(
              builder: (_, premium, __) => _dockItem(
                4,
                Icons.tune_rounded,
                Icons.tune_outlined,
                'More',
                badge: premium.isPremium ? 'PRO' : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dockItem(
    int index,
    IconData activeIcon,
    IconData inactiveIcon,
    String label, {
    Color color = _violet,
    String? badge,
  }) {
    final selected = index == _currentIndex;
    final tint = selected ? color : Colors.white54;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentIndex = index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(selected ? activeIcon : inactiveIcon, color: tint, size: 21),
                  if (badge != null)
                    Positioned(
                      top: -8,
                      right: -14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: _cyan, borderRadius: BorderRadius.circular(5)),
                        child: Text(badge, style: const TextStyle(color: _ink, fontSize: 6, fontWeight: FontWeight.w900)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tint,
                  fontSize: 9,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
