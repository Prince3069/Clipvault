// ui/screens/terms_screen.dart
import 'package:flutter/material.dart';
import '../themes/app_theme.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Terms of Service'),
        backgroundColor: AppColors.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Terms of Service'),
            _paragraph('Last updated: January 2025'),
            const SizedBox(height: 20),
            _paragraph(
              'Welcome to MediaNest. By downloading and using this application, you agree to these Terms of Service. Please read them carefully.',
            ),

            _heading('1. Acceptance of Terms'),
            _paragraph(
              'By using MediaNest, you agree to be bound by these terms. If you do not agree, please do not use the application.',
            ),

            _heading('2. Description of Service'),
            _paragraph(
              'MediaNest is a free media downloading application that allows users to save media from supported social media platforms for personal, offline use. The app uses Cobalt (cobalt.tools), an open-source service, to process media extraction.',
            ),

            _heading('3. Permitted Uses'),
            _paragraph('You may use MediaNest to:'),
            _bullet('Download publicly available media for personal, offline viewing'),
            _bullet('Save WhatsApp status updates shared with you'),
            _bullet('Archive media you have created or own the rights to'),
            _bullet('Download content you have explicit permission to download'),

            _heading('4. Prohibited Uses'),
            _paragraph('You must NOT use MediaNest to:'),
            _bullet('Download copyrighted content without permission from the rights holder'),
            _bullet('Redistribute, sell, or commercially exploit downloaded content'),
            _bullet('Download private content without the owner\'s consent'),
            _bullet('Violate the terms of service of any social media platform'),
            _bullet('Infringe on the intellectual property rights of others'),
            _bullet('Engage in any illegal activity'),

            _heading('5. Intellectual Property'),
            _paragraph(
              'You acknowledge that all content on social media platforms belongs to their respective creators and owners. MediaNest does not claim ownership of any downloaded content. You are solely responsible for ensuring you have the legal right to download any content.',
            ),

            _heading('6. Platform Terms of Service'),
            _paragraph(
              'Using MediaNest to download content may violate the terms of service of the social media platforms whose content you download. You are responsible for understanding and complying with the terms of those platforms.',
            ),

            _heading('7. Disclaimer of Warranties'),
            _paragraph(
              'MediaNest is provided "as is" without warranty of any kind. We do not guarantee that:',
            ),
            _bullet('The app will work with all URLs or platforms at all times'),
            _bullet('Downloads will always be successful'),
            _bullet('The app will be free from bugs or interruptions'),
            _bullet('Third-party services (Cobalt) will remain available'),

            _heading('8. Limitation of Liability'),
            _paragraph(
              'MediaNest and its developers are not liable for any damages arising from your use of the application, including but not limited to: loss of data, infringement claims from third parties, violations of platform terms, or any indirect, incidental, or consequential damages.',
            ),

            _heading('9. Fair Use'),
            _paragraph(
              'This app is intended to support fair use downloading — for personal, offline viewing of content you are entitled to access. Commercial use or redistribution of downloaded content is strictly prohibited.',
            ),

            _heading('10. Changes to Terms'),
            _paragraph(
              'We reserve the right to modify these terms at any time. Continued use of the app after changes are made constitutes acceptance of the new terms.',
            ),

            _heading('11. Governing Law'),
            _paragraph(
              'These terms are governed by applicable law. Any disputes shall be resolved through appropriate legal channels.',
            ),

            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    '⚠️  Important Reminder',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Only download content you have the right to download. Respect content creators and their intellectual property. This app is for personal use only.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) => Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 26,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
        ),
      );

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
      );

  Widget _paragraph(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14, height: 1.6)),
      );

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 7),
              child: CircleAvatar(radius: 3, backgroundColor: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.5)),
            ),
          ],
        ),
      );
}
