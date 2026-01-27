import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:intl/intl.dart';
import '../models/item.dart';
import 'package:idle_warrior/models/skill.dart';

class ShadowText extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color color;
  final FontWeight fontWeight;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const ShadowText(
    this.text, {
    super.key,
    this.fontSize = 14,
    this.color = Colors.white,
    this.fontWeight = FontWeight.normal,
    this.overflow,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: textAlign,
      overflow: overflow,
      style: TextStyle(
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        shadows: [
          Shadow(
            offset: const Offset(1.5, 1.5),
            blurRadius: 3.0,
            color: Colors.black.withValues(alpha: 0.8),
          ),
          Shadow(
            offset: const Offset(-1.0, -1.0),
            blurRadius: 1.0,
            color: Colors.black.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}

class PopBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final String? subLabel;
  final bool isFull;
  final IconData? icon;

  const PopBtn(
    this.label,
    this.color,
    this.onTap, {
    super.key,
    this.subLabel,
    this.isFull = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: isFull ? 20 : 16, vertical: isFull ? 14 : 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1.2),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.1),
                blurRadius: 8,
                spreadRadius: 1),
          ],
        ),
        child: Row(
          mainAxisSize: isFull ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
            ],
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: isFull ? 16 : 14,
                  ),
                ),
                if (subLabel != null)
                  Text(
                    subLabel!,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.6),
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double blur;
  final Border? border;
  final DecorationImage? backgroundImage;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding,
    this.margin,
    this.color,
    this.blur = 10,
    this.border,
    this.backgroundImage,
  });


  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: color ?? Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(borderRadius),
              border: border ??
                  Border.all(
                      color: Colors.white.withValues(alpha: 0.15), width: 0.8),
              image: backgroundImage,
              gradient: backgroundImage == null ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.1),
                  Colors.white.withValues(alpha: 0.02),
                ],
              ) : null,
            ),

            child: child,
          ),
        ),
      ),
    );
  }
}

class PremiumItemSlot extends StatefulWidget {
  final Item item;
  final double size;
  final VoidCallback onTap;
  final bool isPaused;

  const PremiumItemSlot({
    super.key,
    required this.item,
    required this.onTap,
    this.size = 60,
    this.isPaused = false,
  });

  @override
  State<PremiumItemSlot> createState() => _PremiumItemSlotState();
}

class _PremiumItemSlotState extends State<PremiumItemSlot> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotateController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );

    _updateAnimations();
  }

  void _updateAnimations() {
    final grade = widget.item.grade;
    final needsPulse = grade == ItemGrade.unique || grade == ItemGrade.legendary || grade == ItemGrade.mythic || grade == ItemGrade.epic;
    final needsRotate = grade == ItemGrade.rare || grade == ItemGrade.unique || grade == ItemGrade.legendary || grade == ItemGrade.mythic;

    if (needsPulse) {
      _pulseController.repeat();
    } else {
      _pulseController.stop();
    }

    if (needsRotate) {
      _rotateController.repeat();
    } else {
      _rotateController.stop();
    }
  }

  @override
  void didUpdateWidget(PremiumItemSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.grade != widget.item.grade) {
      _updateAnimations();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grade = widget.item.grade;
    final size = widget.size;
    final bool isPaused = widget.isPaused;
    
    return PressableScale(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseController, _rotateController]),
        builder: (context, child) {
          final pulse = 0.5 + 0.5 * sin(_pulseController.value * 2 * pi);
          final rotateValue = _rotateController.value * 2 * pi;

          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: grade.bgGradient,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _getBorderColor(grade, pulse),
                width: _getBorderWidth(grade),
              ),
              boxShadow: _getDynamicShadow(grade, pulse),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // --- 백그라운드 등급별 특수 효과 ---
                  if (!isPaused) ...[
                    if (grade == ItemGrade.rare) _buildRareRotation(rotateValue),
                    if (grade == ItemGrade.epic) ..._buildEpicParticles(pulse),
                    if (grade == ItemGrade.unique) ..._buildUniqueEffects(pulse, rotateValue),
                    if (grade == ItemGrade.legendary) ..._buildLegendaryEffects(pulse, rotateValue),
                    if (grade == ItemGrade.mythic) ..._buildMythicEffects(pulse, rotateValue),
                  ],

                  // --- 공통: 아이템 아이콘 ---
                  _getItemEmoji(widget.item.type, size: size * 0.45),

                  // --- 공통: 강화 및 정보 배지 ---
                  ..._buildStatusWidgets(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getBorderColor(ItemGrade grade, double pulse) {
    switch (grade) {
      case ItemGrade.common: return const Color(0xFF9E9E9E);
      case ItemGrade.uncommon: return const Color(0xFF4CAF50);
      case ItemGrade.rare: return const Color(0xFF2196F3);
      case ItemGrade.epic: return const Color(0xFF9C27B0);
      case ItemGrade.unique: return const Color(0xFFEAB308);
      case ItemGrade.legendary: return const Color(0xFFF44336);
      case ItemGrade.mythic: return const Color(0xFFFF0000);
    }
  }

  double _getBorderWidth(ItemGrade grade) {
    return (grade == ItemGrade.legendary || grade == ItemGrade.mythic) ? 2.5 : 2.0;
  }

  List<BoxShadow> _getDynamicShadow(ItemGrade grade, double pulse) {
    switch (grade) {
      case ItemGrade.common:
        return [BoxShadow(color: const Color(0xFF9E9E9E).withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))];
      case ItemGrade.uncommon:
        return [BoxShadow(color: const Color(0xFF4CAF50).withOpacity(0.4), blurRadius: 8, spreadRadius: 1)];
      case ItemGrade.rare:
        return [BoxShadow(color: const Color(0xFF2196F3).withOpacity(0.5), blurRadius: 12, spreadRadius: 2)];
      case ItemGrade.epic:
        return [BoxShadow(color: const Color(0xFF9C27B0).withOpacity(0.6), blurRadius: 16, spreadRadius: 3)];
      case ItemGrade.unique:
        return [BoxShadow(color: const Color(0xFFEAB308).withOpacity(0.5 + 0.2 * pulse), blurRadius: 14 + 6 * pulse, spreadRadius: 2 + pulse)];
      case ItemGrade.legendary:
        return [BoxShadow(color: const Color(0xFFF44336).withOpacity(0.5 + 0.3 * pulse), blurRadius: 16 + 8 * pulse, spreadRadius: 2 + 2 * pulse)];
      case ItemGrade.mythic:
        return [BoxShadow(color: const Color(0xFFFF0000).withOpacity(0.6 + 0.3 * pulse), blurRadius: 24 + 12 * pulse, spreadRadius: 4 + 4 * pulse)];
    }
  }

  Widget _buildRareRotation(double angle) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: widget.size * 0.9,
        height: widget.size * 0.9,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2196F3).withOpacity(0.6), width: 1.5),
        ),
      ),
    );
  }

  List<Widget> _buildEpicParticles(double pulse) {
    return List.generate(6, (index) {
      final angle = (index * 60) * pi / 180;
      final phase = (_pulseController.value + index / 6) % 1;
      final offset = 18 + (4 * (0.5 + 0.5 * sin(phase * 2 * pi)));
      return Transform.translate(
        offset: Offset(offset * cos(angle), offset * sin(angle)),
        child: Container(
          width: 3, height: 3,
          decoration: BoxDecoration(
            color: const Color(0xFFE1BEE7), shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: const Color(0xFF9C27B0).withOpacity(0.8), blurRadius: 3)],
          ),
        ),
      );
    });
  }

  List<Widget> _buildUniqueEffects(double pulse, double rotateValue) {
    return [
      // 회전하는 사각 프레임
      Transform.rotate(
        angle: rotateValue,
        child: Container(
          width: widget.size * 0.7,
          height: widget.size * 0.7,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3), width: 1),
          ),
        ),
      ),
      // 4개의 춤추는 다이아몬드 파티클
      ...List.generate(4, (index) {
        final angle = (index * 90) * pi / 180 + rotateValue * 0.5;
        final orbit = 20.0 + 2 * pulse;
        return Transform.translate(
          offset: Offset(orbit * cos(angle), orbit * sin(orbit > 0 ? angle : 0)),
          child: Transform.rotate(
            angle: pi / 4,
            child: Container(
              width: 5, height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF176),
                boxShadow: [BoxShadow(color: const Color(0xFFFBC02D).withOpacity(0.8), blurRadius: 4)],
              ),
            ),
          ),
        );
      }),
      // 중앙 골든 글로우
      Opacity(
        opacity: 0.2 * pulse,
        child: Container(
          width: widget.size * 0.5,
          height: widget.size * 0.5,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFFFD700),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildLegendaryEffects(double pulse, double rotateValue) {
    return [
      // 1. 회전하는 다이아몬드 프레임 (마름모)
      Transform.rotate(
        angle: rotateValue + (pi / 4), // 기본 45도 회전된 상태에서 회전 애니메이션
        child: Container(
          width: widget.size * 0.75,
          height: widget.size * 0.75,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.4), width: 1.5),
          ),
        ),
      ),
      // 2. 4방향 방사형 맥동 파티클
      ...List.generate(4, (index) {
        final angle = (index * 90) * pi / 180;
        final orbit = 18.0 + 6.0 * pulse; // 맥동에 따라 거리 조절
        return Transform.translate(
          offset: Offset(orbit * cos(angle), orbit * sin(angle)),
          child: Container(
            width: 4, height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: const Color(0xFFF44336).withOpacity(0.8), blurRadius: 4, spreadRadius: 1)],
            ),
          ),
        );
      }),
      // 3. 중앙 강화된 성광 효과 (스케일 변화 포함)
      Transform.scale(
        scale: 0.8 + 0.4 * pulse,
        child: Opacity(
          opacity: 0.4 + 0.4 * pulse,
          child: Icon(Icons.auto_awesome, color: const Color(0xFFFFCDD2), size: widget.size * 0.5),
        ),
      ),
    ];
  }

  List<Widget> _buildMythicEffects(double pulse, double angle) {
    return [
      // 회전 육각형 1
      Transform.rotate(
        angle: angle,
        child: CustomPaint(size: Size(widget.size, widget.size), painter: HexagonPainter(color: const Color(0xFFF44336))),
      ),
      // 반방향 회전 육각형 2
      Transform.rotate(
        angle: -angle,
        child: CustomPaint(size: Size(widget.size * 0.85, widget.size * 0.85), painter: HexagonPainter(color: const Color(0xFFFF5252))),
      ),
      // 파티클
      ...List.generate(8, (index) {
        final pAngle = (index * 45) * pi / 180;
        final phase = (_pulseController.value * 2 + index / 8) % 1;
        final opacity = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
        return Transform.translate(
          offset: Offset(26 * cos(pAngle), 26 * sin(pAngle)),
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Container(
              width: 5, height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE), shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: const Color(0xFFF44336), blurRadius: 6)],
              ),
            ),
          ),
        );
      }),
      // 중앙 플레어
      Opacity(
        opacity: 0.7 + 0.3 * pulse,
        child: Icon(Icons.auto_awesome, color: Colors.white, size: widget.size * 0.45),
      ),
    ];
  }

  List<Widget> _buildStatusWidgets() {
    return [
      // 강화 수치 배지 (우측 상단) - 배경 제거 및 쉐도우 적용
      if (widget.item.enhanceLevel > 0)
        Positioned(
          top: 4,
          right: 4,
          child: Text(
            '+${widget.item.enhanceLevel}',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              shadows: [
                Shadow(offset: const Offset(1, 1), blurRadius: 2, color: Colors.black.withValues(alpha: 0.8)),
                Shadow(offset: const Offset(-0.5, -0.5), blurRadius: 1, color: Colors.black.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),

      // 티어 표시 (좌측 하단)
      Positioned(
        bottom: 4,
        left: 4,
        child: Text(
          'T${widget.item.tier}',
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      // 🆕 아이템 잠금 아이콘 (좌측 상단)
      if (widget.item.isLocked)
        const Positioned(
          top: 3,
          left: 3,
          child: Icon(
            Icons.lock,
            size: 11,
            color: Colors.amberAccent,
            shadows: [
              Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
            ],
          ),
        ),

      // 신규 획득 알림 (좌측 상단 - 잠금이 아닐 때만 혹은 약간 옆으로)
      if (widget.item.isNew && !widget.item.isLocked && !widget.isPaused)
        Positioned(
          top: 4,
          left: 4,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.redAccent.withOpacity(0.8), blurRadius: 4, spreadRadius: 1)
              ],
            ),
          ),
        ),
    ];
  }

  Widget _getItemEmoji(ItemType t, {double size = 20}) {
    String emoji;
    switch (t) { // ItemType enum 직접 비교로 수정
      case ItemType.weapon: emoji = '🗡️'; break;
      case ItemType.helmet: emoji = '🪖'; break;
      case ItemType.armor: emoji = '🛡️'; break;
      case ItemType.boots: emoji = '👢'; break;
      case ItemType.ring: emoji = '💍'; break;
      case ItemType.necklace: emoji = '🧿'; break;
      default: emoji = '📦';
    }
    return Text(
      emoji, 
      style: TextStyle(
        fontSize: size,
        shadows: [
          Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 4, offset: const Offset(1, 1))
        ]
      )
    );
  }
}

class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const PressableScale({super.key, required this.child, this.onTap});

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 100),
        lowerBound: 0.95,
        upperBound: 1.0,
        value: 1.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => widget.onTap != null ? _controller.reverse() : null,
      onTapUp: (_) => widget.onTap != null ? _controller.forward() : null,
      onTapCancel: () => widget.onTap != null ? _controller.forward() : null,
      onTap: widget.onTap,
      child: ScaleTransition(scale: _controller, child: widget.child),
    );
  }
}

class ItemIcon extends StatelessWidget {
  final ItemType type;
  final double size;
  final Color? color;

  const ItemIcon({
    super.key,
    required this.type,
    this.size = 20,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    String iconStr;
    switch (type) {
      case ItemType.weapon: iconStr = '🗡️'; break;
      case ItemType.helmet: iconStr = '🪖'; break;
      case ItemType.armor: iconStr = '🛡️'; break;
      case ItemType.boots: iconStr = '👢'; break;
      case ItemType.ring: iconStr = '💍'; break;
      case ItemType.necklace: iconStr = '🧿'; break;
    }
    
    return Text(
      iconStr,
      style: TextStyle(
        fontSize: size,
        color: color,
        shadows: const [
          Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
        ],
      ),
    );
  }
}

class EmptyItemIcon extends StatelessWidget {
  final ItemType type;
  final double size;

  const EmptyItemIcon({
    super.key,
    required this.type,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    switch (type) {
      case ItemType.weapon: icon = Icons.skateboarding; break;
      case ItemType.helmet: icon = Icons.smart_toy; break;
      case ItemType.armor: icon = Icons.shield; break;
      case ItemType.boots: icon = Icons.not_started; break;
      case ItemType.ring: icon = Icons.adjust; break;
      case ItemType.necklace: icon = Icons.all_out; break;
    }
    return Icon(icon, color: Colors.white24, size: size);
  }
}

class SkillIcon extends StatelessWidget {
  final Skill skill;
  final double size;

  const SkillIcon({
    super.key,
    required this.skill,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Text(skill.iconEmoji, style: TextStyle(fontSize: size));
  }
}

class ShimmerSheen extends StatelessWidget {
  final double progress;
  const ShimmerSheen({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final double slide = (progress * 4) - 2;
        
        return Transform.translate(
          offset: Offset(w * slide, h * slide),
          child: Transform.rotate(
            angle: pi / 4,
            child: Container(
              width: w * 0.4,
              height: h * 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: 0.4),
                    Colors.white.withValues(alpha: 0),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class AnimatedCountText extends StatefulWidget {
  final int count;
  final TextStyle style;
  final String suffix;

  const AnimatedCountText({
    super.key,
    required this.count,
    required this.style,
    this.suffix = '',
  });

  @override
  State<AnimatedCountText> createState() => _AnimatedCountTextState();
}

class _AnimatedCountTextState extends State<AnimatedCountText> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  int _currentValue = 0;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.count;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animation = Tween<double>(
      begin: _currentValue.toDouble(),
      end: widget.count.toDouble(),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutExpo));
  }

  @override
  void didUpdateWidget(AnimatedCountText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count) {
      _animation = Tween<double>(
        begin: _currentValue.toDouble(),
        end: widget.count.toDouble(),
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutExpo));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        _currentValue = _animation.value.toInt();
        return Text(
          '${BigNumberFormatter.format(_currentValue)}${widget.suffix}',
          style: widget.style,
        );
      },
    );
  }
}

/// 🔢 [v0.5.45] 방치형 게임 특화 무제한 숫자 포맷터
/// 1,000 단위로 K, M, B, T 단위를 사용하며 그 이후는 aa, ab, ac... 순으로 무한 확장됨.
class BigNumberFormatter {
  static const List<String> _units = [
    '', 'K', 'M', 'B', 'T', 
    'aa', 'ab', 'ac', 'ad', 'ae', 'af', 'ag', 'ah', 'ai', 'aj', 'ak', 'al', 'am', 'an', 'ao', 'ap', 'aq', 'ar', 'as', 'at', 'au', 'av', 'aw', 'ax', 'ay', 'az',
    'ba', 'bb', 'bc', 'bd', 'be', 'bf', 'bg', 'bh', 'bi', 'bj', 'bk', 'bl', 'bm', 'bn', 'bo', 'bp', 'bq', 'br', 'bs', 'bt', 'bu', 'bv', 'bw', 'bx', 'by', 'bz',
  ];

  static String format(num value) {
    if (value < 1000) return value.toInt().toString();
    
    double val = value.toDouble();
    int unitIndex = 0;
    
    while (val >= 1000 && unitIndex < _units.length - 1) {
      val /= 1000;
      unitIndex++;
    }

    String formattedValue;
    if (val >= 100) {
      formattedValue = val.toStringAsFixed(0);
    } else if (val >= 10) {
      formattedValue = val.toStringAsFixed(1);
    } else {
      formattedValue = val.toStringAsFixed(2);
    }

    if (formattedValue.contains('.')) {
      formattedValue = formattedValue.replaceAll(RegExp(r'\.?0+$'), '');
    }

    return formattedValue + _units[unitIndex];
  }
}

class HexagonPainter extends CustomPainter {
  final Color color;
  
  HexagonPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path();
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    for (int i = 0; i < 6; i++) {
      final angle = (i * 60 - 30) * pi / 180;
      final point = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HeroEffectPainter extends CustomPainter {
  final int promotionLevel;
  final bool isPlayer;
  final double pulse; // 0.0 ~ 1.0 (Pulse Controller)
  final double rotation; // 0.0 ~ 1.0 (Rotate Controller)

  HeroEffectPainter({
    required this.promotionLevel,
    required this.isPlayer,
    required this.pulse,
    required this.rotation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 🆕 기준점 이원화 (Ground vs Body)
    final groundCenter = Offset(size.width / 2, size.height - 20); // 발끝
    final bodyCenter = Offset(size.width / 2, size.height * 0.55); // 몸체 중앙
    final double time = DateTime.now().millisecondsSinceEpoch / 1000.0;

    // 🆕 10단계 무지개 효과용 Hue 계산
    Color getRainbowColor(double offset) {
      if (promotionLevel < 10) return isPlayer ? Colors.cyanAccent : Colors.redAccent;
      final double hue = (time * 60 + offset) % 360;
      return HSVColor.fromAHSV(1.0, hue, 0.7, 1.0).toColor();
    }

    // 1. 바닥 그림자
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(
      Rect.fromCenter(center: groundCenter, width: 60 - (10 * pulse), height: 12),
      shadowPaint,
    );

    // 2. 발밑 마법진 (groundCenter 기준)
    if (isPlayer && (promotionLevel >= 3)) {
      final sealPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.cyan.withValues(alpha: 0.15);

      if (promotionLevel >= 10) sealPaint.color = getRainbowColor(0).withValues(alpha: 0.3);

      canvas.save();
      canvas.translate(groundCenter.dx, groundCenter.dy);
      canvas.rotate(rotation * 2 * pi);
      canvas.drawCircle(Offset.zero, 45, sealPaint);
      
      final nodePaint = Paint()..style = PaintingStyle.fill;
      for (int i = 0; i < 4; i++) {
        double angle = i * pi / 2;
        nodePaint.color = Colors.cyan;
        if (promotionLevel >= 10) nodePaint.color = getRainbowColor(i * 90);
        canvas.drawCircle(Offset(cos(angle) * 45, sin(angle) * 45), 2.5, nodePaint);
      }
      canvas.restore();
    }

    // 3. 블룸 오라 (bodyCenter 기준 - 캐릭터 중심 배정)
    if (isPlayer && (promotionLevel >= 4)) {
      final auraPulse = 1.0 + (pulse * 0.12);
      final auraColor = promotionLevel >= 10 ? getRainbowColor(180) : Colors.blueAccent;
      
      final auraPaint = Paint()
        ..color = auraColor.withValues(alpha: 0.12 * (1 - pulse))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 20 + (10 * pulse));
      
      canvas.drawCircle(bodyCenter, 40 * auraPulse, auraPaint);
      
      if (promotionLevel >= 7) {
        final corePaint = Paint()
          ..color = auraColor.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        canvas.drawCircle(bodyCenter, 22, corePaint);
      }
    }

    // 4. 부유 파티클 (몸체 전체를 감싸도록 범위 조정)
    if (isPlayer && (promotionLevel >= 1)) {
      int particleCount = (4 + (promotionLevel * 2)).clamp(4, 20);
      for (int i = 0; i < particleCount; i++) {
        final double speed = 0.25 + (i * 0.05);
        final double progress = (pulse * speed + (i / particleCount)) % 1.0;
        
        // 파티클이 발끝에서 시작해 머리 위까지 솟아오름
        final double zigZag = sin(progress * pi * 4 + i) * 15.0; 
        final double startX = (i - (particleCount / 2)) * 8.0;
        final double currentY = groundCenter.dy - (size.height * 0.8 * progress); 
        
        final pColor = promotionLevel >= 10 ? getRainbowColor(i * 40) : (i % 2 == 0 ? Colors.cyanAccent : Colors.blueAccent);
        final pPaint = Paint()
          ..color = pColor.withValues(alpha: (1 - progress) * 0.6)
          ..style = PaintingStyle.fill;
          
        canvas.drawCircle(Offset(bodyCenter.dx + startX + zigZag, currentY), 1.5, pPaint);
        
        if (promotionLevel >= 8) {
           canvas.drawCircle(Offset(bodyCenter.dx + startX + zigZag, currentY), 3.0, pPaint..color = pColor.withValues(alpha: (1 - progress) * 0.12));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant HeroEffectPainter oldDelegate) {
    return oldDelegate.pulse != pulse || 
           oldDelegate.rotation != rotation || 
           oldDelegate.promotionLevel != promotionLevel;
  }
}
