class SocialMediaPlatform {
  final String id;
  final String name;
  final String icon;
  final String packageName;
  final bool isSupported;

  const SocialMediaPlatform({
    required this.id,
    required this.name,
    required this.icon,
    required this.packageName,
    this.isSupported = true,
  });
}
