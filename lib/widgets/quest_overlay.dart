import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_state.dart';
import '../models/quest.dart';
import '../models/hunting_zone.dart';
import 'common_widgets.dart'; // ShadowText 등 사용

class QuestOverlay extends StatelessWidget {
  const QuestOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameState>(
      builder: (context, gameState, child) {
        final player = gameState.player;
        if (player.currentQuestIndex >= GuideQuestData.quests.length) {
          return const SizedBox.shrink();
        }

        final quest = GuideQuestData.quests[player.currentQuestIndex];
        final isClaimable = player.isQuestRewardClaimable;

        return GestureDetector(
          onTap: isClaimable ? () => gameState.claimQuestReward() : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 180, // 너비 축소
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // 패딩 축소
            decoration: BoxDecoration(
              // 유리 질감 (Glassmorphism) 효과
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isClaimable 
                  ? Colors.amberAccent.withOpacity(0.8) 
                  : Colors.white.withOpacity(0.1),
                width: 1.2,
              ),
              boxShadow: [
                if (isClaimable)
                  BoxShadow(
                    color: Colors.amberAccent.withOpacity(0.2),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      isClaimable ? Icons.card_giftcard : Icons.explore,
                      color: isClaimable ? Colors.amberAccent : Colors.blueAccent,
                      size: 14, // 아이콘 축소
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        isClaimable ? '보상 받기!' : '길잡이',
                        style: TextStyle(
                          color: isClaimable ? Colors.amberAccent : Colors.white60,
                          fontSize: 10, // 폰트 축소
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        quest.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // 🆕 진행도 표시 (실시간 수치 반영)
                    if (!isClaimable)
                      Builder(
                        builder: (context) {
                          int currentVal = 0;
                          switch (quest.type) {
                            case QuestType.reachStage: currentVal = gameState.currentStage; break;

                            case QuestType.totalSlotEnhance: currentVal = player.totalSlotEnhanceLevel; break;
                            case QuestType.promotion: currentVal = player.promotionLevel; break;
                            case QuestType.enhanceItem: 
                              currentVal = player.equipment.values
                                .where((i) => i != null)
                                .fold(0, (maxVal, i) => i!.enhanceLevel > maxVal ? i.enhanceLevel : maxVal);
                              break;
                            case QuestType.enhanceSlot:
                              currentVal = player.slotEnhanceLevels.values
                                .fold(0, (maxVal, lv) => lv > maxVal ? lv : maxVal);
                              break;
                            case QuestType.learnSkill:
                              // 습득한 스킬 중 가장 높은 레벨 기준
                              currentVal = player.skills.isEmpty ? 0 : player.skills.fold(0, (maxVal, s) => s.level > maxVal ? s.level : maxVal);
                              break;
                            case QuestType.enhanceAttempt:
                              currentVal = player.totalEnhanceAttempts;
                              break;
                            case QuestType.summonPet:
                              currentVal = player.pets.length;
                              break;
                            case QuestType.dismantle:
                              // 분해를 수행하기 전까지는 0으로 표시
                              currentVal = 0;
                              break;
                            case QuestType.encyclopedia:
                              currentVal = 0; // 수동 수령 전까지 0
                              break;
                            case QuestType.reroll:
                              currentVal = 0; // 수동 재설정 전까지 0
                              break;
                            case QuestType.reachTowerFloor:
                              // 무한의 탑 현재 층 정보가 있다면 반영
                              currentVal = gameState.currentZone.id == ZoneId.tower ? gameState.currentStage : 0;
                              break;
                            case QuestType.craftItem:
                              // 제작 퀘스트 (현재는 T2 제작 q14 하나임)
                              // player에 누적 제작 횟수 기록이 없으므로 일단 0으로 표시 (수정 대상)
                              currentVal = 0;
                              break;
                            case QuestType.equip:
                              // 장착을 수행하기 전까지는 0으로 표시 (기존 장착 아이템 무시)
                              currentVal = 0;
                              break;
                            default: currentVal = 0;
                          }

                          // 퀘스트 완료 조건이 충족되었으나 수령 전인 경우 강제로 타겟값 표시
                          if (isClaimable) currentVal = quest.targetValue;
                          
                          // 장착, 소환, 분해 등 단발성 액션(목표 1)은 0 / 1 표시
                          // 그 외(레벨 등 누적형)는 진행도 수치 표시
                          String progressText = '$currentVal / ${quest.targetValue}';

                          return Text(
                            progressText, 
                            style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                          );

                        }
                      ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  quest.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isClaimable ? Colors.amberAccent.withOpacity(0.8) : Colors.white.withOpacity(0.6),
                    fontSize: 10,
                  ),
                ),


                if (isClaimable) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Center(
                      child: Text(
                        '터치하여 수령',
                        style: TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );

      },
    );
  }
}
