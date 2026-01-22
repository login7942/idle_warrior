# Google OAuth 클라이언트 ID 생성 가이드

## 필요한 정보

### 1. 프로젝트 정보
- **Package Name**: `com.example.idle_warrior`
- **Supabase URL**: `https://yrkvwboldgzbwhaausmu.supabase.co`
- **Deep Link**: `io.supabase.idlewarrior://login-callback`

### 2. SHA-1 인증서 지문 확인 방법

다음 명령어 중 하나를 실행하여 SHA-1을 확인하세요:

#### 방법 1: Android Studio 사용
1. Android Studio에서 프로젝트 열기
2. 우측 Gradle 탭 클릭
3. `idle_warrior > android > Tasks > android > signingReport` 더블클릭
4. 하단 콘솔에서 SHA-1 확인

#### 방법 2: 명령어 사용 (Java가 설치된 경우)
```powershell
cd android
./gradlew signingReport
```

#### 방법 3: keytool 직접 사용
```powershell
# Java bin 폴더 경로를 찾아서 실행
"C:\Program Files\Java\jdk-XX.X.X\bin\keytool.exe" -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

---

## Google Cloud Console 설정 단계

### Step 1: Google Cloud Console 접속
1. https://console.cloud.google.com 접속
2. 프로젝트 선택 또는 새 프로젝트 생성

### Step 2: OAuth 동의 화면 설정
1. 좌측 메뉴 → **APIs & Services** → **OAuth consent screen**
2. User Type: **External** 선택 → **CREATE**
3. 필수 정보 입력:
   - App name: `Idle Warrior`
   - User support email: 본인 이메일
   - Developer contact: 본인 이메일
4. **SAVE AND CONTINUE**
5. Scopes: 기본값 유지 → **SAVE AND CONTINUE**
6. Test users: (선택사항) → **SAVE AND CONTINUE**

### Step 3: OAuth 클라이언트 ID 생성 (Android)
1. 좌측 메뉴 → **Credentials** → **+ CREATE CREDENTIALS** → **OAuth client ID**
2. Application type: **Android** 선택
3. 다음 정보 입력:
   - **Name**: `Idle Warrior Android`
   - **Package name**: `com.example.idle_warrior`
   - **SHA-1 certificate fingerprint**: (위에서 확인한 SHA-1 입력)
4. **CREATE** 클릭
5. 생성된 **Client ID** 복사 (예: `123456789-abcdefg.apps.googleusercontent.com`)

### Step 4: OAuth 클라이언트 ID 생성 (Web - 중요!)
**이 단계가 매우 중요합니다!** Supabase는 내부적으로 Web OAuth 흐름을 사용합니다.

1. 다시 **+ CREATE CREDENTIALS** → **OAuth client ID**
2. Application type: **Web application** 선택
3. 다음 정보 입력:
   - **Name**: `Idle Warrior Supabase`
   - **Authorized JavaScript origins**: 
     ```
     https://yrkvwboldgzbwhaausmu.supabase.co
     ```
   - **Authorized redirect URIs**: 
     ```
     https://yrkvwboldgzbwhaausmu.supabase.co/auth/v1/callback
     ```
4. **CREATE** 클릭
5. 생성된 **Client ID**와 **Client Secret** 복사

---

## Supabase Dashboard 설정

### Step 1: Google Provider 설정
1. https://supabase.com/dashboard 접속
2. 프로젝트 선택
3. 좌측 메뉴 → **Authentication** → **Providers**
4. **Google** 찾아서 클릭
5. 다음 정보 입력:
   - **Enable Sign in with Google**: ON
   - **Client ID**: (Web OAuth Client ID 입력)
   - **Client Secret**: (Web OAuth Client Secret 입력)
6. **Save** 클릭

### Step 2: Redirect URLs 설정
1. 좌측 메뉴 → **Authentication** → **URL Configuration**
2. **Redirect URLs**에 다음 추가:
   ```
   io.supabase.idlewarrior://login-callback
   ```
3. **Save** 클릭

---

## 테스트

1. 앱 재빌드:
   ```powershell
   flutter clean
   flutter build apk --debug
   ```

2. 실기기에 설치 및 테스트

3. 로그 확인:
   ```powershell
   flutter logs
   ```

---

## 문제 해결

### redirect_uri_mismatch 오류
- Google Cloud Console의 Web OAuth Client에 정확한 Supabase 콜백 URL이 등록되어 있는지 확인
- Supabase Dashboard의 Redirect URLs에 Deep Link가 등록되어 있는지 확인

### 400 오류
- Package Name이 정확한지 확인
- SHA-1이 정확한지 확인
- Android OAuth Client가 올바르게 생성되었는지 확인
