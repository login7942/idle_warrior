# 🎮 Idle Warrior Adventure

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Idle Warrior Adventure**는 모던 웹 기술(JS/CSS)로 구현된 정통 방치형 RPG입니다. 프레임워크 없는 순수 JavaScript와 이벤트 기반 아키텍처를 특징으로 하며, 강력한 아이템 시스템과 성장 루프를 제공합니다.

---

## 📚 통합 문서 가이드 (Documentation)

초보 개발자와 사용자를 위해 파편화되어 있던 문서들을 성격에 맞게 3가지로 통합하였습니다.

### 1. [기획 및 설계 문서 (DOC_GAME_DESIGN.md)](./DOC_GAME_DESIGN.md)
*   게임 용어 정의, 아이템 티어/등급 체계, 전투 데미지 공식, 방치형 계산 로직 등 **게임의 규칙**을 설명합니다.

### 2. [개발자 가이드 (DOC_DEV_GUIDE.md)](./DOC_DEV_GUIDE.md)
*   프로젝트 구조, `State.js`Proxy 시스템, 이벤트 버스, 가상 리스트 및 성능 최적화 등 **코드의 구현 방식**을 설명합니다.

### 3. [업데이트 이력 & 로드맵 (DOC_UPDATE_LOG.md)](./DOC_UPDATE_LOG.md)
*   최근 변경 사항과 향후 개발 예정인 **프로젝트 진행 정보**를 기록합니다.

---

## 🚀 빠른 시작 (Quick Start)

### 실행 방법
1.  이 저장소를 클론하거나 다운로드합니다.
2.  브라우저에서 `index.html`을 직접 실행하거나, VS Code의 **Live Server**를 사용하여 로컬 서버로 구동합니다.
    *   *주의: ES6 모듈을 사용하므로 로컬 서버 환경(http://...)을 권장합니다.*

### 기술 스택
*   **Pure Vanilla JS**: 외부 라이브러리 없이 구현된 이벤트 주도 아키텍처.
*   **CSS3**: 변수(Variables)와 그리드를 활용한 현대적인 반응형 UI.
*   **HTML5 Canvas**: 일부 시각적 효과 및 파티클 처리.

---

## 🛠️ 주요 시스템
*   **자동 사냥**: 효율(GPM/EPM) 스냅샷 기반의 수동 방치 시스템.
*   **아이템 순환**: 제작 -> 강화 -> 파손 -> 계승으로 이어지는 독특한 장비 성장 루프.
*   **최적화**: 수천 개의 아이템도 무리 없이 처리하는 가상 리스트 및 타임 슬라이싱 기술 적용.

---
**Happy Coding & Farming!**
