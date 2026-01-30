import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:idle_warrior/models/player.dart';
import 'package:idle_warrior/models/item.dart';
import 'package:idle_warrior/providers/game_state.dart';
import 'character_panel.dart';
import 'common_widgets.dart';
import 'quick_menu_panel.dart'; // 🆕 통합 메뉴 임포트

// =============================================================================
// [InventoryPanel]
// 사용자의 아이템 목록을 관리하고 장착 상태를 확인하며, 아이템 강화/분해/재설정을 
// 수행할 수 있는 메인 인벤토리 화면입니다.
// =============================================================================

/// 🎒 인벤토리 전용 패널 위젯
class InventoryPanel extends StatefulWidget {
  final Function(String, {bool isError})? onShowToast;
  const InventoryPanel({super.key, this.onShowToast});

  @override
  State<InventoryPanel> createState() => _InventoryPanelState();
}

class _InventoryPanelState extends State<InventoryPanel> {
  ItemType? _inventoryFilter;
  int _inventorySortMode = 0; // 0: 등급순, 1: 전투력순, 2: 강화순
  bool _isInventoryScrolling = false;
  Timer? _scrollStopTimer;

  @override
  void dispose() {
    _scrollStopTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameState>(
      builder: (context, gameState, child) {
        final player = gameState.player;
        return Column(
          children: [
            const SizedBox(height: 12),
            _buildResourceBar(player),
            _buildEquippedSlots(player),
            _buildInventoryControls(gameState),
            Expanded(child: _buildInventoryGrid(gameState)),
            const SizedBox(height: 100), // 하단 독 공간
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // [UI Builders] - 메인 섹션 빌더
  // ---------------------------------------------------------------------------

  Widget _buildResourceBar(Player player) {
    return GlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderRadius: 20,
      color: Colors.white.withOpacity(0.04),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('보유 재화', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
              Text(
                '가방 ${player.inventory.length}/${player.maxInventory}',
                style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildCompactResource('✨', player.abyssalPowder, Colors.orangeAccent),
              _buildCompactResource('💎', player.enhancementStone, Colors.blueAccent),
              _buildCompactResource('🎲', player.rerollStone, Colors.purpleAccent),
              _buildCompactResource('🛡️', player.protectionStone, Colors.amberAccent),
              _buildCompactResource('🔮', player.cube, Colors.redAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactResource(String emoji, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        Text(
          _formatNumber(count),
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }



  Widget _buildDismantleSlider({
    required String label,
    required double value,
    required double max,
    required int divisions,
    required List<String> labels,
    required Function(double) onChanged,
    required Color activeColor,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
            Text(
              (value.toInt() >= 0 && value.toInt() < labels.length) ? labels[value.toInt()] : "??",
              style: TextStyle(color: value == 0 ? Colors.white24 : activeColor, fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: activeColor.withOpacity(0.5),
            inactiveTrackColor: Colors.white.withOpacity(0.05),
            thumbColor: activeColor,
            overlayColor: activeColor.withOpacity(0.1),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2),
            activeTickMarkColor: activeColor,
            inactiveTickMarkColor: Colors.white24,
          ),
          child: Slider(
            value: value,
            min: 0,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildEquippedSlots(Player player) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: ItemType.values.map((type) {
          final item = player.equipment[type];
          final slotLevel = player.slotEnhanceLevels[type] ?? 0;
          bool isEmpty = item == null;
          double slotSize = 52.0;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(
              children: [
                isEmpty 
                  ? SizedBox(
                      width: slotSize, height: slotSize,
                      child: GlassContainer(
                        borderRadius: 14,
                        color: Colors.black26,
                        border: Border.all(color: Colors.white10),
                        child: Center(
                          child: Opacity(
                            opacity: 0.5,
                            child: EmptyItemIcon(type: type, size: slotSize * 0.45)
                          )
                        ),
                      ),
                    )
                  : PremiumItemSlot(
                      item: item, 
                      size: slotSize,
                      onTap: () {
                        final equipList = ItemType.values.map((t) => player.equipment[t]).whereType<Item>().toList();
                        _showItemDetail(item, equipList);
                      },
                    ),
                const SizedBox(height: 8),
                // 하단 강화 레벨 버튼
                PressableScale(
                  onTap: () => _showSlotEnhanceDialog(type),
                  child: Container(
                    width: slotSize + 4,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: slotLevel > 0 ? Colors.blueAccent.withOpacity(0.5) : Colors.white10,
                        width: 1
                      ),
                      boxShadow: slotLevel > 0 ? [
                        BoxShadow(color: Colors.blueAccent.withOpacity(0.2), blurRadius: 4, spreadRadius: 0),
                      ] : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '+$slotLevel',
                      style: TextStyle(
                        color: slotLevel > 0 ? Colors.blueAccent : Colors.white38, 
                        fontSize: 10, 
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInventoryControls(GameState gameState) {
    bool isAutoActive = gameState.autoDismantleGrade != -1 && gameState.autoDismantleTier != -1;
    
    return GlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      borderRadius: 24,
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(null, '전체'),
                ...ItemType.values.map((t) => _buildFilterChip(t, t.nameKr)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSortBtn('등급순', 0, Icons.sort),
              const SizedBox(width: 8),
              _buildSortBtn('전투력순', 1, Icons.bolt),
              const SizedBox(width: 8),
              _buildSortBtn('강화순', 2, Icons.upgrade),
              const SizedBox(width: 8),
              // 자동 분해 설정 버튼 -> 🆕 통합 메뉴로 연결
              PressableScale(
                onTap: () {
                  showGeneralDialog(
                    context: context,
                    barrierDismissible: true,
                    barrierLabel: 'QuickMenu',
                    barrierColor: Colors.black54,
                    transitionDuration: const Duration(milliseconds: 300),
                    pageBuilder: (context, anim1, anim2) => const QuickMenuPanel(),
                    transitionBuilder: (context, anim1, anim2, child) {
                      return FadeTransition(opacity: anim1, child: child);
                    },
                  );
                },
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: isAutoActive ? Colors.blueAccent.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                    border: Border.all(color: isAutoActive ? Colors.blueAccent.withOpacity(0.3) : Colors.white10),
                  ),
                  child: Icon(Icons.settings_suggest_outlined, size: 16, color: isAutoActive ? Colors.blueAccent : Colors.white38),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PressableScale(
                  onTap: _showBulkDismantleDialog,
                  child: Container(
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.redAccent.withOpacity(0.1),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_delete_outlined, size: 12, color: Colors.redAccent),
                        SizedBox(width: 4),
                        Text('일괄분해', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.redAccent)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(ItemType? type, String label) {
    bool isSel = _inventoryFilter == type;
    return PressableScale(
      onTap: () => setState(() => _inventoryFilter = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? Colors.blueAccent.withOpacity(0.2) : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSel ? Colors.blueAccent.withOpacity(0.5) : Colors.white.withOpacity(0.05)),
        ),
        child: Text(
          label, 
          style: TextStyle(color: isSel ? Colors.blueAccent : Colors.white38, fontSize: 11, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)
        ),
      ),
    );
  }

  Widget _buildSortBtn(String label, int mode, IconData icon) {
    bool isSel = _inventorySortMode == mode;
    Color color = mode == 1 ? Colors.amberAccent : Colors.blueAccent;
    return Expanded(
      child: PressableScale(
        onTap: () => setState(() => _inventorySortMode = mode),
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: isSel ? color : color.withOpacity(0.1),
            border: Border.all(color: isSel ? color : Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: isSel ? Colors.white : color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isSel ? Colors.white : color.withOpacity(0.8))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryGrid(GameState gameState) {
    List<Item> filtered = _inventoryFilter == null 
        ? List.from(gameState.player.inventory) 
        : gameState.player.inventory.where((i) => i.type == _inventoryFilter).toList();

    if (_inventorySortMode == 0) {
      filtered.sort((a, b) => b.grade.index.compareTo(a.grade.index));
    } else if (_inventorySortMode == 1) {
      filtered.sort((a, b) => b.combatPower.compareTo(a.combatPower));
    } else {
      filtered.sort((a, b) => b.enhanceLevel.compareTo(a.enhanceLevel));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          if (!_isInventoryScrolling) setState(() => _isInventoryScrolling = true);
        } else if (notification is ScrollEndNotification) {
          _scrollStopTimer?.cancel();
          _scrollStopTimer = Timer(const Duration(milliseconds: 200), () {
            if (mounted) setState(() => _isInventoryScrolling = false);
          });
        }
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7, mainAxisSpacing: 8, crossAxisSpacing: 8,
        ),
        itemCount: filtered.length,
        itemBuilder: (context, i) {
          final item = filtered[i];
          return PremiumItemSlot(
            item: item,
            isPaused: _isInventoryScrolling,
            onTap: () => _showItemDetail(item, filtered),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // [Dialog Logic] - 다이얼로그 호출 및 처리 로직
  // ---------------------------------------------------------------------------

  void _showItemDetail(Item item, List<Item> contextList) {
    if (item.isNew) {
      item.isNew = false;
      context.read<GameState>().refresh();
    }
    showDialog(
      context: context,
      builder: (context) => _ItemDetailDialog(initialItem: item, contextList: contextList, onShowToast: widget.onShowToast),
    );
  }

  void _showBulkDismantleDialog() {
    int selectedGradeIdx = 0; // 일반
    int selectedTier = 1;     // T1
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool canExecute = selectedGradeIdx >= 0 && selectedTier >= 1;
          
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1D2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Row(
              children: [
                Icon(Icons.auto_delete_outlined, color: Colors.redAccent, size: 20),
                SizedBox(width: 8),
                Text('일괄 분해 실행', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('선택한 조건 이하의 모든 아이템을 즉시 분해합니다.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 24),
                
                // 등급 선택
                _buildDismantleSlider(
                  label: "대상 등급 이하",
                  value: selectedGradeIdx.toDouble() + 1,
                  max: 7,
                  divisions: 7,
                  labels: ["OFF", "일반", "고급", "희귀", "영웅", "고유", "전설", "신화"],
                  onChanged: (v) => setDialogState(() => selectedGradeIdx = v.toInt() - 1),
                  activeColor: selectedGradeIdx != -1 ? ItemGrade.values[selectedGradeIdx].color : Colors.white24,
                ),
                const SizedBox(height: 16),
                
                // 티어 선택
                _buildDismantleSlider(
                  label: "대상 티어 이하",
                  value: selectedTier == -1 ? 0 : selectedTier.toDouble(),
                  max: 6,
                  divisions: 6,
                  labels: ["OFF", "T1", "T2", "T3", "T4", "T5", "T6"],
                  onChanged: (v) => setDialogState(() => selectedTier = v == 0 ? -1 : v.toInt()),
                  activeColor: Colors.blueAccent,
                ),
                
                const SizedBox(height: 16),
                if (canExecute)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      '${selectedGradeIdx == -1 ? "OFF" : ItemGrade.values[selectedGradeIdx].name} 이하 / ${selectedTier == -1 ? "OFF" : "T$selectedTier"} 이하 장비 분해',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.white38))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: canExecute ? Colors.redAccent : Colors.white10,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: canExecute ? () {
                  Navigator.pop(context);
                  final rewards = context.read<GameState>().executeBulkDismantle(selectedGradeIdx, selectedTier);
                  if (rewards['count']! > 0) {
                    _showDismantleResult(context, rewards);
                  }
                } : null,
                child: const Text('분해 실행', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSlotEnhanceDialog(ItemType type) {
    showDialog(
      context: context,
      builder: (context) => Consumer<GameState>(
        builder: (context, gs, child) {
          final info = gs.getSlotEnhanceInfo(type);
          final level = info['level'] as int;
          final goldCost = info['goldCost'] as int;
          final stoneCost = info['stoneCost'] as int;
          final chance = info['chance'] as double;
          final baseChance = info['baseChance'] as double;
          final bonusChance = info['bonusChance'] as double;
          final isMax = info['isMax'] as bool;
          final failCount = info['failCount'] as int;
          final streakCount = info['streakCount'] as int;
          final isGuaranteed = info['isGuaranteed'] as bool;
          final hasPity = info['hasPity'] as bool;
          final hasStreakBonus = info['hasStreakBonus'] as bool;
          
          final player = gs.player;
          final canAfford = player.gold >= goldCost && player.enhancementStone >= stoneCost;

          // 보너스 요약 텍스트
          String bonusInfo = "";
          if (hasStreakBonus) bonusInfo += "🔥 스트릭 보너스(+10%) ";
          if (hasPity) bonusInfo += "🍀 천장 보너스(x2) ";
          if (isGuaranteed) bonusInfo = "✨ 확정 성공 ✨";

          return Dialog(
            backgroundColor: Colors.transparent,
            child: GlassContainer(
              padding: const EdgeInsets.all(24),
              borderRadius: 32,
              color: const Color(0xFF1A1D2E).withOpacity(0.95),
              border: Border.all(color: isGuaranteed ? Colors.amberAccent : Colors.blueAccent.withOpacity(0.3), width: 1.5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Icon(Icons.bolt, color: Colors.amberAccent, size: 24),
                      Text('${type.nameKr} 슬롯 강화', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white24, size: 20)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // 마일스톤 진행도 간략 표시
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildMilestoneDot(level, 1000, "효과+20%"),
                      _buildMilestoneLine(level, 1000, 1200),
                      _buildMilestoneDot(level, 1200, "비용-10%"),
                      _buildMilestoneLine(level, 1200, 1500),
                      _buildMilestoneDot(level, 1500, "전체효율+15%"),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  Text('+$level', style: TextStyle(color: isGuaranteed ? Colors.amberAccent : Colors.blueAccent, fontSize: 42, fontWeight: FontWeight.w900)),
                  
                  if (bonusInfo.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(bonusInfo, style: TextStyle(color: isGuaranteed ? Colors.amberAccent : Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),

                  const SizedBox(height: 24),
                  
                  // 스탯 변화 표시 및 스트릭
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16)),
                          child: Column(
                            children: [
                              const Text('증폭 효율', style: TextStyle(color: Colors.white30, fontSize: 10)),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('${(level * 2)}%', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                                  const Icon(Icons.arrow_forward_rounded, color: Colors.white24, size: 14),
                                  Text('${(level + 1) * 2}%', style: const TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16)),
                          child: Column(
                            children: [
                              const Text('연속 성공', style: TextStyle(color: Colors.white30, fontSize: 10)),
                              const SizedBox(height: 4),
                              Text('$streakCount Streak', style: TextStyle(color: streakCount >= 3 ? Colors.orangeAccent : Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // 천장 게이지
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('천장 진행도 (Pity)', style: TextStyle(color: Colors.white38, fontSize: 10)),
                          Text('$failCount/50', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: failCount / 50,
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation<Color>(failCount >= 20 ? Colors.amberAccent : Colors.blueAccent),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  
                  // 비용 및 확률
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildCostItem('💰', goldCost, player.gold >= goldCost),
                      _buildCostItem('💎', stoneCost, player.enhancementStone >= stoneCost),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // 확률 디테일
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('성공 확률', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        Text(
                          '${(chance * 100).toStringAsFixed(1)}%',
                          style: TextStyle(color: isGuaranteed ? Colors.amberAccent : (chance > 0.5 ? Colors.greenAccent : Colors.orangeAccent), fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: RepeatingPressable(
                      onTap: (!isMax && canAfford) ? () => gs.enhanceSlot(type) : null,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            colors: (!isMax && canAfford) 
                              ? (isGuaranteed ? [Colors.amber, Colors.orange] : [Colors.blueAccent, Colors.blueAccent.withOpacity(0.7)]) 
                              : [Colors.white10, Colors.white10],
                          ),
                          boxShadow: (!isMax && canAfford) ? [
                             BoxShadow(color: (isGuaranteed ? Colors.amber : Colors.blueAccent).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
                          ] : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          isMax ? '최대 레벨 도달' : (canAfford ? (isGuaranteed ? '확정 강화 실행' : '슬롯 강화') : '재화 부족'),
                          style: TextStyle(
                            color: (!isMax && canAfford) ? Colors.white : Colors.white24,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMilestoneDot(int current, int target, String label) {
    bool reached = current >= target;
    return Column(
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: reached ? Colors.greenAccent : Colors.white12,
            shape: BoxShape.circle,
            boxShadow: reached ? [const BoxShadow(color: Colors.greenAccent, blurRadius: 4)] : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: reached ? Colors.greenAccent : Colors.white12, fontSize: 7, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMilestoneLine(int current, int start, int end) {
    double progress = ((current - start) / (end - start)).clamp(0.0, 1.0);
    return Container(
      width: 30, height: 2,
      margin: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
      color: Colors.white12,
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress,
        child: Container(color: Colors.greenAccent.withOpacity(0.5)),
      ),
    );
  }

  Widget _buildCostItem(String emoji, int cost, bool isEnough) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 4),
        Text(
          _formatNumber(cost),
          style: TextStyle(color: isEnough ? Colors.white70 : Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

String _formatNumber(int n) => BigNumberFormatter.format(n);

/// ♻️ 분해 결과 팝업 함수
void _showDismantleResult(BuildContext context, Map<String, int> rewards) {
  showDialog(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        borderRadius: 32,
        color: const Color(0xFF1A1D2E).withOpacity(0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_delete_outlined, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            const Text('분해 결과', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            if (rewards.containsKey('count'))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('${rewards['count']}개의 아이템을 분해했습니다.', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ),
            Wrap(
              spacing: 12, runSpacing: 12, alignment: WrapAlignment.center,
              children: [
                if (rewards['gold']! > 0) _buildResultItem('💰', '골드', rewards['gold']!, Colors.amberAccent),
                if (rewards['abyssalPowder'] != null && rewards['abyssalPowder']! > 0) _buildResultItem('✨', '심연의 가루', rewards['abyssalPowder']!, Colors.orangeAccent),
                if (rewards['shards'] != null && rewards['shards']! > 0) _buildResultItem('🧩', '연성 파편', rewards['shards']!, Colors.cyanAccent),
                if (rewards['stone']! > 0) _buildResultItem('💎', '강화석', rewards['stone']!, Colors.blueAccent),
                if (rewards['reroll']! > 0) _buildResultItem('🎲', '재설정석', rewards['reroll']!, Colors.purpleAccent),
                if (rewards['protection']! > 0) _buildResultItem('🛡️', '보호석', rewards['protection']!, Colors.orangeAccent),
                if (rewards['cube']! > 0) _buildResultItem('🔮', '잠재력 큐브', rewards['cube']!, Colors.redAccent),

              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildResultItem(String emoji, String label, int amount, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Text(
          BigNumberFormatter.format(amount),
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    ),
  );
}

// =============================================================================
// [_ItemDetailDialog]
// 특정 아이템의 정보를 상세히 보여주는 다이얼로그입니다.
// 강화, 재설정, 잠재능력 각성 및 장착 비교 기능을 포함합니다.
// =============================================================================

class _ItemDetailDialog extends StatefulWidget {
  final Item initialItem;
  final List<Item> contextList;
  final Function(String, {bool isError})? onShowToast;
  const _ItemDetailDialog({required this.initialItem, required this.contextList, this.onShowToast});

  @override
  State<_ItemDetailDialog> createState() => _ItemDetailDialogState();
}

class _ItemDetailDialogState extends State<_ItemDetailDialog> {
  late Item currentItem;
  bool isCompareExpanded = false;
  bool useProtection = false; // 🆕 보호석 사용 여부 토글 상태 추가

  @override
  void initState() {
    super.initState();
    currentItem = widget.initialItem;
  }

  @override
  Widget build(BuildContext context) {
    final gs = context.watch<GameState>();
    final player = gs.player;
    final isEquipped = player.equipment[currentItem.type]?.id == currentItem.id;
    final currentEquip = player.equipment[currentItem.type];
    int currentIndex = widget.contextList.indexWhere((i) => i.id == currentItem.id);
    bool hasPrev = currentIndex > 0;
    bool hasNext = currentIndex >= 0 && currentIndex < widget.contextList.length - 1;

    // 슬롯 강화 배율 (장착 중인 경우에만 적용)
    double slotMultiplier = isEquipped 
        ? 1.0 + (player.slotEnhanceLevels[currentItem.type] ?? 0) * 0.02 
        : 1.0;

    return Dialog(
      backgroundColor: const Color(0xFF141622),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: currentItem.grade.color.withOpacity(0.4), width: 1.5),
      ),
      child: Container(
        width: 350,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1A1D2E), Color(0xFF0F111A)]),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 헤더 (내비게이션)
              _buildHeader(hasPrev, hasNext, currentIndex),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _buildCPBadge(currentItem.combatPower),
                    const SizedBox(height: 12),
                    if (!isEquipped && currentEquip != null)
                      _buildCompareCard(currentItem, currentEquip),
                    _buildMainStatSection(currentItem, slotMultiplier),
                    const SizedBox(height: 16),
                    _buildSubOptions(currentItem),
                    if (currentItem.potential != null)
                      _buildPotentialSection(currentItem.potential!),
                    if (currentItem.setId != null)
                      _buildSetSection(currentItem),
                    const SizedBox(height: 20),

                    _buildFeatureButtons(gs, currentItem),
                    const SizedBox(height: 32),
                    _buildFinalActions(gs, currentItem, isEquipped),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool hasPrev, bool hasNext, int index) {
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [currentItem.grade.color.withOpacity(0.12), Colors.transparent]),
          ),
          child: Row(
            children: [
              _buildNavBtn(hasPrev, index - 1, Icons.chevron_left),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildTierBadge(currentItem.tier),
                        const SizedBox(width: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${currentItem.name.split(' T')[0]} +${currentItem.enhanceLevel}',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: currentItem.grade.color),
                            ),
                          ),

                          ),
                          if (currentItem.canPromote) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amberAccent,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [BoxShadow(color: Colors.amberAccent.withOpacity(0.5), blurRadius: 8)],
                              ),
                              child: const Text('READY', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900)),

                            ),
                          ],
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              context.read<GameState>().toggleItemLock(currentItem);
                              setState(() {});
                            },
                            child: Icon(
                              currentItem.isLocked ? Icons.lock : Icons.lock_open,
                              size: 18,
                              color: currentItem.isLocked ? Colors.amberAccent : Colors.white12,
                            ),
                          ),
                        ],
                      ),

                  ],
                ),
              ),
              _buildNavBtn(hasNext, index + 1, Icons.chevron_right),
            ],
          ),
        ),
        Positioned(right: 12, top: 12, child: InkWell(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, color: Colors.white24, size: 20))),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // [Sub Components] - 다이얼로그 세부 컴포넌트 빌더
  // ---------------------------------------------------------------------------

  Widget _buildNavBtn(bool active, int nextIdx, IconData icon) {
    return IconButton(
      icon: Icon(icon, color: active ? Colors.white70 : Colors.white10, size: 28),
      onPressed: active ? () => setState(() {
        currentItem = widget.contextList[nextIdx];
        if (currentItem.isNew) currentItem.isNew = false;
      }) : null,
    );
  }

  Widget _buildTierBadge(int tier) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white24)),
      child: Text('Tier $tier', style:const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }

  Widget _buildDurabilityBar(Item item) {
    double progress = item.durability / item.maxDurability;
    Color barColor = item.isBroken ? Colors.redAccent : (progress < 0.3 ? Colors.orangeAccent : Colors.greenAccent);
    
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('내구도', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
            Text(
              '${item.durability}/${item.maxDurability}',
              style: TextStyle(color: barColor, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white10,
            color: barColor,
            minHeight: 4,
          ),
        ),
        if (item.isBroken)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 12),
                const SizedBox(width: 4),
                const Text('장비 파손: 성능 20% 감소 및 강화 불가', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCPBadge(int cp) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.bolt, size: 14, color: Colors.amberAccent),
        const SizedBox(width: 4),
        Text(BigNumberFormatter.format(cp), style: const TextStyle(color: Colors.amberAccent, fontSize: 16, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildCompareCard(Item item, Item equip) {
    final diff = item.combatPower - equip.combatPower;
    return GestureDetector(
      onTap: () => setState(() => isCompareExpanded = !isCompareExpanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04), 
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(isCompareExpanded ? 0.1 : 0.05)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.compare_arrows, size: 14, color: Colors.white38),
                const SizedBox(width: 8),
                const Text('착용 장비와 비교', style: TextStyle(fontSize: 12, color: Colors.white38, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${diff >= 0 ? '+' : ''}${NumberFormat('#,###').format(diff)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: diff >= 0 ? Colors.greenAccent : Colors.redAccent)),
                const SizedBox(width: 4),
                Icon(isCompareExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 16, color: Colors.white24),
              ],
            ),
            if (isCompareExpanded) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(color: Colors.white10, height: 1),
              ),
              _buildComparisonRow(item.mainStatName1, equip.effectiveMainStat1.toDouble(), item.effectiveMainStat1.toDouble()),
              if (item.mainStatName2 != null)
                _buildComparisonRow(item.mainStatName2!, equip.effectiveMainStat2.toDouble(), item.effectiveMainStat2.toDouble()),
              
              // 보조 옵션 및 잠재능력 비교 추가
              ..._buildSubOptionComparisons(item, equip),
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // [Comparison Logic] - 착용 장비와의 능력치 비교 계산
  // ---------------------------------------------------------------------------

  List<Widget> _buildSubOptionComparisons(Item item, Item equip) {
    Map<String, double> itemStats = _getAggregatedStats(item);
    Map<String, double> equipStats = _getAggregatedStats(equip);
    
    Set<String> allKeys = {...itemStats.keys, ...equipStats.keys};
    // 메인 스탯은 중복되므로 제외 (이미 위에서 표시함)
    allKeys.remove(item.mainStatName1);
    if (item.mainStatName2 != null) allKeys.remove(item.mainStatName2);
    if (equip.mainStatName1 != item.mainStatName1) allKeys.remove(equip.mainStatName1);
    if (equip.mainStatName2 != null) allKeys.remove(equip.mainStatName2);

    List<String> sortedKeys = allKeys.toList()..sort();
    
    return sortedKeys.map((key) {
      double current = equipStats[key] ?? 0.0;
      double target = itemStats[key] ?? 0.0;
      if ((target - current).abs() < 0.01) return const SizedBox.shrink();

      bool isPerc = _isPercentageStat(key);
      return _buildComparisonRow(key, current, target, isPercentage: isPerc);
    }).where((w) => w is! SizedBox).toList();
  }

  Map<String, double> _getAggregatedStats(Item item) {
    Map<String, double> stats = {};
    for (var opt in item.subOptions) {
      stats[opt.effect.label] = (stats[opt.effect.label] ?? 0.0) + opt.value;
    }
    if (item.potential != null) {
      stats[item.potential!.effect.label] = (stats[item.potential!.effect.label] ?? 0.0) + item.potential!.value;
    }
    return stats;
  }

  bool _isPercentageStat(String name) {
    const percStats = {'치명타 확률', '치명타 피해', 'HP 재생', '골드 획득', '경험치 획득', '아이템 드롭', '최종 피해량 증폭', '쿨타임 감소', '방어력%', '공격 속도'};
    return percStats.contains(name) || name.contains('%');
  }

  Widget _buildComparisonRow(String label, double current, double target, {bool isPercentage = false}) {
    final diff = target - current;
    final bool isZero = diff.abs() < 1e-6;
    final isPos = diff > 0;
    
    Color color = isZero ? Colors.white38 : (isPos ? Colors.greenAccent : Colors.redAccent);
    IconData icon = isZero ? Icons.remove : (isPos ? Icons.arrow_upward : Icons.arrow_downward);

    String diffStr;
    if (isPercentage) {
      String suffix = label == '공격 속도' ? '' : '%';
      diffStr = '${isPos ? '+' : (isZero ? '+' : '')}${diff.toStringAsFixed(1)}$suffix';
    } else {
      diffStr = '${isPos ? '+' : (isZero ? '+' : '')}${NumberFormat('#,###').format(diff.toInt())}';
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const Spacer(),
          Text(
            diffStr,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 4),
          Icon(icon, size: 10, color: color),
        ],
      ),
    );
  }

  Widget _buildMainStatSection(Item item, double slotMultiplier) {
    int s1 = (item.effectiveMainStat1 * slotMultiplier).toInt();
    int s2 = (item.effectiveMainStat2 * slotMultiplier).toInt();
    bool hasBonus = slotMultiplier > 1.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withOpacity(0.08), 
        borderRadius: BorderRadius.circular(16), 
        border: Border.all(color: Colors.blueAccent.withOpacity(hasBonus ? 0.4 : 0.2))
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(item.mainStatName1, style: const TextStyle(fontSize: 14, color: Colors.white70)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(NumberFormat('#,###').format(s1), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.blueAccent)),
                  if (hasBonus)
                    Text('(슬롯 보너스 +${((slotMultiplier - 1) * 100).toInt()}%)', style: const TextStyle(fontSize: 10, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          if (item.mainStat2 != null) ...[
            const Divider(color: Colors.white10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(item.mainStatName2!, style: const TextStyle(fontSize: 14, color: Colors.white70)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(NumberFormat('#,###').format(s2), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.blueAccent)),
                    if (hasBonus)
                      Text('(슬롯 보너스 +${((slotMultiplier - 1) * 100).toInt()}%)', style: const TextStyle(fontSize: 10, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // [Item Options] - 보조 옵션 및 잠재능력 표시
  // ---------------------------------------------------------------------------

  Widget _buildSubOptions(Item item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('아이템 옵션', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white38, letterSpacing: 1)),
        const SizedBox(height: 8),
        ...item.subOptions.map((opt) {
          // 🆕 [v0.5.16] 최대치 포맷팅
          String maxValStr = opt.effect.isPercentage 
              ? '${opt.maxValue.toStringAsFixed(1)}%' 
              : (opt.effect == OptionEffect.addAspd ? opt.maxValue.toStringAsFixed(2) : opt.maxValue.toInt().toString());

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Text(opt.toString(), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(width: 6),
                Text('(MAX: +$maxValStr)', style: const TextStyle(color: Colors.white24, fontSize: 9)), // 🆕 최대치 가이드
                const Spacer(),
                Row(children: List.generate(opt.stars, (i) => const Icon(Icons.star, size: 10, color: Colors.amberAccent))),
                const SizedBox(width: 8),
                GestureDetector(onTap: () { opt.isLocked = !opt.isLocked; setState(() {}); }, child: Icon(opt.isLocked ? Icons.lock : Icons.lock_open, size: 16, color: opt.isLocked ? Colors.amberAccent : Colors.white12)),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPotentialSection(ItemOption potential) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.purpleAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.purpleAccent.withOpacity(0.3))),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Colors.purpleAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('잠재능력', style: TextStyle(color: Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.bold)),
            Text(potential.toString(), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ])),
        ],
      ),
    );
  }

  Widget _buildSetSection(Item item) {
    if (item.setId == null) return const SizedBox.shrink();
    String setName = Item.getSetName(item.setId!);
    
    String bonus2 = "";
    String bonus4 = "";
    switch (item.setId) {
      case 'desert': bonus2 = "골드/EXP +20%"; bonus4 = "사냥터 이동 시 30초간 ATK +30%"; break;
      case 'mine': bonus2 = "방어력 +20%"; bonus4 = "피격 시 10% 확률로 HP 5% 회복"; break;
      case 'dimension': bonus2 = "스킬 데미지 +25%"; bonus4 = "스킬 쿨타임 -15%"; break;
      case 'dragon': bonus2 = "공격력 +30%"; bonus4 = "최종 피해량 증폭 +50%"; break;
      case 'ancient': bonus2 = "모든 능력치 +20%"; bonus4 = "공격 시 5% 확률 광역 번개"; break;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purpleAccent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_motion, size: 14, color: Colors.purpleAccent),
              const SizedBox(width: 8),
              Text('세트 아이탬: [$setName]', style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          _buildSetBonusLine(2, bonus2),
          _buildSetBonusLine(4, bonus4),
        ],
      ),
    );
  }

  Widget _buildSetBonusLine(int count, String bonus) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text('$count세트: $bonus', style: const TextStyle(color: Colors.white60, fontSize: 11))),
        ],
      ),
    );
  }


  // ---------------------------------------------------------------------------
  // [Functional Buttons] - 강화, 재설정, 잠재능력 버튼
  // ---------------------------------------------------------------------------

  Widget _buildFeatureButtons(GameState gs, Item item) {
    int lockCount = item.subOptions.where((o) => o.isLocked).length;
    int powderCost = lockCount == 0 ? 0 : (1000 * pow(10, lockCount - 1)).toInt();
    
    // [v0.4.8] 기능별 해금 체크
    int totalSlotLv = gs.player.totalSlotEnhanceLevel;
    bool isEnhanceUnlocked = totalSlotLv >= 50;
    bool isRerollUnlocked = totalSlotLv >= 300;
    bool isPotentialUnlocked = totalSlotLv >= 1000;

    return Column(
      children: [
        _buildDurabilityBar(item),
        const SizedBox(height: 16),
        if (item.canPromote)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: Colors.amberAccent.withOpacity(0.15), blurRadius: 20, spreadRadius: 2),
                ],
              ),
              child: _FeatureBtn(
                title: '✨ 티어 승급 (T${item.tier} -> T${item.tier + 1}) ✨', 
                icon: Icons.auto_awesome, 
                color: Colors.amberAccent, 
                isFull: true,

              enabled: true,
              cost: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('💰', style: TextStyle(fontSize: 10)),
                  Text(BigNumberFormatter.format(item.promotionGoldCost), style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  const Text('💎', style: TextStyle(fontSize: 10)),
                  Text(BigNumberFormatter.format(item.promotionStoneCost), style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold)),
                ],
              ),
              onTap: () {
                if (gs.player.gold < item.promotionGoldCost || gs.player.enhancementStone < item.promotionStoneCost) {
                  widget.onShowToast?.call('재화가 부족합니다!', isError: true);
                } else {
                  gs.promoteItem(item);
                  widget.onShowToast?.call('승급 성공! (T${item.tier})', isError: false);
                  setState(() {});
                }
              },
            ),
          ),
        ),

        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 1. 재설정 버튼
            Expanded(child: _FeatureBtn(
              title: isRerollUnlocked ? '재설정 (${item.rerollCount}/5)' : '슬롯 300강', 
              icon: isRerollUnlocked ? Icons.refresh : Icons.lock_outline, 
              color: Colors.cyanAccent, 
              enabled: isRerollUnlocked,
              cost: isRerollUnlocked ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('✨', style: TextStyle(fontSize: 9)),
                  Text(_formatNumber(powderCost), style: const TextStyle(fontSize: 9, color: Colors.white54, fontWeight: FontWeight.bold)),
                ],
              ) : Text('(현재 $totalSlotLv / 300)', style: TextStyle(fontSize: 8, color: Colors.amberAccent.withOpacity(0.5), fontWeight: FontWeight.bold)),
              onTap: () {
                if (gs.player.rerollStone < 1 || gs.player.abyssalPowder < powderCost) {
                  widget.onShowToast?.call('재료가 부족합니다!', isError: true);
                } else if (item.isLocked) {
                  widget.onShowToast?.call('잠긴 아이템은 재설정할 수 없습니다!', isError: true);
                } else if (item.rerollCount >= 5) {
                  widget.onShowToast?.call('재설정 횟수를 초과했습니다!', isError: true);
                } else {
                  gs.rerollItemOptions(item);
                  widget.onShowToast?.call('옵션 재설정 완료!', isError: false);
                  setState(() {});
                }
              },
            )),
            const SizedBox(width: 6),
            // 2. 잠재능력 버튼
            Expanded(child: _FeatureBtn(
              title: isPotentialUnlocked ? '잠재능력' : '슬롯 1000강', 
              icon: isPotentialUnlocked ? Icons.auto_awesome : Icons.lock_outline, 
              color: Colors.purpleAccent,
              enabled: isPotentialUnlocked,
              cost: isPotentialUnlocked ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('🔮', style: TextStyle(fontSize: 9)),
                  Text('10', style: TextStyle(fontSize: 9, color: Colors.white54, fontWeight: FontWeight.bold)),
                ],
              ) : Text('(현재 $totalSlotLv / 1000)', style: TextStyle(fontSize: 8, color: Colors.amberAccent.withOpacity(0.5), fontWeight: FontWeight.bold)),
              onTap: () { 
                if (gs.player.cube < 10) {
                  widget.onShowToast?.call('큐브가 부족합니다! (필요: 10개)', isError: true);
                } else if (item.isLocked) {
                  widget.onShowToast?.call('잠긴 아이템은 각성할 수 없습니다!', isError: true);
                } else {
                  gs.player.cube -= 10; 
                  item.awakenPotential(Random()); 
                  gs.saveGameData(); 
                  widget.onShowToast?.call('잠재능력 개방 성공!', isError: false);
                  setState(() {}); 
                }
              },
            )),
            const SizedBox(width: 6),
            // 3. 강화 버튼 (보호석 토글 포함)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isEnhanceUnlocked)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: PressableScale(
                        onTap: () => setState(() => useProtection = !useProtection),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          decoration: BoxDecoration(
                            color: useProtection ? Colors.orangeAccent.withOpacity(0.12) : Colors.black26,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: useProtection ? Colors.orangeAccent.withOpacity(0.4) : Colors.white10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.shield_outlined, size: 10, color: useProtection ? Colors.orangeAccent : Colors.white24),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '보호: ${gs.player.protectionStone}',
                                  style: TextStyle(
                                    color: useProtection ? Colors.orangeAccent : Colors.white38,
                                    fontSize: 7, 
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  _FeatureBtn(
                    title: isEnhanceUnlocked ? '강화 (+${item.enhanceLevel})' : '슬롯 50강', 
                    icon: isEnhanceUnlocked ? Icons.flash_on : Icons.lock_outline, 
                    color: Colors.blueAccent,
                    enabled: isEnhanceUnlocked,
                    cost: isEnhanceUnlocked ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('💰', style: TextStyle(fontSize: 9)),
                        Text(item.enhanceCost > 10000 ? '${(item.enhanceCost/1000).toStringAsFixed(1)}k' : _formatNumber(item.enhanceCost), style: const TextStyle(fontSize: 9, color: Colors.white54, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 3),
                        const Text('💎', style: TextStyle(fontSize: 9)),
                        Text(_formatNumber(item.stoneCost), style: const TextStyle(fontSize: 9, color: Colors.white54, fontWeight: FontWeight.bold)),
                      ],
                    ) : Text('(현재 $totalSlotLv / 50)', style: TextStyle(fontSize: 8, color: Colors.amberAccent.withOpacity(0.5), fontWeight: FontWeight.bold)),
                    onTap: () async {
                      if (item.isLocked) {
                        widget.onShowToast?.call('잠긴 아이템은 강화할 수 없습니다!', isError: true);
                      } else if (gs.player.gold < item.enhanceCost || gs.player.enhancementStone < item.stoneCost) {
                        widget.onShowToast?.call('재화가 부족합니다!', isError: true);
                      } else if (useProtection && gs.player.protectionStone < 1) {
                        widget.onShowToast?.call('보호석이 부족합니다!', isError: true);
                      } else if (item.isBroken) {
                        widget.onShowToast?.call('파손된 장비는 강화할 수 없습니다!', isError: true);
                      } else {
                        if (!useProtection && item.durability == 1) {
                          bool? proceed = await _showLastChanceConfirm(context);
                          if (proceed != true) return;
                        }

                        int oldLevel = currentItem.enhanceLevel;
                        String result = gs.enhanceItem(currentItem, useProtection: useProtection);
                        bool isSuccess = currentItem.enhanceLevel > oldLevel;
                        widget.onShowToast?.call(result, isError: !isSuccess);
                        setState(() {});
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // [Equip Actions] - 장착 및 해제 액션
  // ---------------------------------------------------------------------------

  Widget _buildFinalActions(GameState gs, Item item, bool isEquipped) {
    return Row(
      children: [
        Expanded(child: PressableScale(
          onTap: () {
            if (isEquipped) {
              gs.player.unequipItem(item.type);
              gs.notifyListeners();
            } else {
              gs.equipItem(item);
            }
            gs.saveGameData(); Navigator.pop(context);

          },
          child: Container(
            height: 44,
            decoration: BoxDecoration(color: isEquipped ? Colors.white10 : Colors.blueAccent, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Text(isEquipped ? '해제하기' : '착용하기', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        )),
        const SizedBox(width: 10),
        PressableScale(
          onTap: item.isLocked ? null : () {
            final rewards = gs.executeDismantle(item); 
            Navigator.pop(context);
            if (rewards.isNotEmpty) {
              _showDismantleResult(context, rewards);
            }
          },
          child: Container(
            width: 80, height: 44,
            decoration: BoxDecoration(color: Colors.redAccent.withOpacity(item.isLocked ? 0.2 : 0.8), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
        ),
      ],
    );
  }

  // 🆕 [v0.5.15] 내구도 1 강화 시 경고 팝업
  Future<bool?> _showLastChanceConfirm(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 12),
            Text('파손 주의!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('내구도가 1입니다. 강화 실패 시 장비는 파손됩니다.', style: TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: const Text('강화하시겠습니까?', style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('포기!!', style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('강화!!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _FeatureBtn extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final bool enabled;
  final bool isFull;
  final VoidCallback onTap;
  final Widget? cost; // [v0.4.7] 소모 비용 표시용 위젯 추가

  const _FeatureBtn({
    required this.title, 
    required this.icon, 
    required this.color, 
    required this.enabled, 
    required this.onTap, 
    this.isFull = false,
    this.cost,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        width: isFull ? double.infinity : null,
        decoration: BoxDecoration(
          color: color.withOpacity(enabled ? 0.1 : 0.03), borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(enabled ? 0.3 : 0.05)),
        ),
        child: Column(children: [
          Icon(icon, size: 18, color: color.withOpacity(enabled ? 1 : 0.2)),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color.withOpacity(enabled ? 1 : 0.3))),
          if (cost != null) ...[
            const SizedBox(height: 4),
            cost!,
          ],
        ]),
      ),
    );
  }
}
