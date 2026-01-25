import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:idle_warrior/models/pet.dart';
import 'package:idle_warrior/providers/game_state.dart';
import 'common_widgets.dart';

/// 🐾 펫 시스템 UI 전용 파일 (PetPanel)
/// main.dart의 다이어트를 위해 분리되었습니다.

class PetPanel extends StatefulWidget {
  const PetPanel({super.key});

  @override
  State<PetPanel> createState() => _PetPanelState();
}

class _PetPanelState extends State<PetPanel> {
  int _petFilterIdx = 0; // 0: 전체, 1: 일반, 2: 고급, 3: 희귀, 4: 고대의, 5: 유물의, 6: 전설의

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          _buildPetUnifiedDashboard(),
          const SizedBox(height: 12),
          _buildPetFilterArea(),
          const SizedBox(height: 12),
          Expanded(child: _buildOwnedPetGrid()),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildPetUnifiedDashboard() {
    return Consumer<GameState>(
      builder: (context, gameState, child) {
        final activePet = gameState.player.activePet;
        return GlassContainer(
          padding: const EdgeInsets.all(12),
          borderRadius: 24,
          border: Border.all(color: activePet?.grade.color.withOpacity(0.3) ?? Colors.white10),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: activePet?.grade.bgGradient,
                      color: activePet == null ? Colors.white10 : null,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Center(
                      child: Text(
                        activePet?.iconEmoji ?? '❔',
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ShadowText(
                              activePet?.name ?? '동행 펫 없음',
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: activePet?.grade.color ?? Colors.white60,
                            ),
                            Row(
                              children: [
                                const Icon(Icons.auto_awesome_motion, color: Colors.purpleAccent, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  '영혼석: ${gameState.player.soulStone}',
                                  style: const TextStyle(color: Colors.purpleAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              gameState.player.petSummaryText,
                              style: TextStyle(color: Colors.orangeAccent.withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          activePet != null 
                            ? '동행 효과: ${activePet.companionSkillName} (${activePet.companionValue.toStringAsFixed(1)}%)'
                            : '펫을 동행시키면 특수 효과가 활성화됩니다.',
                          style: TextStyle(color: activePet != null ? Colors.cyanAccent : Colors.white24, fontSize: 10, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 14),
                      SizedBox(width: 6),
                      Text('펫 소환', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Row(
                    children: [
                      _buildSlimSummonBtn(context, '1회', () => gameState.summonPet(1), '10,000 G + 👻1'),
                      const SizedBox(width: 8),
                      _buildSlimSummonBtn(context, '10회', () => gameState.summonPet(10), '90,000 G + 👻1', isHighlight: true),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSlimSummonBtn(BuildContext context, String label, VoidCallback onTap, String cost, {bool isHighlight = false}) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isHighlight ? Colors.deepPurple.withOpacity(0.3) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isHighlight ? Colors.deepPurpleAccent.withOpacity(0.5) : Colors.white10),
        ),
        child: Row(
          children: [
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Text(cost, style: TextStyle(color: isHighlight ? Colors.amberAccent : Colors.white38, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _buildPetFilterArea() {
    final List<String> filters = ['전체', '일반', '고급', '희귀', '고대의', '유물의', '전설의'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(filters.length, (index) {
          bool isSelected = _petFilterIdx == index;
          Color filterColor = Colors.white24;
          if (index > 0) {
            filterColor = PetGrade.values[index - 1].color;
          }

          return GestureDetector(
            onTap: () => setState(() => _petFilterIdx = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? filterColor.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? filterColor : Colors.white10,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Text(
                filters[index],
                style: TextStyle(
                  color: isSelected ? filterColor : Colors.white38,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildOwnedPetGrid() {
    return Consumer<GameState>(
      builder: (context, gameState, child) {
        final player = gameState.player;
        final List<Pet> allInitialPets = PetData.getInitialPets();
        List<Pet> displayPets = allInitialPets.where((p) {
          if (_petFilterIdx == 0) return true;
          return p.grade == PetGrade.values[_petFilterIdx - 1];
        }).toList();

        if (displayPets.isEmpty) {
          return const Center(child: Text('해당 등급의 펫이 없습니다.', style: TextStyle(color: Colors.white24)));
        }

        return GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.82,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: displayPets.length,
          itemBuilder: (context, index) {
            final petData = displayPets[index];
            final ownedPet = player.pets.firstWhere((p) => p.id == petData.id, orElse: () => petData);
            bool isOwned = player.pets.any((p) => p.id == petData.id);
            bool isActive = player.activePet?.id == petData.id;

            return _buildPetCard(context, gameState, ownedPet, isOwned, isActive);
          },
        );
      },
    );
  }

  Widget _buildPetCard(BuildContext context, GameState gameState, Pet pet, bool isOwned, bool isActive) {
    return PressableScale(
      onTap: () => _showPetDetailDialog(context, gameState, pet, isOwned, isActive),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: isOwned ? pet.grade.bgGradient : null,
          color: isOwned ? null : Colors.black45,
          border: Border.all(
            color: isActive ? Colors.cyanAccent : (isOwned ? pet.grade.color.withOpacity(0.5) : Colors.white10),
            width: isActive ? 2 : 1.2,
          ),
          boxShadow: [
            if (isActive)
              BoxShadow(color: Colors.cyanAccent.withOpacity(0.3), blurRadius: 10, spreadRadius: 1),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   ColorFiltered(
                    colorFilter: isOwned 
                      ? const ColorFilter.mode(Colors.transparent, BlendMode.multiply)
                      : const ColorFilter.matrix([
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0, 0, 0, 1, 0,
                        ]),
                    child: Text(pet.iconEmoji, style: const TextStyle(fontSize: 32)),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      pet.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isOwned ? Colors.white : Colors.white24,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (isOwned)
                    Text(
                      'Lv.${pet.level}',
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                ],
              ),
            ),
            if (!isOwned)
              const Positioned(
                top: 6, right: 6,
                child: Icon(Icons.lock, color: Colors.white24, size: 12),
              ),
            if (isActive)
              Positioned(
                top: 0, left: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: const BoxDecoration(
                    color: Colors.cyanAccent,
                    borderRadius: BorderRadius.only(bottomRight: Radius.circular(10)),
                  ),
                  child: const Text('ON', style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.w900)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showPetDetailDialog(BuildContext context, GameState gameState, Pet pet, bool isOwned, bool isActive) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) => Container(),
      transitionBuilder: (context, anim1, anim2, child) {
        return Transform.scale(
          scale: anim1.value,
          child: Opacity(
            opacity: anim1.value,
            child: AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: pet.grade.color.withValues(alpha: 0.5))),
              contentPadding: EdgeInsets.zero,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: pet.grade.bgGradient,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Column(
                      children: [
                        Text(pet.iconEmoji, style: const TextStyle(fontSize: 60)),
                        const SizedBox(height: 12),
                        ShadowText(pet.name, fontSize: 24, fontWeight: FontWeight.bold),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.24), borderRadius: BorderRadius.circular(12)),
                          child: Text(pet.grade.name, style: TextStyle(color: pet.grade.color, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pet.description, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 20),
                        _buildDetailInfoTile('보유 효과', [
                          if (pet.ownAtkMultiplier > 0) '공격력 +${pet.currentAtkBonus.toStringAsFixed(1)}%',
                          if (pet.ownHpMultiplier > 0) '체력 +${pet.currentHpBonus.toStringAsFixed(1)}%',
                          if (pet.ownGoldMultiplier > 0) '골드 +${pet.currentGoldBonus.toStringAsFixed(1)}%',
                        ], Colors.orangeAccent),
                        const SizedBox(height: 12),
                        _buildDetailInfoTile('동행 효과 (${pet.companionSkillName})', [
                          pet.companionSkillDesc,
                          if (pet.companionValue > 0) '기준 수치: ${pet.companionValue.toStringAsFixed(1)}%',
                        ], Colors.cyanAccent),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: PopBtn('닫기', Colors.white10, () => Navigator.pop(context)),
                            ),
                            if (isOwned) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: PopBtn(
                                  isActive ? '해제' : '동행',
                                  isActive ? Colors.redAccent : Colors.greenAccent,
                                  () {
                                    gameState.togglePetActive(pet);
                                    Navigator.pop(context);
                                  }
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailInfoTile(String title, List<String> details, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 3, height: 14, color: color),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 6),
        ...details.map((d) => Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 2),
          child: Text('• $d', style: const TextStyle(color: Colors.white60, fontSize: 12)),
        )),
      ],
    );
  }
}
