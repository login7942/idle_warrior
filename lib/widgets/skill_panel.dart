import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:idle_warrior/models/skill.dart';
import 'package:idle_warrior/providers/game_state.dart';
import 'common_widgets.dart';

/// ⚡ 스킬 관련 UI를 담당하는 파일 (SkillQuickbar, SkillPanel)
/// main.dart의 부하를 줄이기 위해 분리되었습니다.

class SkillQuickbar extends StatelessWidget {
  final Animation<double> uiTicker;
  final VoidCallback onNavigateToSkillTab;

  const SkillQuickbar({
    super.key,
    required this.uiTicker,
    required this.onNavigateToSkillTab,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<GameState>(
      builder: (context, gameState, child) {
        final activeSkills = gameState.player.skills.where((s) => s.type == SkillType.active).toList();
        return Container(
          height: 80,
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (i) {
              if (i < activeSkills.length) {
                final skill = activeSkills[i];
                bool isUnlocked = skill.level > 0;
                bool canUpgrade = (gameState.player.level >= skill.unlockLevel) && (gameState.player.gold >= skill.upgradeCost);
                
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: (canUpgrade || !isUnlocked) 
                        ? onNavigateToSkillTab 
                        : (isUnlocked ? () => gameState.processCombatTurn() : null),
                      child: Container(
                        width: 50, height: 50,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: skill.isUnlocked ? Colors.white24 : Colors.white10),
                          boxShadow: skill.isUnlocked ? [BoxShadow(color: Colors.blueAccent.withValues(alpha: 0.1), blurRadius: 4)] : null,
                        ),
                        child: Stack(
                          children: [
                            Center(child: Opacity(opacity: skill.isUnlocked ? 1.0 : 0.3, child: SkillIcon(skill: skill, size: 28))),
                            if (skill.isUnlocked)
                              Positioned.fill(
                                child: AnimatedBuilder(
                                  animation: uiTicker,
                                  builder: (context, child) {
                                    final progress = skill.getCooldownProgress(gameState.player.cdr);
                                    return FractionallySizedBox(
                                      alignment: Alignment.bottomCenter,
                                      heightFactor: skill.isReady(gameState.player.cdr) ? 0.0 : (1.0 - progress),
                                      child: Container(color: Colors.black54),
                                    );
                                  },
                                ),
                              ),
                            if (skill.isUnlocked && !skill.isReady(gameState.player.cdr))
                              Center(
                                child: AnimatedBuilder(
                                  animation: uiTicker,
                                  builder: (context, child) {
                                    return Text(
                                      '${skill.getRemainingSeconds(gameState.player.cdr).toStringAsFixed(1)}s',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            if (!skill.isUnlocked)
                              Center(child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                   const Icon(Icons.lock, size: 14, color: Colors.white24),
                                   Text('Lv.${skill.unlockLevel}', style: const TextStyle(fontSize: 8, color: Colors.white24)),
                                 ],
                                )),
                            if (canUpgrade)
                              Positioned(
                                top: 4, right: 4,
                                child: Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(color: Colors.red.withValues(alpha: 0.4), blurRadius: 4, spreadRadius: 1)
                                    ],
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 0.5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: onNavigateToSkillTab,
                      child: Text(
                        isUnlocked ? 'Lv.${skill.level}' : '잠김',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isUnlocked ? Colors.white70 : Colors.white24,
                          shadows: const [Shadow(blurRadius: 2, color: Colors.black)],
                        ),
                      ),
                    ),
                  ],
                );
              }
              return Container(width: 50, height: 50, margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 15), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)), child: const Icon(Icons.add, size: 14, color: Colors.white10));
            }),
          ),
        );
      },
    );
  }
}

class SkillPanel extends StatelessWidget {
  final Function(String, {bool isError}) onShowToast;

  const SkillPanel({
    super.key,
    required this.onShowToast,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [Tab(text: '액티브 스킬'), Tab(text: '패시브 스킬')],
            indicatorColor: Colors.orangeAccent,
            labelColor: Colors.orangeAccent,
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildSkillList(context, SkillType.active),
                _buildSkillList(context, SkillType.passive),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillList(BuildContext context, SkillType type) {
    final gameState = context.watch<GameState>();
    final player = gameState.player;
    final list = player.skills.where((s) => s.type == type).toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final skill = list[i];
        bool canLevelUp = player.gold >= skill.upgradeCost;
        bool isLevelMet = player.level >= skill.unlockLevel;
        
        return GlassContainer(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          border: Border.all(color: skill.isUnlocked ? Colors.orangeAccent.withValues(alpha: 0.3) : Colors.white10),
          child: Row(
            children: [
              _buildSkillIconSlot(skill, isLevelMet),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(skill.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white)),
                        const SizedBox(width: 8),
                        if (skill.isUnlocked)
                          GlassContainer(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            borderRadius: 6,
                            color: Colors.orangeAccent.withValues(alpha: 0.2),
                            child: Text('Lv.${skill.level}', style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                          )
                        else
                          Text('해금 Lv.${skill.unlockLevel}', style: TextStyle(color: isLevelMet ? Colors.greenAccent : Colors.white24, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(skill.description, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                    const SizedBox(height: 6),
                    _buildSkillEffectInfo(player, skill),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              PopBtn(
                skill.isUnlocked ? '강화' : '개방',
                (!isLevelMet || !canLevelUp) ? Colors.grey : (skill.isUnlocked ? Colors.orangeAccent : Colors.blueAccent),
                () {
                  if (!isLevelMet) {
                    onShowToast('레벨이 부족합니다! (필요: ${skill.unlockLevel})', isError: true);
                  } else if (!canLevelUp) {
                    onShowToast('골드가 부족합니다!', isError: true);
                  } else {
                    gameState.upgradeSkill(skill);
                    onShowToast('${skill.name} 강화 성공!', isError: false);
                  }
                },
                subLabel: '${_formatNumber(skill.upgradeCost)} G',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSkillIconSlot(Skill skill, bool isLevelMet) {
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        color: Colors.black38, 
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: skill.isUnlocked ? Colors.orangeAccent.withValues(alpha: 0.5) : Colors.white10),
      ),
      child: Center(
        child: Opacity(
          opacity: isLevelMet ? 1.0 : 0.2,
          child: Text(skill.iconEmoji, style: const TextStyle(fontSize: 28)),
        ),
      ),
    );
  }

  Widget _buildSkillEffectInfo(dynamic player, Skill skill) {
    int bonus = player.potentialSkillBonus;
    double effVal;

    if (skill.isUnlocked) {
      effVal = player.getSkillValue(skill.id);
    } else {
      // 🆕 [v0.5.0] 미해금 상태일 경우 1레벨(+잠재보너스) 기준 미리보기 수치 계산
      int previewLevel = 1 + bonus;
      effVal = skill.baseValue + (previewLevel * skill.valuePerLevel);
    }

    String effectText = "";
    switch (skill.id) {
      case 'act_1': effectText = '공격력의 ${effVal.toInt()}% 피해 (3연타)'; break;
      case 'act_1_5': effectText = '공격력의 ${effVal.toInt()}% 피해 (2연타)'; break;
      case 'pas_1': effectText = '공격 속도 +${effVal.toInt()}%'; break;
      case 'act_2': effectText = '공격력의 ${effVal.toInt()}% 강력한 한방'; break;
      case 'pas_2': effectText = '방어력 +${effVal.toInt()}%'; break;
      case 'act_3': effectText = '공격력의 ${effVal.toInt()}% 및 빙결'; break;
      case 'pas_3': effectText = '골드/아이템 획득 +${effVal.toInt()}%'; break;
      case 'act_4': effectText = '공격력의 ${effVal.toInt()}% 광역 마법'; break;
      case 'pas_4': effectText = '치명타 피해 +${effVal.toInt()}%'; break;
      case 'act_5': effectText = '공격력의 ${effVal.toInt()}% 초거대 메테오'; break;
      case 'pas_5': effectText = '데미지의 ${effVal.toStringAsFixed(1)}% 체력 흡수'; break;
      case 'pas_atk': effectText = '기본 공격력 +${effVal.toInt()}%'; break;
      case 'pas_6': effectText = '스킬 재사용 대기시간 -${effVal.toInt()}%'; break;
    }

    return Row(
      children: [
        Icon(Icons.flash_on, size: 10, color: skill.isUnlocked ? Colors.cyanAccent : Colors.white10),
        const SizedBox(width: 4),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(color: skill.isUnlocked ? Colors.cyanAccent : Colors.white24, fontSize: 11, fontWeight: FontWeight.w500),
              children: [
                TextSpan(text: skill.level == 0 ? '효과: $effectText' : '현재 효과: $effectText'),
                if (bonus > 0 && skill.isUnlocked)
                  const TextSpan(text: ' (잠재 보너스 적용 중)', style: TextStyle(color: Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatNumber(int n) {
    return BigNumberFormatter.format(n);
  }
}
