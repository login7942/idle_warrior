import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:idle_warrior/providers/game_state.dart';
import 'package:idle_warrior/models/player.dart';
import 'package:idle_warrior/models/item.dart';
import 'common_widgets.dart';

/// 👤 캐릭터 정보 및 스탯을 보여주는 패널 위젯
class CharacterPanel extends StatefulWidget {
  const CharacterPanel({super.key});

  @override
  State<CharacterPanel> createState() => _CharacterPanelState();
}

class _CharacterPanelState extends State<CharacterPanel> with TickerProviderStateMixin {
  late AnimationController _heroPulseController;
  late AnimationController _heroRotateController;

  @override
  void initState() {
    super.initState();
    _heroPulseController = AnimationController(
      vsync: this, 
      duration: const Duration(seconds: 3)
    )..repeat(reverse: true);
    
    _heroRotateController = AnimationController(
      vsync: this, 
      duration: const Duration(seconds: 10)
    )..repeat();
  }

  @override
  void dispose() {
    _heroPulseController.dispose();
    _heroRotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameState>(
      builder: (context, gameState, child) {
        final player = gameState.player;
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
          child: Column(
            children: [
              // 히어로 쇼케이스 카드
              _buildHeroShowcase(player),
              const SizedBox(height: 20),
              
              // 능력치 카드 3종
              Row(
                children: [
                  Expanded(child: _buildStatCard('공격', Icons.flash_on, Colors.redAccent, [
                    _buildStatRow('공격력', player.attack.toString()),
                    _buildStatRow('공격 속도', player.attackSpeed.toStringAsFixed(2)),
                    _buildStatRow('치명타 확률', '${player.critChance.toStringAsFixed(1)}%'),
                    _buildStatRow('치명타 피해', '${player.critDamage.toInt()}%'),
                  ])),
                  const SizedBox(width: 10),
                  Expanded(child: _buildStatCard('생존', Icons.shield, Colors.blueAccent, [
                    _buildStatRow('최대 체력', player.maxHp.toString()),
                    _buildStatRow('방어력', player.defense.toString()),
                    _buildStatRow('초당 회복', '${player.hpRegen.toStringAsFixed(1)}%'),
                    _buildStatRow('회복 상한', '${player.hpRegenCap.toStringAsFixed(1)}%'),
                  ])),
                  const SizedBox(width: 10),
                  Expanded(child: _buildStatCard('성장', Icons.trending_up, Colors.lightBlueAccent, [
                    _buildStatRow('골드 획득', '+${(player.goldBonus - 100).toInt()}%'),
                    _buildStatRow('경험치 획득', '+${(player.expBonus - 100).toInt()}%'),
                    _buildStatRow('아이템 드롭', '+${(player.dropBonus - 100).toInt()}%'),
                    _buildStatRow('오프라인 효율', '${player.offEfficiency}x'),
                  ])),
                ],
              ),
              const SizedBox(height: 20),
              
              // 🆕 상세 능력치 섹션 (전투/생존 특수 옵션)
              _buildDetailedStats(player),
              const SizedBox(height: 20),

              // 자산 및 재료 요약
              _buildAssetSummary(player),
              const SizedBox(height: 20),
              
              // 🆕 세트 효과 요약
              _buildSetEffectSummary(player),

              const SizedBox(height: 120), // 하단 독 여백
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeroShowcase(player) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: 34,
      child: Column(
        children: [
          // 1. 상단 타이틀 뱃지 (이름 및 칭호)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 20, height: 1, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Colors.blueAccent]))),
              const SizedBox(width: 12),
              Column(
                children: [
                  Text(player.promotionName.toUpperCase(), style: TextStyle(color: Colors.blueAccent.withValues(alpha: 0.8), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 3)),
                  const SizedBox(height: 2),
                  ShadowText(player.name, fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
                ],
              ),
              const SizedBox(width: 12),
              Container(width: 20, height: 1, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.blueAccent, Colors.transparent]))),
            ],
          ),
          const SizedBox(height: 16),

          // 2. 메인 대시보드 (아바타 | 승급 효과 리스트)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // [좌측 영역] 캐릭터 아바타 및 이펙트
              Expanded(
                flex: 4,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // 이펙트 레이어 (사이즈 축소 260 -> 180)
                    AnimatedBuilder(
                      animation: Listenable.merge([_heroPulseController, _heroRotateController]),
                      builder: (context, _) => IgnorePointer(
                        child: CustomPaint(
                          size: const Size(180, 180),
                          painter: HeroEffectPainter(
                            promotionLevel: player.promotionLevel,
                            isPlayer: true,
                            pulse: _heroPulseController.value,
                            rotation: _heroRotateController.value,
                          ),
                        ),
                      ),
                    ),
                    // 아바타 본체 (사이즈 축소 195 -> 140)
                    AnimatedBuilder(
                      animation: _heroPulseController,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, -10 * _heroPulseController.value),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 20), 
                            child: SizedBox(
                              height: 140, 
                              child: Image.asset(
                                'assets/images/warrior.png', 
                                fit: BoxFit.contain, 
                                errorBuilder: (c, e, s) => const Icon(Icons.person, size: 60, color: Colors.white24)
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 10),

              // [우측 영역] 전체 승급 효과 리스트
              Expanded(
                flex: 6,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.stars, size: 12, color: Colors.amberAccent),
                          const SizedBox(width: 6),
                          Text('승급 보너스 리스트', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...Player.promotionSteps.skip(1).map((step) {
                        final bool isUnlocked = player.promotionLevel >= step['lv'];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.5),
                          child: Row(
                            children: [
                              // 단계 인디케이터
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isUnlocked ? Colors.blueAccent : Colors.white.withValues(alpha: 0.05),
                                ),
                                child: Center(
                                  child: Text(
                                    '${step['lv']}', 
                                    style: TextStyle(
                                      color: isUnlocked ? Colors.white : Colors.white24, 
                                      fontSize: 8, 
                                      fontWeight: FontWeight.bold
                                    )
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 효과 텍스트
                              Expanded(
                                child: Text(
                                  isUnlocked ? step['bonus'] : '보너스 ???????', 
                                  style: TextStyle(
                                    color: isUnlocked ? Colors.white : Colors.white24,
                                    fontSize: 10,
                                    fontWeight: isUnlocked ? FontWeight.bold : FontWeight.normal,
                                    letterSpacing: -0.2,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // 고정 유도 레이블 (미작성 시 ? 처리)
                              if (!isUnlocked)
                                Text('?', style: TextStyle(color: Colors.white.withValues(alpha: 0.1), fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 3. 승급 배너 버튼
          Consumer<GameState>(
            builder: (context, gameState, _) => _buildPromotionBanner(gameState),
          ),
          const SizedBox(height: 20),
          
          // 4. 전투력 요약 바
          _buildHeroScoreBar(player),
        ],
      ),
    );
  }

  Widget _buildHeroScoreBar(player) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      borderRadius: 18,
      color: Colors.white.withOpacity(0.04),
      border: Border.all(color: Colors.blueAccent.withOpacity(0.2), width: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('전투 준비 태세', style: TextStyle(color: Colors.blueAccent.withOpacity(0.6), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(height: 2),
              const ShadowText('압도적인 무력', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ],
          ),
          ShadowText('${player.combatPower}', fontSize: 32, fontWeight: FontWeight.w900, color: Colors.orangeAccent),
        ],
      ),
    );
  }

  Widget _buildDetailedStats(Player player) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.analytics_outlined, size: 18, color: Colors.cyanAccent), 
              const SizedBox(width: 10), 
              ShadowText('상세 옵션 및 버프 정보', fontSize: 16, fontWeight: FontWeight.bold)
            ]
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 전투 상세
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSubTitle('⚔️ 전투 특화'),
                    _buildStatRow('2연타 확률', '${player.doubleHitChance.toStringAsFixed(1)}%'),
                    _buildStatRow('스킬 추가 발동', '${player.skillEchoChance.toStringAsFixed(1)}%'),
                    _buildStatRow('처형 확률', '${player.executeChance.toStringAsFixed(1)}%'),
                    _buildStatRow('쿨타임 감소', '${player.cdr.toStringAsFixed(1)}%'),
                    _buildStatRow('치명타 시 쿨감', '${player.critCdrAmount.toStringAsFixed(1)}s'),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              // 2. 생존 상세
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSubTitle('🛡️ 생존 특화'),
                    _buildStatRow('피격 시 회복', '${player.recoverOnDamagedPerc.toStringAsFixed(1)}%'),
                    _buildStatRow('스킬 시 감댐', '${player.dmgReductionOnSkill.toStringAsFixed(1)}%'),
                    _buildStatRow('보호막 확률', '${player.gainShieldChance.toStringAsFixed(1)}%'),
                    _buildStatRow('모든 피해 흡혈', '${player.lifesteal.toStringAsFixed(1)}%'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white10),
          const SizedBox(height: 10),
          _buildSubTitle('🔥 아이템 옵션 버프 잠재치 (최대 보너스)'),
          Row(
            children: [
              Expanded(child: _buildStatRow('처치 시 공증', '+${player.killAtkBonus.toStringAsFixed(1)}%')),
              const SizedBox(width: 20),
              Expanded(child: _buildStatRow('처치 시 방증', '+${player.killDefBonus.toStringAsFixed(1)}%')),
            ],
          ),
          Row(
            children: [
              Expanded(child: _buildStatRow('지역 이동 공증', '+${player.zoneAtkBonus.toStringAsFixed(1)}%')),
              const SizedBox(width: 20),
              Expanded(child: _buildStatRow('지역 이동 방증', '+${player.zoneDefBonus.toStringAsFixed(1)}%')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildStatCard(String title, IconData icon, Color color, List<Widget> children) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      borderRadius: 20,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildAssetSummary(player) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.inventory, size: 18, color: Colors.orangeAccent), 
              const SizedBox(width: 10), 
              ShadowText('희귀 자원 현황', fontSize: 16, fontWeight: FontWeight.bold)
            ]
          ),
          const SizedBox(height: 20),
          Row(children: [
            _buildAssetItem(Icons.auto_awesome, '심연의 가루', player.abyssalPowder, Colors.orangeAccent),
            _buildAssetItem(Icons.diamond, '강화석', player.enhancementStone, Colors.blueAccent),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _buildAssetItem(Icons.history_edu, '재설정석', player.rerollStone, Colors.purpleAccent),
            _buildAssetItem(Icons.shield, '보호권', player.protectionStone, Colors.amberAccent),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _buildAssetItem(Icons.category, '잠재력 큐브', player.cube, Colors.redAccent),
            const Expanded(child: SizedBox()), 
          ]),
        ],
      ),
    );
  }

  Widget _buildSetEffectSummary(Player player) {
    final setCounts = player.activeSetCounts;
    if (setCounts.isEmpty) return const SizedBox.shrink();

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: 24,
      color: Colors.purpleAccent.withValues(alpha: 0.05),
      border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_motion, size: 18, color: Colors.purpleAccent), 
              const SizedBox(width: 10), 
              ShadowText('공명 중인 세트 옵션', fontSize: 16, fontWeight: FontWeight.bold)
            ]
          ),
          const SizedBox(height: 16),
          ...setCounts.entries.map((entry) {
            String setId = entry.key;
            int count = entry.value;
            String setName = Item.getSetName(setId);
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('[$setName]', style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(width: 8),
                    Text('$count/6 장착 중', style: const TextStyle(color: Colors.white24, fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 6),
                _buildSetBonusLine(setId, 2, count),
                _buildSetBonusLine(setId, 4, count),
                const SizedBox(height: 12),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildSetBonusLine(String setId, int req, int current) {
    bool isActive = current >= req;
    String bonusText = "";

    switch (setId) {
      case 'desert': bonusText = (req == 2) ? "골드/EXP +20%" : "사냥터 이동 시 30초간 ATK +30%"; break;
      case 'mine': bonusText = (req == 2) ? "방어력 +20%" : "피격 시 10% 확률로 HP 5% 회복"; break;
      case 'dimension': bonusText = (req == 2) ? "스킬 데미지 +25%" : "스킬 쿨타임 -15%"; break;
      case 'dragon': bonusText = (req == 2) ? "공격력 +30%" : "최종 피해량 증폭 +50%"; break;
      case 'ancient': bonusText = (req == 2) ? "모든 능력치 +20%" : "공격 시 5% 확률 광역 번개"; break;
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Row(
        children: [
          Icon(isActive ? Icons.check_circle : Icons.radio_button_off, size: 10, color: isActive ? Colors.greenAccent : Colors.white10),
          const SizedBox(width: 8),
          Text('$req세트: $bonusText', style: TextStyle(color: isActive ? Colors.white70 : Colors.white10, fontSize: 11)),
        ],
      ),
    );
  }


  Widget _buildAssetItem(IconData icon, String label, int count, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const Spacer(),
            Text(_formatNumber(count), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  String _formatNumber(int n) => BigNumberFormatter.format(n);

  // 🆕 [v0.5.26] 승급 배너 빌더
  Widget _buildPromotionBanner(GameState gameState) {
    final player = gameState.player;
    final int nextLv = player.promotionLevel + 1;
    final bool isMax = nextLv >= Player.promotionSteps.length;
    final int req = isMax ? 0 : Player.promotionSteps[nextLv]['req'];
    final bool canPromote = !isMax && player.totalSlotEnhanceLevel >= req;
    
    return PressableScale(
      onTap: canPromote ? () => gameState.promote() : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: canPromote 
              ? [Colors.orangeAccent, Colors.redAccent] 
              : [Colors.white.withOpacity(0.05), Colors.white.withOpacity(0.02)]
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: canPromote ? Colors.white70 : Colors.white10,
            width: 1,
          ),
          boxShadow: canPromote ? [
            BoxShadow(color: Colors.redAccent.withOpacity(0.3), blurRadius: 15, spreadRadius: 2)
          ] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isMax ? Icons.auto_awesome : (canPromote ? Icons.keyboard_double_arrow_up : Icons.lock_outline),
              size: 18, 
              color: canPromote ? Colors.white : Colors.white24
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isMax ? '최고 단계 도달' : (canPromote ? '새로운 경지 승급 가능!' : '다음 승급: ${Player.promotionSteps[nextLv]['name']}'),
                  style: TextStyle(
                    color: canPromote ? Colors.white : Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (!isMax)
                  Text(
                    '강화 총합: ${player.totalSlotEnhanceLevel} / $req',
                    style: TextStyle(
                      color: canPromote ? Colors.white70 : Colors.white24,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            if (canPromote) ...[
              const SizedBox(width: 20),
              const Icon(Icons.touch_app, size: 16, color: Colors.white70),
            ]
          ],
        ),
      ),
    );
  }
}
