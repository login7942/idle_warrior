import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui';

class UpdateService {
  // 실제 배포 서버의 version.json URL
  static const String versionUrl = 'https://raw.githubusercontent.com/login7942/idle_warrior/main/version.json';

  static Future<void> checkUpdate(BuildContext context) async {
    try {
      // 1. 현재 앱 버전 정보 가져오기
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;
      int currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      // 2. 서버에서 최신 버전 정보 가져오기
      final response = await http.get(Uri.parse(versionUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String latestVersion = data['version'];
        int latestBuildNumber = data['buildNumber'] ?? 0;
        String downloadUrl = data['downloadUrl'];
        String changelog = data['changelog'] ?? '새로운 버전이 출시되었습니다.';

        // 3. 버전 비교 (빌드 번호 또는 버전 명칭 기준)
        if (latestBuildNumber > currentBuildNumber || _isNewerVersion(latestVersion, currentVersion)) {
          if (context.mounted) {
            _showUpdateDialog(context, latestVersion, downloadUrl, changelog);
          }
        }
      }
    } catch (e) {
      debugPrint('최신 버전 확인 실패: $e');
    }
  }

  static bool _isNewerVersion(String latest, String current) {
    List<int> latestParts = latest.split('.').map(int.parse).toList();
    List<int> currentParts = current.split('.').map(int.parse).toList();

    for (int i = 0; i < latestParts.length && i < currentParts.length; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return latestParts.length > currentParts.length;
  }

  static void _showUpdateDialog(BuildContext context, String version, String url, String changelog) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.system_update, color: Colors.blueAccent, size: 48),
                const SizedBox(height: 16),
                Text(
                  '새로운 버전 발견! (v$version)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    changelog,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        '나중에',
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final uri = Uri.parse(url);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: const Text('지금 업데이트'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
