import 'dart:math';

enum NPCCategory {
  offensive, // 공격형 (ATK, Crit 특화)
  defensive, // 방어형 (HP, DEF, Shield 특화)
  skill,     // 스킬형 (CDR, Skill Echo 특화)
  balanced   // 밸런스형 (균형)
}

class TournamentNPC {
  final String id;
  final String name;
  final NPCCategory category;
  final String imagePath;
  
  // 기본 전투 스탯
  late int attack;
  late int maxHp;
  late int currentHp;
  late int defense;
  
  // 특수 옵션
  late double critChance;
  late double critDamage;
  late double skillEchoChance;
  late double cdr;
  late double shieldChance;

  // 🆕 고도화된 특수 옵션 (v2.3)
  late double executeChance;    // 처형 확률
  late double lifestealPerc;    // 흡혈 (가한 데미지의 %)
  late double reflectPerc;      // 반사 (받은 데미지의 %)

  TournamentNPC({
    required this.id,
    required this.name,
    required this.category,
    this.imagePath = 'assets/images/warrior.png', 
  });

  /// 플레이어의 베이스 스탯과 배율을 기반으로 NPC 스탯 생성
  factory TournamentNPC.generate(String name, Map<String, dynamic> playerSnapshot, double scale, {bool isChampion = false}) {
    final rand = Random();
    final categories = NPCCategory.values;
    final category = categories[rand.nextInt(categories.length)];
    
    final npc = TournamentNPC(
      id: 'npc_${DateTime.now().microsecondsSinceEpoch}_${rand.nextInt(1000)}',
      name: isChampion ? '👑 $name' : name,
      category: category,
      imagePath: isChampion ? 'assets/images/monsters/chaos_knight.png' : 'assets/images/warrior.png',
    );

    // 기본 스탯 배율 적용 (라운드별 스케일 반영)
    npc.attack = (playerSnapshot['attack'] * scale).toInt();
    npc.maxHp = (playerSnapshot['maxHp'] * scale).toInt();
    npc.currentHp = npc.maxHp;
    npc.defense = (playerSnapshot['defense'] * scale).toInt();
    
    npc.critChance = playerSnapshot['critChance'] ?? 10.0;
    npc.critDamage = playerSnapshot['critDamage'] ?? 150.0;
    npc.skillEchoChance = playerSnapshot['skillEchoChance'] ?? 5.0;
    npc.cdr = playerSnapshot['cdr'] ?? 0.0;
    npc.shieldChance = playerSnapshot['shieldChance'] ?? 5.0;

    // 초기 특수 옵션
    npc.executeChance = 0.0;
    npc.lifestealPerc = 0.0;
    npc.reflectPerc = 0.0;

    // 성향(Archetype)에 따른 추가 보정
    switch (category) {
      case NPCCategory.offensive:
        npc.attack = (npc.attack * 1.2).toInt();
        npc.maxHp = (npc.maxHp * 0.8).toInt();
        npc.currentHp = npc.maxHp;
        npc.critChance += 10.0;
        npc.critDamage += 50.0;
        npc.executeChance = 5.0; // 공격형은 처형 확률 보유
        break;
      case NPCCategory.defensive:
        npc.attack = (npc.attack * 0.8).toInt();
        npc.maxHp = (npc.maxHp * 1.4).toInt();
        npc.currentHp = npc.maxHp;
        npc.defense = (npc.defense * 1.5).toInt();
        npc.shieldChance += 10.0;
        npc.reflectPerc = 15.0; // 방어형은 반사 데미지 보유
        break;
      case NPCCategory.skill:
        npc.attack = (npc.attack * 0.9).toInt();
        npc.cdr += 20.0;
        npc.skillEchoChance += 15.0;
        npc.lifestealPerc = 10.0; // 스킬형은 흡혈 보유
        break;
      case NPCCategory.balanced:
        npc.executeChance = 2.0;
        npc.lifestealPerc = 5.0;
        npc.reflectPerc = 5.0;
        break;
    }

    // 결승전 챔피언 추가 보정
    if (isChampion) {
      npc.maxHp = (npc.maxHp * 1.5).toInt();
      npc.currentHp = npc.maxHp;
      npc.attack = (npc.attack * 1.3).toInt();
      npc.shieldChance += 15.0;
      npc.executeChance += 5.0;
      npc.lifestealPerc += 10.0;
    }

    return npc;
  }
}
