import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:idle_warrior/providers/game_state.dart';
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
                    _buildStatRow('ATK', player.attack.toString()),
                    _buildStatRow('SPD', player.attackSpeed.toStringAsFixed(2)),
                    _buildStatRow('CRIT', '${player.critChance.toStringAsFixed(1)}%'),
                    _buildStatRow('C.DMG', '${player.critDamage.toInt()}%'),
                  ])),
                  const SizedBox(width: 10),
                  Expanded(child: _buildStatCard('생존', Icons.shield, Colors.blueAccent, [
                    _buildStatRow('HP', player.maxHp.toString()),
                    _buildStatRow('DEF', player.defense.toString()),
                    _buildStatRow('REGEN', '${player.hpRegen.toStringAsFixed(1)}%'),
                  ])),
                  const SizedBox(width: 10),
                  Expanded(child: _buildStatCard('성장', Icons.trending_up, Colors.lightBlueAccent, [
                    _buildStatRow('GOLD', '${player.goldBonus.toInt()}%'),
                    _buildStatRow('DROP', '${player.dropBonus.toInt()}%'),
                    _buildStatRow('OFF', '${player.offEfficiency}x'),
                  ])),
                ],
              ),
              const SizedBox(height: 20),
              
              // 자산 및 재료 요약
              _buildAssetSummary(player),
              
              const SizedBox(height: 120), // 하단 독 여백
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeroShowcase(player) {
    return GlassContainer(
      padding: const EdgeInsets.all(24),
      borderRadius: 34,
      child: Column(
        children: [
          // 상단 타이틀 뱃지
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 30, height: 1, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Colors.blueAccent]))),
              const SizedBox(width: 12),
              Column(
                children: [
                  Text('MYTHIC WARRIOR', style: TextStyle(color: Colors.blueAccent.withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 3)),
                  const SizedBox(height: 4),
                  ShadowText(player.name, fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white),
                ],
              ),
              const SizedBox(width: 12),
              Container(width: 30, height: 1, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.blueAccent, Colors.transparent]))),
            ],
          ),
          const SizedBox(height: 40),
          
          // 메인 비주얼 엔진
          Stack(
            alignment: Alignment.center,
            children: [
              // 1. 회전하는 매직 헤일로 (Back layer)
              RotationTransition(
                turns: _heroRotateController,
                child: Container(
                  width: 220, height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blueAccent.withOpacity(0.05), width: 1),
                  ),
                  child: Stack(
                    children: List.generate(4, (i) => Align(
                      alignment: Alignment(cos(i * pi/2), sin(i * pi/2)),
                      child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle)),
                    )),
                  ),
                ),
              ),
              
              // 2. 멀티 레이어 펄스 오라 (Glow layer)
              AnimatedBuilder(
                animation: _heroPulseController,
                builder: (context, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // 외곽 광원
                      Container(
                        width: 160 + (30 * _heroPulseController.value),
                        height: 160 + (30 * _heroPulseController.value),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blueAccent.withOpacity(0.12 * (1 - _heroPulseController.value)),
                              blurRadius: 60 + (40 * _heroPulseController.value),
                              spreadRadius: 5,
                            )
                          ],
                        ),
                      ),
                      // 핵심 광원
                      Container(
                        width: 100, height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.cyanAccent.withOpacity(0.15),
                              blurRadius: 30 + (10 * _heroPulseController.value),
                              spreadRadius: 2,
                            )
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),

              // 3. 부유 에너지 입자 (Particle simulation)
              ...List.generate(6, (i) => _buildHeroParticle(i)),

              // 4. 캐릭터 본체 (Breathing)
              AnimatedBuilder(
                animation: _heroPulseController,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, -8 * _heroPulseController.value),
                    child: SizedBox(
                      height: 190,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          // 캐릭터 그림자
                          Container(
                            width: 60 - (10 * _heroPulseController.value),
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3 + (0.1 * _heroPulseController.value)),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)],
                              borderRadius: const BorderRadius.all(Radius.elliptical(60, 10)),
                            ),
                          ),
                          // 캐릭터 이미지 (TODO: 경로 확인 필요. 보통 lib 상위 기준 assets)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Image.asset('assets/images/warrior.png', fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.person, size: 80, color: Colors.white24)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 40),
          
          // 전투력 요약 바
          _buildHeroScoreBar(player),
        ],
      ),
    );
  }

  // 에너지 입자 생성기
  Widget _buildHeroParticle(int index) {
    return AnimatedBuilder(
      animation: _heroPulseController,
      builder: (context, child) {
        final double speed = 0.5 + (index * 0.1);
        final double progress = (_heroPulseController.value * speed + (index / 6)) % 1.0;
        final double angle = (index * 60) * pi / 180;
        final double radius = 80 + (20 * sin(progress * pi));
        
        return Transform.translate(
          offset: Offset(cos(angle) * radius, -40 - (radius * 0.5 * progress)),
          child: Opacity(
            opacity: sin(progress * pi),
            child: Container(
              width: 3, height: 3,
              decoration: BoxDecoration(
                color: index % 2 == 0 ? Colors.cyanAccent : Colors.blueAccent,
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Colors.white, blurRadius: 4)],
              ),
            ),
          ),
        );
      },
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
              Text('COMBAT READINESS', style: TextStyle(color: Colors.blueAccent.withOpacity(0.6), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(height: 2),
              const ShadowText('OVERPOWERING', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ],
          ),
          ShadowText('${player.combatPower}', fontSize: 32, fontWeight: FontWeight.w900, color: Colors.orangeAccent),
        ],
      ),
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
            _buildAssetItem(Icons.auto_awesome, '가루', player.powder, Colors.orangeAccent),
            _buildAssetItem(Icons.diamond, '강화석', player.enhancementStone, Colors.blueAccent),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _buildAssetItem(Icons.history_edu, '재설정석', player.rerollStone, Colors.purpleAccent),
            _buildAssetItem(Icons.shield, '보호권', player.protectionStone, Colors.amberAccent),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _buildAssetItem(Icons.category, '큐브', player.cube, Colors.redAccent),
            const Expanded(child: SizedBox()), 
          ]),
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

  String _formatNumber(int n) => NumberFormat('#,###').format(n);
}
