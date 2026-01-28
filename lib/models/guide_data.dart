import 'package:flutter/material.dart';

class GuideEntry {
  final String title;
  final String content;
  final IconData icon;

  const GuideEntry({required this.title, required this.content, required this.icon});
}

class GameGuideData {
  static const List<GuideEntry> automationGuides = [
    GuideEntry(
      title: '자동 분해 시스템',
      content: '획득하는 즉시 설정된 티어/등급 이하의 장비를 분해하여 재료로 변환합니다. 인벤토리 공간 확보에 필수적입니다.',
      icon: Icons.auto_delete_outlined,
    ),
    GuideEntry(
      title: '자동 스테이지 진행',
      content: '몬스터를 일정 수 이상 처치하면 자동으로 다음 스테이지로 이동합니다. 보스 층에서는 수동 확인이 필요할 수 있습니다.',
      icon: Icons.speed,
    ),
  ];

  static const List<GuideEntry> growthGuides = [
    GuideEntry(
      title: '슬롯 강화의 중요성',
      content: '장비 자체 강화보다 슬롯 강화가 효율적입니다. 장비를 교체해도 강화 수치가 유지되기 때문입니다.',
      icon: Icons.bolt,
    ),
    GuideEntry(
      title: '승급 조건',
      content: '캐릭터 승급을 위해서는 일정 수치 이상의 "슬롯 강화 총합"이 필요합니다. 승급 시 강력한 보너스 스탯을 얻습니다.',
      icon: Icons.military_tech,
    ),
    GuideEntry(
      title: 'T2 장비 제작',
      content: '티어 2 장비는 T2 핵심 재료와 충분한 신비의 가루가 필요합니다. 상위 사냥터에서 재료를 수급하세요.',
      icon: Icons.build_circle,
    ),
    GuideEntry(
      title: '아이템 승급',
      content: '아이템을 +20강까지 강화하면 승급이 가능합니다. 승급 시 상위 티어 장비로 진화하며 훨씬 강력한 능력치를 얻을 수 있습니다.',
      icon: Icons.auto_awesome,
    ),
    GuideEntry(
      title: '강화 성공 확률',
      content: '장비 티어가 높을수록 강화 성공 확률이 낮아집니다. T2는 0.7배, T6는 0.25배의 확률 페널티가 적용됩니다.',
      icon: Icons.trending_down,
    ),
  ];

  static const List<Map<String, String>> faq = [
    {'q': '골드가 모자라요.', 'a': '더 높은 스테이지나 적정 사냥터에서 사냥하면 골드 획득 효율이 올라갑니다.'},
    {'q': '강화 보호석은 어디서 얻나요?', 'a': '일일 퀘스트 보상이나 높은 등급의 사냥터 보스에게서 낮은 확률로 드랍됩니다.'},
    {'q': '능력치 재설정은 언제 하나요?', 'a': '전설 등급 이상의 장비를 획득했을 때 옵션 재설정석을 사용하여 최적의 옵션을 맞추는 것을 추천합니다.'},
  ];
}
