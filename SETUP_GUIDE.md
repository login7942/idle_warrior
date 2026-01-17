# 🛠 Flutter 개발 환경 설정 가이드 (Windows)

이 문서는 **Idle Warrior Adventure** 프로젝트를 Flutter로 개발하기 위한 환경 구축 과정을 안내합니다.

---

## 🏗 1단계: Flutter SDK 설치

1.  **SDK 다운로드**
    *   [Flutter SDK 최신 안정 버전(3.38.7) 직접 다운로드](https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.38.7-stable.zip)
    *   위 링크가 작동하지 않는다면 [Flutter SDK Archive](https://docs.flutter.dev/release/archive?tab=windows)에서 최신 **Stable** 버전을 확인하세요.

2.  **압축 해제**
    *   다운로드한 파일을 `C:\flutter` 경로에 압축 해제합니다.
    *   **주의**: `C:\Program Files`와 같이 관리자 권한이 필요한 경로는 피하세요.

3.  **환경 변수(Path) 설정**
    *   Windows 검색창에 **'시스템 환경 변수 편집'**을 입력하고 실행합니다.
    *   **'환경 변수'** 버튼을 클릭합니다.
    *   **'시스템 변수'** 목록에서 `Path`를 찾아 선택하고 **'편집'**을 클릭합니다.
    *   **'새로 만들기'**를 누르고 `C:\flutter\bin`을 입력한 뒤 저장합니다.

---

## 🛠 2단계: 필수 도구 설치

1.  **Git 설치**
    *   [git-scm.com](https://git-scm.com/)에서 Windows용 Git을 설치합니다.
    *   설치 시 기본 설정을 유지해도 무방합니다.

2.  **Android Studio 설치**
    *   [Android Studio 공식 사이트](https://developer.android.com/studio)에서 설치합니다.
    *   설치 후 **Settings > Plugins**에서 `Flutter` 플러그인을 설치합니다. (Dart도 자동 설치됨)
    *   **중요**: **Settings > Languages & Frameworks > Android SDK > SDK Tools** 탭에서 **Android SDK Command-line Tools (latest)**를 반드시 체크하고 설치해야 합니다. (기본적으로 꺼져 있는 경우가 많습니다.)

3.  **Visual Studio 2022 (Windows 데스크톱 앱 개발용)**
    *   Windows 앱 개발이 필요하다면 [Visual Studio](https://visualstudio.microsoft.com/ko/downloads/)를 설치합니다.
    *   워크로드에서 **'C++를 사용한 데스크톱 개발'**을 반드시 체크해야 합니다.

---

## ✅ 3단계: 설치 확인

모든 설치와 환경 변수 설정이 완료되었다면, **터미널(PowerShell 또는 CMD)**을 열고 아래 명령어를 입력합니다.

```powershell
flutter doctor
```

*   체크 표시(`[✓]`)가 아닌 항목(`[!]` 또는 `[✗]`)이 있다면 안내 메시지에 따라 추가 조치를 취해야 합니다.

---

## 💡 자주 발생하는 문제 해결 (Troubleshooting)

### 1. Android Licenses (안드로이드 라이선스 미승인)
`flutter doctor --android-licenses` 처럼 느낌표(`!`)가 뜬다면 아래 명령어를 터미널에 입력하고 모두 `y`를 눌러 수락하세요.
```powershell
flutter doctor --android-licenses
```

### 3. 'flutter' 명령어를 찾을 수 없음 (CommandNotFoundException)
시스템 환경 변수 `Path`에 `C:\flutter\bin`을 올바르게 추가했음에도 이 에러가 발생한다면:
1.  **터미널 재시작**: VS Code나 PowerShell 창을 모두 닫고 다시 실행하세요.
2.  **경로 오타 확인**: `C:\flutter\bin` 경로가 철자 하나 틀리지 않고 정확한지 확인하세요.
3.  **전체 경로 사용**: 급한 경우 `C:\flutter\bin\flutter create .` 처럼 전체 경로를 직접 입력하여 실행할 수 있습니다.

---

## 📝 향후 작업 (진행 예정)

- [x] Flutter SDK 및 안드로이드 라이선스 설정 완료
- [x] Flutter 프로젝트 초기화 (`flutter create .` / 프로젝트명: `idle_warrior`)
- [ ] 기존 웹 소스 기반 Dart 엔진 설계
- [ ] UI 프레임워크 구축
