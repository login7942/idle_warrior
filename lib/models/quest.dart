import 'package:flutter/material.dart';

enum QuestType {
  equip,          // 아이템 장착
  learnSkill,     // 스킬 습득/레벨업
  enhanceItem,    // 아이템 개별 강화 도달
  enhanceSlot,    // 슬롯 강화 (개별/누적)
  totalSlotEnhance, // 슬롯 강화 레벨 총합 🆕
  summonPet,      // 펫 소환
  reachStage,     // 스테이지 도달
  dismantle,      // 아이템 분해
  encyclopedia,   // 도감 수령
  reroll,         // 옵션 재설정
  promotion,       // 캐릭터 승급 🆕
}

class QuestReward {
  final int gold;
  final int stone;
  final int powder;
  final int shards;
  final int cube;
  final int soulStone;

  const QuestReward({
    this.gold = 0,
    this.stone = 0,
    this.powder = 0,
    this.shards = 0,
    this.cube = 0,
    this.soulStone = 0,
  });
}

class Quest {
  final String id;
  final String title;
  final String description;
  final QuestType type;
  final int targetValue; // 목표 수치
  final QuestReward reward;

  Quest({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.targetValue,
    required this.reward,
  });
}

class GuideQuestData {
  static final List<Quest> quests = [
    Quest(
      id: 'q1',
      title: '첫 걸음: 장비 장착',
      description: '인벤토리에서 아이템을 착용하세요.',
      type: QuestType.equip,
      targetValue: 1,
      reward: QuestReward(gold: 10000, stone: 20),
    ),
    Quest(
      id: 'q2',
      title: '영역 확장: 스테이지 20',
      description: '스테이지 20을 돌파하여 기지를 넓히세요.',
      type: QuestType.reachStage,
      targetValue: 20,
      reward: QuestReward(gold: 30000, shards: 200),
    ),
    Quest(
      id: 'q3',
      title: '기술 습득: 스킬 배우기',
      description: '스킬 탭의 첫 번째 스킬을 배우세요.',
      type: QuestType.learnSkill,
      targetValue: 1,
      reward: QuestReward(gold: 20000, stone: 50),
    ),
    Quest(
      id: 'q4',
      title: '동료의 힘: 펫 소환',
      description: '펫 탭에서 첫 번째 동료를 소환하세요.',
      type: QuestType.summonPet,
      targetValue: 1,
      reward: QuestReward(gold: 50000, soulStone: 10),
    ),
    Quest(
      id: 'q5',
      title: '성장의 토대: 슬롯 50강',
      description: '슬롯 강화 총합 50강을 달성하세요.',
      type: QuestType.totalSlotEnhance,
      targetValue: 50,
      reward: QuestReward(gold: 100000, shards: 500),
    ),
    Quest(
      id: 'q6',
      title: '장비 연마: +5강 달성',
      description: '해금된 아이템 강화를 통해 +5강을 만드세요.',
      type: QuestType.enhanceItem,
      targetValue: 5,
      reward: QuestReward(gold: 150000, stone: 100),
    ),
    Quest(
      id: 'q7',
      title: '심화 수련: 슬롯 300강',
      description: '슬롯 강화 총합 300강을 달성하세요.',
      type: QuestType.totalSlotEnhance,
      targetValue: 300,
      reward: QuestReward(gold: 500000, cube: 10),
    ),
    Quest(
      id: 'q8',
      title: '운명의 변화: 옵션 재설정',
      description: '해금된 옵션 재설정을 1회 진행하세요.',
      type: QuestType.reroll,
      targetValue: 1,
      reward: QuestReward(gold: 300000, powder: 1000),
    ),
    Quest(
      id: 'q9',
      title: '한계 돌파: 캐릭터 승급',
      description: '캐릭터 상세에서 첫 번째 승급을 달성하세요.',
      type: QuestType.promotion,
      targetValue: 1,
      reward: QuestReward(gold: 1000000, shards: 2000),
    ),
    Quest(
      id: 'q10',
      title: '지식의 기록: 도감 수령',
      description: '도감의 모든 보상을 수령해 보세요.',
      type: QuestType.encyclopedia,
      targetValue: 1,
      reward: QuestReward(gold: 200000, cube: 15),
    ),
    Quest(
      id: 'q11',
      title: '재활용: 아이템 분해',
      description: '사용하지 않는 아이템을 분해하세요.',
      type: QuestType.dismantle,
      targetValue: 1,
      reward: QuestReward(gold: 100000, powder: 2000),
    ),
  ];
}

