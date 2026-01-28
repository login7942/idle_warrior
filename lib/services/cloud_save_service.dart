import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 클라우드 세이브 서비스 - Supabase를 통한 데이터 저장/로드
class CloudSaveService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  /// 클라우드에 저장
  Future<bool> saveToCloud(Map<String, dynamic> gameData) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[CloudSave] 저장 실패: 사용자 미로그인');
        return false;
      }
      
      // 현재 앱 버전 정보 가져오기
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      
      await _supabase.from('player_saves').upsert({
        'user_id': userId,
        'save_data': gameData,
        'version': currentVersion,
        'last_saved_at': DateTime.now().toIso8601String(),
        'device_info': 'Flutter App',
      }, onConflict: 'user_id'); // 🆕 user_id가 겹치면 업데이트하도록 명시
      
      debugPrint('[CloudSave] 클라우드 저장 성공');
      return true;
    } catch (e) {
      debugPrint('[CloudSave] 클라우드 저장 실패: $e');
      return false;
    }
  }
  
  /// 클라우드에서 로드
  Future<Map<String, dynamic>?> loadFromCloud() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[CloudSave] 로드 실패: 사용자 미로그인');
        return null;
      }
      
      final response = await _supabase
          .from('player_saves')
          .select('save_data, last_saved_at, version')
          .eq('user_id', userId)
          .maybeSingle();
      
      if (response == null) {
        debugPrint('[CloudSave] 클라우드 데이터 없음');
        return null;
      }
      
      debugPrint('[CloudSave] 클라우드 로드 성공 (버전: ${response['version']})');
      return {
        'data': response['save_data'],
        'timestamp': response['last_saved_at'],
        'version': response['version'],
      };
    } catch (e) {
      debugPrint('[CloudSave] 클라우드 로드 실패: $e');
      return null;
    }
  }
  
  /// 클라우드 데이터 존재 여부 확인
  Future<bool> hasCloudSave() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;
      
      final response = await _supabase
          .from('player_saves')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();
      
      return response != null;
    } catch (e) {
      debugPrint('[CloudSave] 클라우드 확인 실패: $e');
      return false;
    }
  }
  
  /// 클라우드 데이터 삭제
  Future<bool> deleteCloudSave() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;
      
      await _supabase
          .from('player_saves')
          .delete()
          .eq('user_id', userId);
      
      debugPrint('[CloudSave] 클라우드 데이터 삭제 완료');
      return true;
    } catch (e) {
      debugPrint('[CloudSave] 클라우드 삭제 실패: $e');
      return false;
    }
  }
}
