import 'package:flutter/material.dart';

enum QuestType {
  equip,          // 아이템 장착
  learnSkill,     // 스킬 습득/레벨업
  learnActiveSkill, // 액티브 스킬 습득 🆕
  learnPassiveSkill, // 패시브 스킬 습득 🆕
  enhanceItem,    // 아이템 개별 강화 도달
  enhanceSlot,    // 슬롯 강화 (개별/누적)
  totalSlotEnhance, // 슬롯 강화 레벨 총합 🆕
  summonPet,      // 펫 소환
  reachStage,     // 스테이지 도달
  dismantle,      // 아이템 분해
  encyclopedia,   // 도감 수령
  reroll,         // 옵션 재설정
  promotion,       // 캐릭터 승급 🆕
  enhanceAttempt,  // 장비 강화 시도 🆕
  reachTowerFloor, // 무한의 탑 층 도달 🆕
  craftItem,      // 아이템 제작 🆕
  craftGoldTicket, // 황금의 방 입장권 제작 🆕
  craftTrialTicket, // 시련의 방 입장권 제작 🆕
  enterGoldDungeon, // 황금의 방 입장 🆕
  enterTrialDungeon, // 시련의 방 입장 🆕
  itemPromotion,  // 아이템 승급 🆕
  changeName,     // 캐릭터 이름 변경 🆕
}

class QuestReward {
  final int gold;
  final int stone;
  final int abyssalPowder;
  final int shards;
  final int cube;
  final int soulStone;
  final int protectionStone; // 🆕

  const QuestReward({
    this.gold = 0,
    this.stone = 0,
    this.abyssalPowder = 0,
    this.shards = 0,
    this.cube = 0,
    this.soulStone = 0,
    this.protectionStone = 0,
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
      id: 'q0',
      title: '첫 인사: 이름 설정',
      description: '캐릭터 탭에서 이름을 변경하세요.',
      type: QuestType.changeName,
      targetValue: 1,
      reward: QuestReward(gold: 10000, stone: 20),
    ),
    Quest(
      id: 'q1',
      title: '첫 걸음: 장비 장착',
      description: '인벤토리에서 아이템을 착용하세요.',
      type: QuestType.equip,
      targetValue: 1,
      reward: QuestReward(gold: 20000, stone: 50),
    ),
    Quest(
      id: 'q3',
      title: '기술 습득: 액티브 스킬',
      description: '스킬 탭에서 액티브 스킬을 1회 배우거나 강화하세요.',
      type: QuestType.learnActiveSkill,
      targetValue: 1,
      reward: QuestReward(gold: 50000, stone: 100),
    ),
    Quest(
      id: 'q11',
      title: '재활용: 아이템 분해',
      description: '사용하지 않는 아이템을 분해하세요.',
      type: QuestType.dismantle,
      targetValue: 1,
      reward: QuestReward(gold: 200000, abyssalPowder: 3000),
    ),
    Quest(
      id: 'q2',
      title: '영역 확장: 스테이지 10',
      description: '스테이지 10을 돌파하여 기지를 넓히세요.',
      type: QuestType.reachStage,
      targetValue: 10,
      reward: QuestReward(gold: 100000, shards: 500),
    ),
    Quest(
      id: 'q17',
      title: '기술 심화: 패시브 스킬',
      description: '스킬 탭에서 패시브 스킬을 1회 배우거나 강화하세요.',
      type: QuestType.learnPassiveSkill,
      targetValue: 1,
      reward: QuestReward(gold: 300000, stone: 500),
    ),
    Quest(
      id: 'q5',
      title: '성장의 토대: 슬롯 10강',
      description: '슬롯 강화 총합 10강을 달성하세요.',
      type: QuestType.totalSlotEnhance,
      targetValue: 10,
      reward: QuestReward(gold: 500000, shards: 1000),
    ),
    Quest(
      id: 'q6',
      title: '장비 연마: +5강 달성',
      description: '해금된 아이템 강화를 통해 +5강을 만드세요.',
      type: QuestType.enhanceItem,
      targetValue: 5,
      reward: QuestReward(gold: 800000, stone: 300),
    ),
    Quest(
      id: 'q10',
      title: '지식의 기록: 도감 수령',
      description: '도감의 모든 보상을 수령해 보세요.',
      type: QuestType.encyclopedia,
      targetValue: 1,
      reward: QuestReward(gold: 1500000, cube: 20),
    ),
    Quest(
      id: 'q12',
      title: '장비 연마의 길: 강화 시도',
      description: '장비 강화를 30회 시도하여 숙련도를 높이세요.',
      type: QuestType.enhanceAttempt,
      targetValue: 30,
      reward: QuestReward(gold: 2000000, stone: 1000),
    ),
    Quest(
      id: 'q13',
      title: '시련의 증표: 무한의 탑',
      description: '사냥터-무한의 탑에 도전하여 영혼석을 획득하세요!',
      type: QuestType.reachTowerFloor,
      targetValue: 1,
      reward: QuestReward(gold: 2500000, soulStone: 30),
    ),
    Quest(
      id: 'q4',
      title: '동료의 힘: 펫 소환',
      description: '펫 탭에서 첫 번째 동료를 소환하세요.',
      type: QuestType.summonPet,
      targetValue: 1,
      reward: QuestReward(gold: 3000000, soulStone: 20),
    ),
    Quest(
      id: 'q9',
      title: '한계 돌파: 캐릭터 승급',
      description: '캐릭터 상세에서 첫 번째 승급을 달성하세요.',
      type: QuestType.promotion,
      targetValue: 1,
      reward: QuestReward(gold: 3500000, shards: 3000),
    ),
    Quest(
      id: 'q8',
      title: '운명의 변화: 옵션 재설정',
      description: '해금된 옵션 재설정을 1회 진행하세요.',
      type: QuestType.reroll,
      targetValue: 1,
      reward: QuestReward(gold: 4000000, abyssalPowder: 10000),
    ),
    Quest(
      id: 'q14',
      title: '풍요의 열쇠: 황금 입장권',
      description: '제작 탭에서 황금의 방 입장권을 1회 제작해 보세요.',
      type: QuestType.craftGoldTicket,
      targetValue: 1,
      reward: QuestReward(gold: 4500000, cube: 30),
    ),
    Quest(
      id: 'q18',
      title: '황금의 유혹: 황금의 방',
      description: '제작한 입장권을 사용하여 황금의 방에 들어가보세요.',
      type: QuestType.enterGoldDungeon,
      targetValue: 1,
      reward: QuestReward(gold: 500000, stone: 500),
    ),
    Quest(
      id: 'q19',
      title: '시련의 준비: 시련 입장권',
      description: '제작 탭에서 시련의 방 입장권을 1회 제작해 보세요.',
      type: QuestType.craftTrialTicket,
      targetValue: 1,
      reward: QuestReward(gold: 5000000, cube: 40),
    ),
    Quest(
      id: 'q20',
      title: '시련의 돌파: 시련의 방',
      description: '시련의 방에 입장하여 장비 강화 재료를 수급하세요.',
      type: QuestType.enterTrialDungeon,
      targetValue: 1,
      reward: QuestReward(gold: 600000, stone: 1000),
    ),
    Quest(
      id: 'q15',
      title: '정점의 무기: +20강 달성',
      description: '장비 강화를 통해 아이템 레벨을 +20까지 끌어올리세요.',
      type: QuestType.enhanceItem,
      targetValue: 20,
      reward: QuestReward(gold: 5500000, protectionStone: 5),
    ),
    Quest(
      id: 'q16',
      title: '진화의 정점: 장비 승급',
      description: '+20강 장비를 재료를 사용하여 다음 티어로 승급시키세요.',
      type: QuestType.itemPromotion,
      targetValue: 1,
      reward: QuestReward(gold: 6000000, cube: 50, protectionStone: 5),
    ),
  ];


}

