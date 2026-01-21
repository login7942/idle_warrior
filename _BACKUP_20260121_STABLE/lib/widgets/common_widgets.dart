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

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding,
    this.margin,
    this.color,
    this.blur = 10,
    this.border,
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
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.1),
                  Colors.white.withValues(alpha: 0.02),
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class PremiumItemSlot extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: item.grade.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: item.grade.color.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            _getItemEmoji(item.type, size: size * 0.4),
            if (item.enhanceLevel > 0)
              Positioned(
                top: 2,
                right: 4,
                child: Text(
                  '+${item.enhanceLevel}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (item.isNew && !isPaused)
              Positioned(
                top: 2,
                left: 2,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _getItemEmoji(ItemType t, {double size = 20}) {
    String emoji;
    switch (t.name) {
      case 'weapon': emoji = '🗡️'; break;
      case 'helmet': emoji = '🪖'; break;
      case 'armor': emoji = '🛡️'; break;
      case 'boots': emoji = '👢'; break;
      case 'ring': emoji = '💍'; break;
      case 'necklace': emoji = '🧿'; break;
      default: emoji = '📦';
    }
    return Text(emoji, style: TextStyle(fontSize: size));
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
    _animation = Tween<double>(begin: _currentValue.toDouble(), end: widget.count.toDouble()).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutExpo),
    );
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
    final formatter = NumberFormat('#,###');
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        _currentValue = _animation.value.toInt();
        return Text(
          '${formatter.format(_currentValue)}${widget.suffix}',
          style: widget.style,
        );
      },
    );
  }
}
