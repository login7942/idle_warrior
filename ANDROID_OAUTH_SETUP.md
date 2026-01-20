# 🔐 안드로이드 APK 구글 로그인 설정 가이드 (Supabase)

## 📋 진행 상황 (2026-01-21)

### ✅ 완료된 작업
- [x] SHA-1 인증서 생성: `E0:70:C3:BF:6E:B5:7A:37:69:63:43:64:0C:20:19:0E:A3:7A:52:D4`
- [x] 패키지명 확인: `com.example.idle_warrior`
- [x] AndroidManifest.xml에 Deep Link 추가
- [x] Google Cloud Console에서 Android 클라이언트 ID 생성
- [x] Google Cloud Console에서 Web 클라이언트 ID 생성
- [x] Supabase에 Client ID, Client Secret 설정
- [x] 디버그 APK 빌드 성공
- [x] 에뮬레이터에서 앱 실행 성공

### ⏳ 남은 작업
- [ ] Google OAuth 설정 반영 대기 (5~10분 소요)
- [ ] 구글 로그인 테스트 및 검증
- [ ] 실제 안드로이드 기기에서 테스트
- [ ] 릴리즈 키스토어 생성 및 SHA-1 등록 (배포용)

### 🐛 발생한 문제
- **redirect_uri_mismatch**: Google 설정 변경 후 반영 대기 중
- **원인**: OAuth 클라이언트 설정 변경사항이 즉시 반영되지 않음
- **해결**: 5~10분 대기 후 재시도 필요

---

## 🚀 1단계: Google Cloud Console 설정

### 1-1. Google Cloud Console 접속
1. [Google Cloud Console](https://console.cloud.google.com/) 접속
2. 새 프로젝트 생성 또는 기존 프로젝트 선택

### 1-2. OAuth 2.0 클라이언트 ID 생성

1. **API 및 서비스** → **사용자 인증 정보** 메뉴
2. **사용자 인증 정보 만들기** → **OAuth 클라이언트 ID** 선택
3. **애플리케이션 유형**: **Android** 선택
4. 다음 정보 입력:
   - **이름**: Idle Warrior Android
   - **패키지 이름**: `com.example.idle_warrior`
   - **SHA-1 인증서 지문**: (아래에서 생성)

---

## 🔑 2단계: SHA-1 인증서 지문 생성

### Windows PowerShell에서 실행:

```powershell
# 디버그용 SHA-1 (개발/테스트용)
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

### 출력 예시:
```
Certificate fingerprints:
SHA1: A1:B2:C3:D4:E5:F6:...
SHA256: ...
```

**SHA1 값을 복사**하여 Google Cloud Console에 입력합니다.

### 릴리즈용 SHA-1 (나중에 필요)
```powershell
# 릴리즈 키스토어 생성 (처음 한 번만)
keytool -genkey -v -keystore release.keystore -alias release -keyalg RSA -keysize 2048 -validity 10000

# SHA-1 확인
keytool -list -v -keystore release.keystore -alias release
```

---

## 🔧 3단계: Supabase 설정

### 3-1. Supabase Dashboard 접속
1. [Supabase Dashboard](https://app.supabase.com/) 접속
2. 프로젝트 선택

### 3-2. Google Provider 활성화
1. **Authentication** → **Providers** 메뉴
2. **Google** 찾아서 활성화
3. Google Cloud Console에서 생성한 정보 입력:
   - **Client ID (for OAuth)**: Google Cloud Console의 Android 클라이언트 ID
   - **Client Secret (for OAuth)**: (Android는 불필요, Web 클라이언트 ID 사용 시에만)

### 3-3. Redirect URLs 설정
**Authentication** → **URL Configuration**에서 다음 추가:

```
io.supabase.idlewarrior://login-callback
```

---

## ⚙️ 4단계: Android 프로젝트 설정

### 4-1. `AndroidManifest.xml` 수정

`android/app/src/main/AndroidManifest.xml` 파일을 열어 다음 추가:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.idle_warrior">
    
    <!-- 인터넷 권한 추가 (이미 있을 수 있음) -->
    <uses-permission android:name="android.permission.INTERNET"/>
    
    <application
        android:label="Idle Warrior"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        
        <!-- 기존 MainActivity -->
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            
            <!-- 기존 intent-filter -->
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
            
            <!-- 🆕 Deep Link 처리를 위한 intent-filter 추가 -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                
                <!-- Supabase OAuth 콜백 URL -->
                <data
                    android:scheme="io.supabase.idlewarrior"
                    android:host="login-callback" />
            </intent-filter>
        </activity>
        
        <!-- 기존 meta-data -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
```

### 4-2. 패키지명 확인/변경 (필요시)

`android/app/build.gradle` 파일에서:

```gradle
android {
    ...
    defaultConfig {
        applicationId "com.example.idle_warrior"  // 이 값이 Google Cloud Console과 일치해야 함
        ...
    }
}
```

---

## 📱 5단계: 코드 확인

현재 `lib/services/auth_service.dart`가 이미 올바르게 설정되어 있는지 확인:

```dart
Future<bool> signInWithGoogle() async {
  try {
    final success = await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb 
        ? Uri.base.origin 
        : 'io.supabase.idlewarrior://login-callback',  // ✅ 이미 설정됨
    );
    return success;
  } catch (e) {
    debugPrint('[Supabase Auth] 구글 로그인 실패: $e');
    return false;
  }
}
```

---

## 🏗️ 6단계: APK 빌드 및 테스트

### 디버그 APK 빌드:
```powershell
flutter build apk --debug
```

### 실제 기기에서 테스트:
```powershell
flutter run --release
```

### 릴리즈 APK 빌드 (배포용):
```powershell
flutter build apk --release
```

---

## ✅ 체크리스트

- [ ] Google Cloud Console에서 프로젝트 생성
- [ ] Android용 OAuth 클라이언트 ID 생성
- [ ] SHA-1 인증서 생성 및 등록
- [ ] Supabase에서 Google Provider 활성화
- [ ] Supabase Redirect URL 설정
- [ ] `AndroidManifest.xml`에 Deep Link 추가
- [ ] 패키지명 일치 확인
- [ ] APK 빌드 테스트

---

## 🐛 문제 해결

### "Developer Error" 또는 "Sign in failed"
**원인**: SHA-1 인증서가 Google Cloud Console에 등록되지 않음

**해결**:
1. SHA-1 인증서를 다시 확인
2. Google Cloud Console → OAuth 클라이언트 ID → SHA-1 재등록
3. 10~20분 정도 기다린 후 재시도

### Deep Link가 작동하지 않음
**원인**: `AndroidManifest.xml` 설정 오류

**해결**:
1. `android:exported="true"` 확인
2. `android:scheme`과 `android:host` 값 확인
3. Supabase Redirect URL과 일치하는지 확인

### 패키지명 불일치 에러
**원인**: Google Cloud Console과 앱의 패키지명이 다름

**해결**:
1. `android/app/build.gradle`의 `applicationId` 확인
2. `AndroidManifest.xml`의 `package` 확인
3. Google Cloud Console의 OAuth 클라이언트 ID 패키지명 확인

---

## 📚 참고 자료

- [Supabase Auth 문서](https://supabase.com/docs/guides/auth/social-login/auth-google)
- [Google Cloud Console](https://console.cloud.google.com/)
- [Flutter Deep Linking](https://docs.flutter.dev/development/ui/navigation/deep-linking)

---

## 🎯 다음 단계

APK 빌드가 완료되면:
1. 실제 안드로이드 기기에서 테스트
2. 구글 로그인 플로우 확인
3. 클라우드 저장/로드 테스트
4. Play Store 배포 준비 (릴리즈 키스토어 설정)
