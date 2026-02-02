import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 인증 서비스 - 익명 로그인 및 사용자 관리
class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  /// 현재 사용자 ID
  String? get userId => _supabase.auth.currentUser?.id;
  
  /// 로그인 상태 확인
  bool get isLoggedIn => _supabase.auth.currentUser != null;

  /// 익명 계정 여부 확인
  bool get isAnonymous => _supabase.auth.currentUser?.isAnonymous ?? false;

  /// 사용자 이메일
  String? get userEmail => _supabase.auth.currentUser?.email;
  
  /// 익명 로그인
  Future<bool> signInAnonymously() async {
    try {
      final response = await _supabase.auth.signInAnonymously();
      debugPrint('[Supabase Auth] 익명 로그인 성공: ${response.user?.id}');
      return response.user != null;
    } on AuthException catch (e) {
      debugPrint('[Supabase Auth] 인증 에러: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[Supabase Auth] 알 수 없는 에러: $e');
      return false;
    }
  }
  
  /// 구글 로그인 (OAuth)
  Future<bool> signInWithGoogle() async {
    try {
      // Supabase OAuth 로그인 호출
      final success = await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        // 웹: 현재 origin 사용 / 안드로이드: 미리 정의한 커스텀 스킴 사용
        redirectTo: kIsWeb 
          ? Uri.base.origin 
          : 'io.supabase.idlewarrior://login-callback',
      );
      return success;
    } catch (e) {
      debugPrint('[Supabase Auth] 구글 로그인 실패: $e');
      return false;
    }
  }

  /// 로그아웃
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
      debugPrint('[Supabase Auth] 로그아웃 완료');
    } catch (e) {
      debugPrint('[Supabase Auth] 로그아웃 실패: $e');
    }
  }
  
  /// 인증 상태 변경 스트림
  Stream<AuthState> get onAuthStateChange => _supabase.auth.onAuthStateChange;

  /// 세션 새로고침
  Future<bool> refreshSession() async {
    try {
      await _supabase.auth.refreshSession();
      return true;
    } catch (e) {
      debugPrint('[Auth] 세션 새로고침 실패: $e');
      return false;
    }
  }
}
