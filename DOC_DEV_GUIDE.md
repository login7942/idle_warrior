# 🛠️ Idle Warrior - 개발 가이드

> Developer Guide v1.0

## 📋 목차
1. [프로젝트 구조](#프로젝트-구조)
2. [코드 아키텍처](#코드-아키텍처)
3. [주요 클래스 설명](#주요-클래스-설명)
4. [개발 워크플로우](#개발-워크플로우)
5. [성능 최적화](#성능-최적화)
6. [디버깅 가이드](#디버깅-가이드)
7. [UI/UX 디자인 원칙](#uiux-디자인-원칙)

---

## 📁 프로젝트 구조

```
idle_warrior/
├── lib/
│   ├── main.dart                 # 메인 앱 및 게임 로직
│   └── models/
│       ├── player.dart           # 플레이어 데이터 모델
│       ├── monster.dart          # 몬스터 생성 및 관리
│       ├── item.dart             # 아이템 시스템
│       ├── skill.dart            # 스킬 시스템
│       ├── achievement.dart      # 업적 시스템
│       └── hunting_zone.dart     # 사냥터 데이터
├── assets/
│   └── images/
│       ├── background.png        # 전투 배경
│       ├── warrior.png           # 플레이어 캐릭터
│       └── slime.png             # 몬스터 이미지
├── android/                      # Android 빌드 설정
├── pubspec.yaml                  # 패키지 의존성
└── DOC_*.md                      # 문서 파일들
```

---

## 🏗️ 코드 아키텍처

### 📐 설계 패턴

#### 1. State Management
- **Flutter StatefulWidget**: 게임 상태 관리
- **setState()**: UI 업데이트
- **향후 고려**: Provider, Riverpod 등

#### 2. Data Models
- **Pure Dart Classes**: 비즈니스 로직 분리
- **Factory Constructors**: 객체 생성 패턴
- **Immutable Fields**: 안정성 확보

#### 3. UI Components
- **Widget Composition**: 재사용 가능한 위젯
- **Builder Pattern**: 동적 UI 생성
- **Custom Painters**: 성능 최적화

---

## 📚 주요 클래스 설명

### 🎮 GameMainPage (main.dart)

#### 핵심 State 변수
```dart
Player player;                    // 플레이어 인스턴스
Monster? currentMonster;          // 현재 전투 중인 몬스터
int playerCurrentHp;              // 플레이어 현재 HP
int _selectedIndex;               // 현재 선택된 탭
HuntingZone _currentZone;         // 현재 사냥터
int _currentStage;                // 현재 스테이지
```

#### 주요 메서드
```dart
_startBattleLoop()                // 전투 루프 시작
_processCombatTurn()              // 턴 처리
_handleVictory()                  // 승리 처리
_handlePlayerDeath()              // 사망 처리
_spawnMonster()                   // 몬스터 생성
_addLog()                         // 로그 추가
_addFloatingText()                // 데미지 텍스트 생성
```

### 👤 Player (models/player.dart)

#### 주요 속성
```dart
String name;                      // 이름
int level;                        // 레벨
int exp, maxExp;                  // 경험치
int gold;                         // 골드
Map<ItemType, Item?> equipment;   // 장착 장비
List<Item> inventory;             // 인벤토리
List<Skill> skills;               // 스킬 목록
```

#### 주요 메서드
```dart
gainExp(int amount)               // 경험치 획득
equipItem(Item item)              // 장비 착용
unequipItem(ItemType type)        // 장비 해제
addItem(Item item)                // 아이템 추가
calculateOfflineRewards()         // 방치 보상 계산
checkAchievement()                // 업적 확인
```

### 👾 Monster (models/monster.dart)

#### Factory Constructor
```dart
Monster.generate(HuntingZone zone, int stage)
```
- 사냥터와 스테이지에 따라 몬스터 생성
- 지수 함수적 난이도 증가
- 랜덤 몬스터 종류 선택

### 🎒 Item (models/item.dart)

#### 강화 시스템
```dart
applyEnhanceMilestone(int level)
```
- +3, +4, +7: 옵션 성장
- +5, +8: 옵션 추가
- +9, +10: 대폭 성장

### 🗺️ HuntingZone (models/hunting_zone.dart)

#### 데이터 구조
```dart
class HuntingZone {
  final ZoneId id;
  final String name;
  final String description;
  final Color color;
  final int minLevel;
  final List<String> monsterNames;
  final List<String> keyDrops;
}
```

---

## 🔄 개발 워크플로우

### 🚀 새 기능 추가 프로세스

#### 1. 데이터 모델 정의
```dart
// models/new_feature.dart
class NewFeature {
  final String id;
  final int value;
  
  NewFeature({required this.id, required this.value});
}
```

#### 2. Player 클래스에 통합
```dart
// models/player.dart
class Player {
  List<NewFeature> features = [];
  
  void addFeature(NewFeature feature) {
    features.add(feature);
  }
}
```

#### 3. UI 구현
```dart
// main.dart
Widget _buildNewFeatureTab() {
  return ListView.builder(
    itemCount: player.features.length,
    itemBuilder: (context, index) {
      // UI 구현
    },
  );
}
```

#### 4. 네비게이션 연결
```dart
Widget _buildBodyContent() {
  switch (_selectedIndex) {
    case X: return _buildNewFeatureTab();
  }
}
```

### 🧪 테스트 가이드

#### 수동 테스트 체크리스트
- [ ] 기능이 정상 작동하는가?
- [ ] UI가 깨지지 않는가?
- [ ] 성능 저하가 없는가?
- [ ] 다른 기능에 영향을 주지 않는가?
- [ ] Hot Reload가 정상 작동하는가?

---

## ⚡ 성능 최적화

### 🎨 렌더링 최적화

#### 1. RepaintBoundary 사용
```dart
RepaintBoundary(
  child: Image(
    image: AssetImage('assets/images/background.png'),
    fit: BoxFit.cover,
  ),
)
```
- 배경 이미지 등 자주 변경되지 않는 위젯에 적용
- 불필요한 리페인트 방지

#### 2. CustomPainter 활용
```dart
class LootParticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 직접 Canvas에 그리기
  }
}
```
- 파티클 시스템 등 대량의 위젯 대신 사용
- 60fps 유지

#### 3. const 생성자 활용
```dart
const Icon(Icons.star, color: Colors.amber)
```
- 불변 위젯은 const로 선언
- 메모리 절약 및 성능 향상

### 💾 메모리 최적화

#### 1. 리스트 크기 제한
```dart
if (_combatLog.length > 100) {
  _combatLog.removeAt(0);
}
```
- 로그, 파티클 등 무한 증가 방지

#### 2. Timer 정리
```dart
@override
void dispose() {
  _battleTimer?.cancel();
  _efficiencyTimer?.cancel();
  super.dispose();
}
```
- 사용하지 않는 타이머 반드시 취소

---

## 🐛 버그 수정

### ✅ 완료된 수정
- [x] **일괄 분해 시 마우스 트래커 오류**: 다이얼로그 닫힘과 데이터 갱신 시점 충돌 해결
- [x] 로그 이모지 제거
- [x] **Windows 환경 `grep` 명령어 오류**: PowerShell에서 `grep` 미지원으로 인한 중단 이슈 해결 (Select-String 명령어 활용 가이드 추가)
- [x] **능력치 명칭 로직 통합**: `main.dart`와 `item.dart` 간의 능력치 명칭 불일치 해결 및 `Item` 모델로 로직 일원화
- [x] **아이템 티어 라벨 표시 오류**: UI에서 등급 인덱스를 티어로 잘못 표시하던 버그 수정 (항상 T1으로 표시되도록 일원화)

## 🐛 디버깅 가이드

### 🐚 터미널 명령어 (Windows/PowerShell)
Windows 환경에서 코드 검색 시 `grep` 대신 아래 명령어를 사용하세요:
- **문자열 검색**: `Select-String -Path "파일경로" -Pattern "검색어"`
- **하위 폴더 포함**: `Get-ChildItem -Recurse | Select-String -Pattern "검색어"`

### 🔍 일반적인 문제 해결

#### 1. Hot Reload 실패
**증상**: 코드 변경이 반영되지 않음  
**해결**: Hot Restart (Shift + R) 또는 앱 재시작

#### 2. 빌드 에러
**증상**: `flutter build` 실패  
**해결**:
```bash
flutter clean
flutter pub get
flutter build apk
```

#### 3. 한글 경로 문제
**증상**: Android 빌드 실패  
**해결**: 
- 프로젝트를 영문 경로로 이동
- 또는 `android/gradle.properties`에 추가:
```properties
android.overridePathCheck=true
```

#### 4. 마우스 트래커 Assertion 오류 (Rendering)
**증상**: `rendering/mouse_tracker.dart:199:12`에서 Assertion failed 발생 (주로 다이얼로그 닫을 때)  
**원인**: 다이얼로그 내의 복잡한 위젯(GridView 등)이 제거되는 시점과 마우스 오버 상태 추적이 충돌  
**해결**:
- 다이얼로그 내 GridView 대신 계산된 너비의 `Wrap` 사용으로 위젯 구조 단순화
- 데이터를 수정하기 전에 `Navigator.pop(context)`를 먼저 호출하여 UI 트리를 안정화한 후 로직 실행

### 📊 성능 프로파일링

#### Flutter DevTools 사용
```bash
flutter run --profile
```
- Performance 탭에서 프레임 드롭 확인
- Memory 탭에서 메모리 누수 확인

---

## 🔧 유용한 개발 도구

### VS Code 확장
- **Dart**: Dart 언어 지원
- **Flutter**: Flutter 개발 도구
- **Error Lens**: 인라인 에러 표시

### 디버깅 명령어
```bash
# 디바이스 확인
flutter devices

# 로그 확인
flutter logs

# 앱 실행 (디버그)
flutter run

# 앱 실행 (프로파일)
flutter run --profile

# APK 빌드
flutter build apk --release
```

---

## 📝 코딩 컨벤션

### 네이밍 규칙
- **클래스**: PascalCase (`Player`, `Monster`)
- **변수/함수**: camelCase (`currentHp`, `_spawnMonster`)
- **상수**: lowerCamelCase (`maxInventorySize`)
- **Private**: 언더스코어 접두사 (`_selectedIndex`)

### 파일 구조
```dart
// 1. Imports
import 'dart:async';
import 'package:flutter/material.dart';

// 2. Main Widget
class GameMainPage extends StatefulWidget {}

// 3. State Class
class _GameMainPageState extends State<GameMainPage> {
  // 3.1 Variables
  // 3.2 Lifecycle Methods
  // 3.3 Game Logic Methods
  // 3.4 UI Build Methods
}

// 4. Helper Classes
class FloatingText {}
```

---

## 🚀 배포 가이드

### Android APK 빌드
```bash
flutter build apk --release
```
생성 위치: `build/app/outputs/flutter-apk/app-release.apk`

### 앱 번들 빌드 (Play Store용)
```bash
flutter build appbundle --release
```

### 버전 관리
`pubspec.yaml`:
```yaml
version: 1.0.0+1
# 1.0.0: 버전 이름
# +1: 빌드 번호
```

---

## 🤖 자동 배포 및 OTA 시스템 (CI/CD)

### 1. 워크플로우 개요
코드 수정 후 GitHub에 푸시하면 자동으로 빌드되어 사용자에게 업데이트 알림이 가는 시스템입니다.

### 2. 작동 프로세스
1.  **Code Push**: 개발자가 `main` 브랜치에 코드를 푸시합니다.
2.  **GitHub Actions**: 
    -   Flutter 환경 설정 및 의존성 설치.
    -   `flutter build apk --release` 실행.
    -   생성된 APK를 `gh-pages` 브랜치 또는 Release 섹션에 업로드.
    -   `version.json` 파일을 최신 버전으로 갱신.
3.  **App Check**: 사용자가 앱을 켜면 서버의 `version.json`을 확인합니다.
4.  **Update Prompt**: 새 버전이 발견되면 앱 내에서 업데이트 다이얼로그를 출력합니다.

### 3. 배포 주의사항
-   **버전 수동 관리**: `pubspec.yaml`의 `version` 값을 반드시 올리고 푸시해야 앱이 새 버전을 인식합니다.
-   **서버 경로**: `version.json`과 APK가 호스팅되는 URL이 static하게 유지되어야 합니다.

### 4. 향후 온라인 확장 (Supabase/Firebase)
-   백엔드 도입 시에도 이 배포 워크플로우는 동일하게 유지됩니다.
-   로그인 및 랭킹 데이터는 Supabase로, 앱 바이너리 배포(OTA)는 현재의 GitHub 방식을 유지하거나 Firebase App Distribution으로 확장 가능합니다.

---

## 📞 문의 및 기여

### 버그 리포트
이슈 생성 시 포함 사항:
- 발생 환경 (기기, OS 버전)
- 재현 방법
- 예상 동작 vs 실제 동작
- 스크린샷/로그

### 기능 제안
- 명확한 사용 사례
- 기대 효과
- 구현 난이도 추정

---

## 🎨 UI/UX 디자인 원칙

### ⚖️ 대칭 및 그리드 시스템 (Symmetry & Grid)
- **그리드 정렬**: 버튼이나 칸을 나열할 때 단순히 나열하지 않고, 2x3, 3x2 등 정해진 그리드 시스템을 사용하여 좌우 대칭을 맞춥니다.
- **간격의 통일**: 모든 UI 요소 사이의 여백(Spacing, Padding)은 4, 8, 12, 16px 단위의 8pt Grid 시스템을 따릅니다.
- **고정 비율**: 팝업이나 다이얼로그 내의 버튼들은 상단 2단(5:5), 하단 1단(Full width) 형태의 안정적인 구조를 지향합니다.

### ✨ 프리미엄 비주얼 (Premium Aesthetics)
- **유리 질감 (Glassmorphism)**: 배경을 `Colors.black.withOpacity(0.8)` 또는 `blur` 효과와 함께 사용하여 깊이감을 줍니다.
- **그라데이션 (Gradients)**: 단색 대신 은은한 그라데이션을 배경이나 버튼에 적용합니다.
- **아이콘 활용 (Icons & Emojis)**: 텍스트만 있는 버튼보다 직관적인 아이콘을 함께 배치하여 시각적 완성도를 높입니다.

### 🎬 인터랙션 및 피드백 (Interactions)
- **스케일 효과**: 버튼 클릭 시 미세하게 크기가 변하는 피드백을 제공합니다.
- **규정된 규격**: 버튼은 텍스트 길이에 따라 크기가 변하지 않으며, 레이아웃에 맞게 고정된 너비(Width)와 높이(Height)를 가집니다.
- **빛 효과 (Glow)**: 높은 등급의 아이템이나 선택된 상태의 버튼에는 테두리 빛 효과를 추가합니다.
- **상태 변화**: `Hover`나 `Selected` 상태를 명확히 구분하여 유저에게 현재 상태를 피드백합니다.

---

## 💎 Premium Game UI 디자인 시스템

### 📏 고정 규격 시스템 (Fixed Sizing System) - [필수 준수]
- **버튼 불변 법칙**: 어떤 버튼도 내부의 글자 수나 길이에 따라 가로/세로 크기가 변해서는 안 됩니다. 모든 액션 버튼은 레이아웃 그리드에 따른 고정 너비(Fixed Width)를 가집니다.
- **통일감 있는 정렬**: 리스트 형태의 UI(스킬, 업적 등)에서 모든 버튼은 우측 끝에 수직으로 일렬 정렬되어야 하며, 동일한 크기를 유지해야 합니다.
- **텍스트 오버플로우 대응**: 수치가 커지거나 텍스트가 길어질 경우 버튼을 키우는 대신 `FittedBox` 위젯을 사용하여 폰트 크기를 자동으로 축소하거나, `maxLines: 1`과 `ellipsis`를 사용하여 레이아웃 파괴를 방지합니다.
- **수치 가독성**: 골드 수치(`1,000,000 G`) 등은 `_formatNumber` 함수를 사용하여 항상 세 자리 콤마를 표시하며, 버튼 내에서 가독성을 해치지 않도록 여백을 관리합니다.

### 🍶 Glassmorphism (유리 질감)
- **효과**: `BackdropFilter(sigmaX: 10, sigmaY: 10)`를 사용하여 배경을 부드럽게 블러 처리합니다.
- **배경**: `Colors.black.withOpacity(0.6)`에서 `0.8` 사이의 반투명 그라데이션을 사용합니다.
- **테두리**: `Border.all(color: Colors.white.withOpacity(0.1), width: 0.5)`를 추가하여 유리의 반사광 테두리를 표현합니다.

### 🏔️ Neumorphism & Depth (입체감)
- **그림자**: 단순한 단일 그림자 대신, 빛의 방향을 고려한 **Multi-layered Shadow**를 사용합니다.
- **곡률**: 모든 컨테이너와 카드의 `borderRadius`는 **16~24** 사이로 설정하여 부드러운 인상을 줍니다.
- **깊이**: 중요한 카드나 팝업은 `BoxShadow`의 `blurRadius`를 20 이상으로 주어 화면 위에 떠 있는 듯한 느낌을 줍니다.

### 🎭 Motion & Easing (애니메이션)
- **Curves**: Material의 기본 애니메이션 대신 `Curves.easeOutQuint`, `Curves.easeInOutCubic` 등을 사용하여 고급스러운 움직임을 구현합니다.
- **Micro-animations**: 버튼 클릭 시 가벼운 `Scale` 변화(0.95), 탭 전환 시 부드러운 `Fade` 및 `Slide`를 적용합니다.

### 🎨 Color & Gradient
- **Dark Mode Base**: `Color(0xFF0F111A)`를 기본 배경색으로 사용합니다.
- **Gradients**: 모든 액션 요소에는 최소 2색 이상의 `LinearGradient`를 적용합니다.
- **Branding**: Material 기본 색상을 피하고, 등급별/속성별 독자적인 프리미엄 컬러 팔레트를 사용합니다.

### 💍 장신구 특수 스탯 시스템 (Ring & Necklace)
- **듀얼 주 능력치**: 반지와 목걸이는 '공격력'과 '체력' 두 가지를 기본 스탯으로 가집니다.
- **T1 기초 밸런스 (2026-01-17 재설정)**:
  - **플레이어**: 1Lv 공격력 30 / 1Lv 체력 250
  - **무기**: 공격력 100
  - **방어구**: 투구 300 / 갑옷 500 / 신발 200 (총 1000 HP)
  - **장신구**: 반지(공20, 체100) / 목걸이(공30, 체150)
- **스테이지 가속 시스템 (Stage Acceleration)**:
  - **내부 단계 (Combat Stage)**: 몬스터 스탯, 보상 계산의 기준 (1씩 증가)
  - **표시 단계 (Display Stage)**: 유저가 실제 보게 되는 숫자 (가속 적용)
  - **공식**: `DisplayStage = floor(CombatStage^1.6 + (CombatStage-1)*2)`
- **몬스터 성장 공식 (2026-01-17 개편)**:
  - **체력(HP)**: $900 \times stage^{1.25}$ (11Stage 기준)
    - *초반 완화(Smoothing)*: 1~5층은 15%, 6~10층은 40% 수치만 적용
  - **공격력(ATK)**: $90 \times stage^{1.1}$
  - **방어력(DEF)**: 0 고정
- **사망 페널티 (Death Penalty)**:
  - 플레이어 사망 시 **-5 스테이지** 하락 (최소 1 스테이지 유지)
  - 스테이지 진행도(`_stageKills`) 초기화
- **강화 동기화**: 모든 스탯은 강화 단계에 따라 동일한 계수(`getEnhanceFactor`)로 상승합니다.

---

### 🎨 아이템 등급/티어 비주얼 규격 (Item Grade & Tier)

- **핵심 원칙**: 이 게임에서 **Tier와 Grade는 동일한 개념**입니다. (`Tier = Grade Index + 1`)
- **표시 규칙**: `Common = T1`, `Uncommon = T2`, `Rare = T3`, `Epic = T4`, `Legendary = T5`, `Mythic = T6`로 매칭됩니다.
- **제한 사항**: Shader 및 ParticleSystem 사용 금지. 오직 Opacity, Scale, Blur, Gradient 이동만 사용.

| 등급 (Grade) | 표시 이름 | 테마 색상 (Primary) | 비주얼 효과 |
| :--- | :--- | :--- | :--- |
| **Common** | 일반 | `0xFF9CA3AF` (Gray) | 기본 슬롯, 효과 없음 |
| **Uncommon** | 고급 | `0xFF22C55E` (Green) | 미세 Glow (Spread: 2) |
| **Rare** | 희귀 | `0xFF3B82F6` (Blue) | 중간 Glow (Spread: 4) |
| **Epic** | 에픽 | `0xFFA855F7` (Purple) | 강한 Glow (Spread: 8) |
| **Legendary** | 전설 | `0xFFF59E0B` (Gold) | 초강력 Glow (Spread: 12), 전설 전용 슬롯 효과 |
| **Mythic** | 신화 | `0xFFEF4444` (Red) | 궁극의 Glow (Spread: 18), **Mythic Shimmer(무지개 광택)** 적용 |

---

### 🤺 캐릭터 그래픽 및 연출 규격 (Character Rendering)
캐릭터의 품격을 높이기 위해 다음과 같은 동적 연출 및 렌더링 파이프라인을 준수합니다.

#### 1. 프리미엄 캐릭터 연출 (Visual Standards)
- **Breathing (숨쉬기)**: 캐릭터가 정지 상태에서도 살아있는 느낌을 주도록 `3.0초` 주기로 `5~8px` 내외의 상하 미세 이동(Transform.translate)을 적용합니다.
- **Dynamic Aura (후광 펄스)**: 캐릭터 배후에 Core 및 Bloom 레이어를 중첩 배치하고, 숨쉬기 주기와 동기화하여 역동적인 빛의 확산을 연출합니다.
- **Magic Seal (마법진)**: 캐릭터의 등급이나 위치에 따라 회전하는 마법진(Rotating Seal)을 배치하여 시각적 무게감을 더합니다.
- **Particle System**: 캐릭터 속성에 맞는 색상의 마력 입자를 생성하며, 지그재그 모션과 페이드 아웃 효과를 결합하여 자연스럽게 소멸되도록 합니다.

#### 2. 실시간 크로마키 및 에셋 처리 (Transparency)
- **표준 원칙**: 실시간 필터(`ColorFiltered`)는 이미지의 디테일을 손상시킬 수 있으므로, **배경이 제거된 투명 PNG 에셋 사용을 원칙**으로 합니다.
- **처리 프로세스**: 배경이 있는 에셋(흰색/검정 등) 도입 시, 반드시 외부 도구나 스크립트를 통해 물리적으로 배경을 제거한 뒤 `assets/images`에 배치합니다.
- **예외 상황**: 에셋 수정이 즉시 불가능한 임시 개발 단계에서만 `ColorFiltered` 매트릭스를 활용하며, 최종 배포 전에는 반드시 투명 PNG로 교체합니다.

#### 3. 모션 싱크로나이즈
- 모든 캐릭터 애니메이션(공격, 피격, 숨쉬기)은 `AnimationController`를 통해 제어하며, UI 틱(Ticker)과 동기화하여 끊김 없는 부드러운 프레임을 유지합니다.

---

## � 패치 노트 (Patch Notes)

### [v0.0.13] - 2026-01-17
- **사망 페널티 강화**: 플레이어 사망 시 현재 스테이지가 5단계 하락하도록 변경하여 패배의 긴장감을 높였습니다.

### [v0.0.12] - 2026-01-17
- **스테이지 가속 시스템 도입**: 내부 난이도는 정교하게 조절하되, 유저에게는 시원시원한 성장감을 주기 위해 표시 스테이지 숫자가 실시간으로 가속되는 시스템을 적용했습니다.
- **전투 밸런스 심화**: 표시 스테이지의 빠른 증가 속도에 맞춰 몬스터의 체력($stage^{1.25}$)과 공격력($stage^{1.1}$) 성장 곡선을 최적화했습니다.

### [v0.0.11] - 2026-01-17
- **초반 구간 전투 난이도 조정 (Smoothing)**: 11스테이지 이전까지 몬스터 체력이 너무 높게 느껴지지 않도록 단계적 완화 로직(1-5층 15%, 6-10층 40%)을 적용했습니다.

### [v0.0.10] - 2026-01-17
- **플레이어 기초 스탯 상향**: 1레벨 플레이어의 기본 공격력(10->30)과 체력(100->250)을 상향 조정했습니다.
- **기존 데이터 소급 적용**: 기존 플레이어도 레벨에 따른 보너스를 포함하여 새로운 기초 능력치 혜택을 받을 수 있도록 보정 로직을 적용했습니다.

### [v0.0.9] - 2026-01-17
- **몬스터 성장 시스템 전면 개편**: 용사의 공격력 상향에 맞춰 몬스터의 기초 체력(900) 및 공격력(90)을 재설정하고, 지수 성장 공식($stage^{1.15}$ 등)을 적용했습니다.
- **전투 밸런스 최적화**: 스테이지 진행에 따른 난이도 체감이 더욱 직관적으로 느껴지도록 수식을 단순화했습니다.

### [v0.0.8] - 2026-01-17
- **기초 밸런스 전면 재조정**: T1 아이템의 기본 스탯을 사용자 요청 수치로 상향 조정했습니다. (공격력 100, 총 HP 1000 등)
- **데이터 자동 보정**: 기존에 보유한 모든 아이템이 새로운 스탯 규격으로 즉시 업데이트되도록 보정 로직을 강화했습니다.

### [v0.0.7] - 2026-01-17
- **장신구 시스템 고도화**: 반지와 목걸이에 **듀얼 주 능력치(공격력+체력)** 시스템을 도입했습니다.
- **강화 로직 통합**: 이제 장신구의 체력 옵션도 공격력과 동일하게 강화 단계에 따라 수치가 상승합니다.
- **UI 최적화**: 아이템 상세창의 주 능력치 영역을 확장하여 두 가지 핵심 스탯을 콤팩트하게 표시하도록 개선했습니다.

### [v0.0.6] - 2026-01-17
- **아이템 시스템 전면 리빌딩 (A안 적용)**: Tier와 Grade 개념을 하나로 통합했습니다.
- **드랍 밸런스 조정**: 현재 모든 사냥터에서 오직 **T1(일반)** 등급의 아이템만 드랍되도록 직관적으로 변경했습니다.
- **코드 무결성**: 모델의 생성자와 직렬화 로직에서 티어와 등급이 항상 동기화되도록 강제했습니다.

### [v0.0.5] - 2026-01-17
- **UI 무결성 개선**: 아이템 슬롯 좌측 상단 티어 라벨이 실제 아이템 티어(`T1`)와 일치하도록 수정 (등급 기반 오표기 해결)

### [v0.0.4] - 2026-01-17
- **개발 환경 최적화**: Windows PowerShell 환경에서의 명령어 호환성 가이드 추가
- **코드 무결성 개선**: UI와 모델 간의 능력치 명칭(HP/공격력) 로직을 `Item` 모델로 통합하여 데이터 불일치 버그 원천 차단

### [v0.0.3] - 2026-01-17
- **장비 시스템 리빌딩**: 1티어 장비 스탯 고정 및 강화 공식(선형 증폭) 적용
- **UI 최적화**: 장착 장비 슬롯 1줄 콤팩트 레이아웃 적용
- **밸런스 조정**: 플레이어 초기 스탯(10/100) 및 드랍률(20%) 조정

### [v0.0.2] - 2026-01-17
- **데이터 영속성**: SharedPreferences 기반 자동 저장/불러오기 구현
- **인벤토리 개선**: 신규 아이템 'N' 표시 및 상세창 네비게이션 추가
- **서버리스 OTA**: GitHub Actions를 통한 자동 APK 빌드 및 업데이트 시스템 구축

### [v0.0.1] - 새로운 시작 (2026-01-17)
- **데이터 보존 시스템**: 이제 앱을 재시작해도 플레이어의 정보가 보존됩니다.
- **관리자 도구 확장**: 실시간 몬스터 방어력 배율(0~100%) 조절 슬라이더가 추가되었습니다.

---

**최종 수정**: 2026-01-17  
**작성자**: Idle Warrior Dev Team
