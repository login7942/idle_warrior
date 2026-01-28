import 'dart:math';

enum AchievementType {
  monsterKill,
  goldEarned,
  playerLevel,
  itemAcquired,
  skillUsed
}

class Achievement {
  final String id;
  final String title;
  final String description;
  final AchievementType type;
  final List<int> targets; // 각 단계별 목표 수치
  final List<int> rewards; // 각 단계별 보상 수치

  Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.targets,
    required this.rewards,
  });

  // 현재 진행도에 따른 단계 계산
  int getCurrentStep(int progress) {
    for (int i = 0; i < targets.length; i++) {
      if (progress < targets[i]) return i;
    }
    return targets.length;
  }

  // 특정 단계의 목표치
  int getTargetForStep(int step) {
    if (step < targets.length) return targets[step];
    return targets.last;
  }

  // 특정 단계의 보상치
  int getRewardForStep(int step) {
    if (step < rewards.length) return rewards[step];
    return rewards.last;
  }
}

class AchievementData {
  static List<Achievement> list = [
    Achievement(
      id: 'destroyer',
      title: '영역의 파괴자',
      description: '몬스터를 소탕하여 평화를 가져옵니다.',
      type: AchievementType.monsterKill,
      targets: List.generate(1000, (i) => (10 * pow(i + 1, 2.1)).toInt()),
      rewards: List.generate(1000, (i) => 5 + (i * 2)),
    ),
    Achievement(
      id: 'wealthy',
      title: '황금의 손',
      description: '막대한 부를 축적합니다.',
      type: AchievementType.goldEarned,
      targets: List.generate(1000, (i) => (1000 * pow(i + 1, 2.6)).toInt()),
      rewards: List.generate(1000, (i) => 10 + (i * 5)),
    ),
    Achievement(
      id: 'veteran',
      title: '전설의 용사',
      description: '한계를 넘어 성장합니다.',
      type: AchievementType.playerLevel,
      targets: List.generate(1000, (i) => i + 2),
      rewards: List.generate(1000, (i) => 1 + (i ~/ 5)),
    ),
    Achievement(
      id: 'hoarder',
      title: '보물 사냥꾼',
      description: '필드에서 아이템을 수집합니다.',
      type: AchievementType.itemAcquired,
      targets: List.generate(1000, (i) => (5 * pow(i + 1, 1.8)).toInt()),
      rewards: List.generate(1000, (i) => 2 + i),
    ),
    Achievement(
      id: 'skilled',
      title: '마법의 대가',
      description: '스킬을 사용하여 적을 압도합니다.',
      type: AchievementType.skillUsed,
      targets: List.generate(1000, (i) => (20 * pow(i + 1, 1.9)).toInt()),
      rewards: List.generate(1000, (i) => 3 + i),
    ),
  ];
}
