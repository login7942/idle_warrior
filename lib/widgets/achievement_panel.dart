import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:idle_warrior/models/achievement.dart';
import 'package:idle_warrior/models/item.dart';
import 'package:idle_warrior/providers/game_state.dart';
import 'common_widgets.dart';

/// 🏆 업적 및 도감 시스템 UI 전용 파일 (AchievementPanel)
/// main.dart의 부하를 줄이기 위해 분리되었습니다.

class AchievementPanel extends StatefulWidget {
  final Function(String message, {bool isError}) onShowToast;
  final Function(String title, String subtitle) onShowSuccess;

  const AchievementPanel({
    super.key,
    required this.onShowToast,
    required this.onShowSuccess,
  });

  @override
  State<AchievementPanel> createState() => _AchievementPanelState();
}

class _AchievementPanelState extends State<AchievementPanel> {
  int _achievementMenuTab = 0; // 0: 업적 전당, 1: 장비 도감

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 메뉴 선택 버튼
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildSubTabBtn('업적 전당', 0, Icons.emoji_events),
                ),
                Expanded(
                  child: _buildSubTabBtn('장비 도감', 1, Icons.auto_stories),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: _achievementMenuTab == 0 
              ? _buildAchievementList() 
              : _buildEquipmentEncyclopedia(),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildSubTabBtn(String label, int index, IconData icon) {
    bool isSelected = _achievementMenuTab == index;
    return GestureDetector(
      onTap: () => setState(() => _achievementMenuTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected ? Border.all(color: Colors.amber.withValues(alpha: 0.5)) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.amber : Colors.white24),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(
              color: isSelected ? Colors.amberAccent : Colors.white38,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildAchievementList() {
    final gameState = context.watch<GameState>();
    final player = gameState.player;

    return ListView.builder(
      itemCount: AchievementData.list.length,
      itemBuilder: (context, index) {
        final achievement = AchievementData.list[index];
        
        int progress = 0;
        switch (achievement.type) {
          case AchievementType.monsterKill: progress = player.totalKills; break;
          case AchievementType.goldEarned: progress = player.totalGoldEarned; break;
          case AchievementType.playerLevel: progress = player.level; break;
          case AchievementType.itemAcquired: progress = player.totalItemsFound; break;
          case AchievementType.skillUsed: progress = player.totalSkillsUsed; break;
        }

        int currentStep = player.achievementSteps[achievement.id] ?? 0;
        int target = achievement.getTargetForStep(currentStep);
        double percent = (progress / target).clamp(0.0, 1.0);
        int reward = achievement.getRewardForStep(currentStep);

        return GlassContainer(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            borderRadius: 24,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ShadowText(achievement.title, fontSize: 18, fontWeight: FontWeight.bold),
                  GlassContainer(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    borderRadius: 8,
                    color: Colors.amber.withValues(alpha: 0.15),
                    child: ShadowText('${currentStep + 1}단계', color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(achievement.description, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
              const SizedBox(height: 20),
              // 프리미엄 단계 바
              Stack(
                children: [
                  Container(
                    height: 14,
                    width: double.infinity,
                    decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(7), border: Border.all(color: Colors.white10)),
                  ),
                  FractionallySizedBox(
                    widthFactor: percent,
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Colors.orange, Colors.amber]),
                        borderRadius: BorderRadius.circular(7),
                        boxShadow: [BoxShadow(color: Colors.orange.withValues(alpha: 0.3), blurRadius: 8)],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: Text('$progress / $target', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.stars, color: Colors.blueAccent, size: 14),
                      const SizedBox(width: 4),
                      Text('보상: $reward 강화석', style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  PopBtn('수령하기', percent >= 1.0 ? Colors.greenAccent : Colors.white12, () {
                    if (percent >= 1.0) {
                      gameState.claimAchievement(achievement);
                    } else {
                      widget.onShowToast('아직 목표에 도달하지 못했습니다.');
                    }
                  }),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEquipmentEncyclopedia() {
    final gameState = context.watch<GameState>();
    final player = gameState.player;

    return Column(
      children: [
        GlassContainer(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          color: Colors.cyanAccent.withValues(alpha: 0.05),
          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.2)),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   const Row(
                    children: [
                      Icon(Icons.analytics, color: Colors.cyanAccent, size: 20),
                      SizedBox(width: 8),
                      Text('현재 도감 총 보너스', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  PopBtn(
                    '일괄 수령', 
                    Colors.amberAccent, 
                    () {
                      int count = player.claimAllEncyclopediaRewards();
                      if (count > 0) {
                        gameState.claimEncyclopediaRewards();
                        widget.onShowSuccess('일괄 수령 완료', '$count개의 도감 보상을 모두 획득했습니다!');
                      } else {
                        widget.onShowToast('수령할 보상이 없습니다.');
                      }
                    },
                    icon: Icons.done_all
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  player.encyclopediaSummaryText,
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.w600, height: 1.5),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        
        Expanded(
          child: ListView.builder(
            itemCount: 6, // T1 ~ T6
            itemBuilder: (context, index) {
              int tier = index + 1;
              return _buildTierSection(gameState, tier);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTierSection(GameState gameState, int tier) {
    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderRadius: 16,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TIER $tier 장비 도감', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              _buildProgressBadge(gameState, tier),
            ],
          ),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.85,
            children: ItemType.values.map((type) => _buildEncyclopediaItemIcon(gameState, tier, type)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBadge(GameState gameState, int tier) {
    final player = gameState.player;
    int total = 6 * 21; // 6종 * (0~20강)
    int completed = 0;
    
    for (var type in ItemType.values) {
      String key = 'T${tier}_${type.name}';
      completed += player.encyclopediaClaims[key]?.length ?? 0;
    }
    
    double percent = completed / total;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.cyanAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('${(percent * 100).toInt()}%', style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildEncyclopediaItemIcon(GameState gameState, int tier, ItemType type) {
    final player = gameState.player;
    String key = 'T${tier}_${type.name}';
    int maxLevelAchieved = player.encyclopediaProgress[key] ?? -1;
    bool hasUnlockedAny = maxLevelAchieved >= 0;
    
    int claimedCount = player.encyclopediaClaims[key]?.length ?? 0;
    bool hasRewardToClaim = (maxLevelAchieved + 1) > claimedCount;

    return GestureDetector(
      onTap: () => _showEncyclopediaDetail(context, gameState, tier, type),
      child: GlassContainer(
        padding: const EdgeInsets.all(8),
        borderRadius: 12,
        color: hasUnlockedAny ? Colors.white.withValues(alpha: 0.05) : Colors.black26,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.topRight,
              children: [
                ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    hasUnlockedAny ? Colors.transparent : Colors.grey,
                    hasUnlockedAny ? BlendMode.dst : BlendMode.saturation,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [ItemIcon(type: type, size: 28, color: hasUnlockedAny ? null : Colors.white24)],
                  ),
                ),
                if (hasRewardToClaim)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(_getItemTypeName(type), style: TextStyle(color: hasUnlockedAny ? Colors.white70 : Colors.white24, fontSize: 11)),
            Text('$claimedCount/21', style: TextStyle(color: hasUnlockedAny ? Colors.cyanAccent : Colors.white10, fontSize: 9, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  String _getItemTypeName(ItemType type) {
    switch (type) {
      case ItemType.weapon: return '무기';
      case ItemType.helmet: return '투구';
      case ItemType.armor: return '갑옷';
      case ItemType.boots: return '신발';
      case ItemType.ring: return '반지';
      case ItemType.necklace: return '목걸이';
    }
  }

  void _showEncyclopediaDetail(BuildContext context, GameState gameState, int tier, ItemType type) {
    String key = 'T${tier}_${type.name}';
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          int currentMax = gameState.player.encyclopediaProgress[key] ?? -1;
          List<int> claimed = gameState.player.encyclopediaClaims[key] ?? [];

          return AlertDialog(
            backgroundColor: const Color(0xFF161B2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                ItemIcon(type: type, size: 24, color: Colors.cyanAccent),
                const SizedBox(width: 12),
                Text('T$tier ${_getItemTypeName(type)} 도감', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: GridView.builder(
                shrinkWrap: true,
                itemCount: 21,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (context, lv) {
                  bool isReached = lv <= currentMax;
                  bool isClaimed = claimed.contains(lv);
                  
                  return GestureDetector(
                    onTap: () {
                      if (isReached && !isClaimed) {
                        gameState.claimEncyclopediaRewards(); // logic is claim all for now in GameState, but we can call it or specific
                        setDialogState(() {});
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isClaimed 
                          ? Colors.cyanAccent.withOpacity(0.1) 
                          : (isReached ? Colors.orangeAccent.withOpacity(0.1) : Colors.white10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isClaimed 
                            ? Colors.cyanAccent.withOpacity(0.5) 
                            : (isReached ? Colors.orangeAccent.withOpacity(0.5) : Colors.transparent),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('+$lv', style: TextStyle(
                            color: isReached ? Colors.white : Colors.white24,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          )),
                          if (isClaimed)
                            const Icon(Icons.check_circle, color: Colors.cyanAccent, size: 12)
                          else if (isReached)
                            const Icon(Icons.card_giftcard, color: Colors.orangeAccent, size: 12)
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기', style: TextStyle(color: Colors.white60))),
            ],
          );
        }
      ),
    );
  }
}
