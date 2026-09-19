// ui/screens/privacy_policy_screen.dart
import 'package:flutter/material.dart';
import '../themes/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Privacy Policy'),
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
            _sectionHeader('Privacy Policy'),
            _paragraph('Last updated: August 2026'),
            const SizedBox(height: 20),
            _paragraph(
              'MediaNest ("the App") is committed to protecting your privacy. This Privacy Policy explains how we handle information when you use our application.',
            ),
            _heading('1. Information MediaNest Handles'),
            _paragraph(
              'MediaNest is designed to keep downloaded and selected media on your device. The app may create an anonymous Firebase authentication identifier so Cloud Vault Pro can associate your files with your installation. This identifier is not used as your name, email, phone number, or advertising profile.',
            ),
            _bullet('Downloaded, edited, and Private Vault files remain on your device unless you explicitly upload them to Cloud Vault Pro'),
            _bullet('The app does not sell personal data or display third-party advertising'),
            _bullet('The app does not use AccessibilityService or overlay access for its core workflow'),
            _bullet('You can delete local files from the app and delete uploaded Cloud Vault Pro files from the cloud screen'),

            _heading('2. Permissions and User Choices'),
            _subheading('MediaStore and system pickers'),
            _paragraph(
              'MediaNest saves its own downloads through Android MediaStore. When you choose a local photo for Quick Editor, or a local photo or video for Private Vault, Android’s system picker gives the app access to that selected item only.',
            ),
            _subheading('WhatsApp Status folder grant'),
            _paragraph(
              'When you open WhatsApp Status, you may choose the WhatsApp Media or .Statuses folder through Android’s system folder picker. MediaNest uses the persisted folder grant to read only image and video files in that selected folder. You can revoke the grant in Android settings at any time.',
            ),
            _subheading('Notifications'),
            _paragraph(
              'Notifications are optional and are requested only if you enable download-completion alerts. Notification content is not uploaded as media data.',
            ),

            _heading('3. Third-Party Services'),
            _paragraph(
              'When you request a download, MediaNest may send the URL you entered to the configured media-extraction service so it can resolve a downloadable media address. Those services process URLs under their own privacy policies. Do not submit private or confidential URLs.',
            ),
            _paragraph(
              'If you use AI Coach or translation features, the text, transcript, or image you submit may be sent to the configured AI or translation provider to produce the requested result. Do not submit information you do not want processed by that provider.',
            ),
            _paragraph(
              'Cloud Vault Pro uses Firebase Authentication, Cloud Firestore, and Firebase Storage to store the files and metadata you explicitly upload. Cloud files can be downloaded or deleted from the Cloud Vault Pro screen.',
            ),

            _heading('4. Media Downloads'),
            _paragraph(
              'MediaNest is designed for downloading media for personal use. You are responsible for ensuring you have the right to download any content. Please respect the terms of service of the social media platforms you use and the intellectual property rights of content creators.',
            ),

            _heading('5. Children\'s Privacy'),
            _paragraph(
              'MediaNest is not directed at children under 13. We do not knowingly collect any information from children.',
            ),

            _heading('6. Data Security and Deletion'),
            _paragraph(
              'Private Vault files are stored in the app’s private storage and protected by the vault PIN or biometric setting available on your device. Cloud Vault Pro files are stored in Firebase services and can be individually deleted from the cloud screen. Uninstalling the app removes its local app data; cloud files remain until you delete them from Cloud Vault Pro or request deletion through the developer contact channel.',
            ),

            _heading('7. Changes to This Policy'),
            _paragraph(
              'We may update this Privacy Policy from time to time. Changes will be reflected in the app update notes. Continued use of the app after updates constitutes acceptance of the revised policy.',
            ),

            _heading('8. Contact'),
            _paragraph(
              'If you have questions about this Privacy Policy, please contact us through the app store page.',
            ),

            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.verified_user_outlined, color: AppColors.success, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'MediaNest has no third-party ads and gives you control over local and cloud media.',
                      style: TextStyle(
                        color: AppColors.success,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
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

  Widget _sectionHeader(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 26,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.5,
      ),
    );
  }

  Widget _heading(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _subheading(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _paragraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: CircleAvatar(
              radius: 3,
              backgroundColor: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
