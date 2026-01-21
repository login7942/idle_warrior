import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:idle_warrior/models/player.dart';
import 'package:idle_warrior/models/item.dart';
import 'package:idle_warrior/providers/game_state.dart';
import 'common_widgets.dart';

/// 🎒 인벤토리 전용 패널 위젯
class InventoryPanel extends StatefulWidget {
  const InventoryPanel({super.key});

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
            _buildAutoDismantlePanel(gameState),
            _buildEquippedSlots(player),
            _buildInventoryControls(),
            Expanded(child: _buildInventoryGrid(gameState)),
            const SizedBox(height: 100), // 하단 독 공간
          ],
        );
      },
    );
  }

  // --- 위젯 빌더들 ---

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
              _buildCompactResource('✨', player.powder, Colors.greenAccent),
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

  Widget _buildAutoDismantlePanel(GameState gameState) {
    return GlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      borderRadius: 16,
      color: Colors.white.withOpacity(0.03),
      border: Border.all(color: gameState.autoDismantleLevel > 0 ? Colors.blueAccent.withOpacity(0.3) : Colors.white10),
      child: Row(
        children: [
          Icon(
            Icons.auto_delete_outlined,
            size: 16,
            color: gameState.autoDismantleLevel > 0 ? Colors.blueAccent : Colors.white38,
          ),
          const SizedBox(width: 8),
          const Text(
            '자동 분해',
            style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: DropdownButton<int>(
              value: gameState.autoDismantleLevel,
              isDense: true,
              underline: const SizedBox(),
              dropdownColor: const Color(0xFF1a1d2e),
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              items: const [
                DropdownMenuItem(value: 0, child: Text('사용 안 함')),
                DropdownMenuItem(value: 1, child: Text('T1 일반')),
                DropdownMenuItem(value: 2, child: Text('T1 고급 이하')),
                DropdownMenuItem(value: 3, child: Text('T1 희귀 이하')),
                DropdownMenuItem(value: 4, child: Text('T1 전체')),
              ],
              onChanged: (v) {
                if (v != null) {
                  gameState.autoDismantleLevel = v;
                  gameState.saveGameData();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEquippedSlots(Player player) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: ItemType.values.map((type) {
          final item = player.equipment[type];
          bool isEmpty = item == null;
          double slotSize = 52.0;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: isEmpty 
              ? SizedBox(
                  width: slotSize, height: slotSize,
                  child: GlassContainer(
                    borderRadius: 12,
                    color: Colors.black26,
                    border: Border.all(color: Colors.white10),
                    child: Center(
                      child: Opacity(
                        opacity: 0.5,
                        child: EmptyItemIcon(type: type, size: slotSize * 0.5)
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
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInventoryControls() {
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

  // --- 다이얼로그 로직 ---

  void _showItemDetail(Item item, List<Item> contextList) {
    if (item.isNew) {
      item.isNew = false;
      context.read<GameState>().refresh();
    }
    showDialog(
      context: context,
      builder: (context) => _ItemDetailDialog(initialItem: item, contextList: contextList),
    );
  }

  void _showBulkDismantleDialog() {
    ItemGrade selectedGrade = ItemGrade.uncommon;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1D2E),
          title: const Text('일괄 분해 설정', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('선택한 등급 이하의 모든 아이템을 분해합니다.', style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10, runSpacing: 10, alignment: WrapAlignment.center,
                children: ItemGrade.values.map((grade) {
                  bool isSel = selectedGrade == grade;
                  return InkWell(
                    onTap: () => setDialogState(() => selectedGrade = grade),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 85, height: 40,
                      decoration: BoxDecoration(
                        color: isSel ? grade.color.withOpacity(0.3) : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isSel ? grade.color : Colors.white10, width: isSel ? 2 : 1),
                      ),
                      alignment: Alignment.center,
                      child: Text(grade.name, style: TextStyle(color: isSel ? Colors.white : Colors.white38, fontWeight: isSel ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () {
                Navigator.pop(context);
                context.read<GameState>().executeBulkDismantle(selectedGrade);
              },
              child: const Text('분해 실행', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(int n) => NumberFormat('#,###').format(n);
}

// --- 상세 정보 다이얼로그 (내부 위젯) ---

class _ItemDetailDialog extends StatefulWidget {
  final Item initialItem;
  final List<Item> contextList;
  const _ItemDetailDialog({required this.initialItem, required this.contextList});

  @override
  State<_ItemDetailDialog> createState() => _ItemDetailDialogState();
}

class _ItemDetailDialogState extends State<_ItemDetailDialog> {
  late Item currentItem;
  bool isCompareExpanded = false;

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
                    _buildMainStatSection(currentItem),
                    const SizedBox(height: 16),
                    _buildSubOptions(currentItem),
                    if (currentItem.potential != null)
                      _buildPotentialSection(currentItem.potential!),
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
                        Text(
                          '${currentItem.name.split(' T')[0]} +${currentItem.enhanceLevel}',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: currentItem.grade.color),
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
      child: Text('Tier $tier', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }

  Widget _buildCPBadge(int cp) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.bolt, size: 14, color: Colors.amberAccent),
        const SizedBox(width: 4),
        Text(NumberFormat('#,###').format(cp), style: const TextStyle(color: Colors.amberAccent, fontSize: 16, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildCompareCard(Item item, Item equip) {
    final diff = item.combatPower - equip.combatPower;
    return GestureDetector(
      onTap: () => setState(() => isCompareExpanded = !isCompareExpanded),
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.compare_arrows, size: 14, color: Colors.white38),
                const SizedBox(width: 8),
                const Text('착용 장비와 비교', style: TextStyle(fontSize: 12, color: Colors.white38, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${diff >= 0 ? '+' : ''}${NumberFormat('#,###').format(diff)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: diff >= 0 ? Colors.greenAccent : Colors.redAccent)),
                Icon(isCompareExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 16, color: Colors.white24),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainStatSection(Item item) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.blueAccent.withOpacity(0.2))),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(item.mainStatName1, style: const TextStyle(fontSize: 14, color: Colors.white70)),
              Text(NumberFormat('#,###').format(item.effectiveMainStat1), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.blueAccent)),
            ],
          ),
          if (item.mainStat2 != null) ...[
            const Divider(color: Colors.white10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(item.mainStatName2!, style: const TextStyle(fontSize: 14, color: Colors.white70)),
                Text(NumberFormat('#,###').format(item.effectiveMainStat2), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.blueAccent)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubOptions(Item item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('아이템 옵션', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white38, letterSpacing: 1)),
        const SizedBox(height: 8),
        ...item.subOptions.map((opt) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              Text(opt.toString(), style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              Row(children: List.generate(opt.stars, (i) => const Icon(Icons.star, size: 10, color: Colors.amberAccent))),
              const SizedBox(width: 8),
              GestureDetector(onTap: () { opt.isLocked = !opt.isLocked; setState(() {}); }, child: Icon(opt.isLocked ? Icons.lock : Icons.lock_open, size: 16, color: opt.isLocked ? Colors.amberAccent : Colors.white12)),
            ],
          ),
        )),
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

  Widget _buildFeatureButtons(GameState gs, Item item) {
    int lockCount = item.subOptions.where((o) => o.isLocked).length;
    int powderCost = lockCount == 0 ? 0 : (1000 * pow(10, lockCount - 1)).toInt();
    
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _FeatureBtn(
              title: '옵션 재설정', icon: Icons.refresh, color: Colors.cyanAccent, 
              enabled: gs.player.rerollStone >= 1 && gs.player.powder >= powderCost && !item.isLocked,
              onTap: () {
                gs.player.rerollStone -= 1; gs.player.powder -= powderCost;
                item.rerollSubOptions(Random()); gs.saveGameData(); setState(() {});
              },
            )),
            const SizedBox(width: 8),
            Expanded(child: _FeatureBtn(
              title: '잠재능력', icon: Icons.auto_awesome, color: Colors.purpleAccent,
              enabled: gs.player.cube >= 10 && !item.isLocked,
              onTap: () { gs.player.cube -= 10; item.awakenPotential(Random()); gs.saveGameData(); setState(() {}); },
            )),
          ],
        ),
        const SizedBox(height: 8),
        _FeatureBtn(
          title: '장비 강화 (+${item.enhanceLevel})', icon: Icons.flash_on, color: Colors.blueAccent, isFull: true,
          enabled: !item.isLocked && gs.player.gold >= item.enhanceCost && gs.player.enhancementStone >= item.stoneCost,
          onTap: () => gs.enhanceItem(item), // GameState에 위임
        ),
      ],
    );
  }

  Widget _buildFinalActions(GameState gs, Item item, bool isEquipped) {
    return Row(
      children: [
        Expanded(child: PressableScale(
          onTap: () {
            if (isEquipped) {
              gs.player.unequipItem(item.type);
            } else {
              gs.player.equipItem(item);
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
            gs.executeDismantle(item); Navigator.pop(context);
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
}

class _FeatureBtn extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final bool enabled;
  final bool isFull;
  final VoidCallback onTap;

  const _FeatureBtn({required this.title, required this.icon, required this.color, required this.enabled, required this.onTap, this.isFull = false});

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
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color.withOpacity(enabled ? 1 : 0.3))),
        ]),
      ),
    );
  }
}
