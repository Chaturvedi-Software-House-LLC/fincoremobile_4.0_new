import 'package:flutter/material.dart';
import '../constants.dart';

class ScrollFab extends StatefulWidget {
  final ScrollController controller;
  const ScrollFab({super.key, required this.controller});

  @override
  State<ScrollFab> createState() => _ScrollFabState();
}

class _ScrollFabState extends State<ScrollFab>
    with SingleTickerProviderStateMixin {
  bool _scrollingDown = true;
  bool _visible = false;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    widget.controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (!widget.controller.hasClients) return;
    final offset = widget.controller.offset;
    final max = widget.controller.position.maxScrollExtent;

    final bool newVisible = max > 120 && offset > 60;
    // Based on *where the user currently is*, not which way they last
    // scrolled - within 60px of the bottom shows the up-arrow (there's
    // nowhere further down to go), otherwise the down-arrow. Using the
    // last scroll delta instead (the previous behavior) meant pausing
    // after scrolling down, or a small upward flick near the bottom,
    // could leave the icon pointing the "wrong" way relative to where
    // tapping it would actually take you.
    final bool newDown = offset < max - 60;

    if (newVisible != _visible) {
      setState(() => _visible = newVisible);
      if (newVisible) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    }
    if (newDown != _scrollingDown) {
      setState(() => _scrollingDown = newDown);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 88,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: FloatingActionButton.small(
          heroTag: UniqueKey(),
          onPressed: () {
            if (_scrollingDown) {
              widget.controller.animateTo(
                widget.controller.position.maxScrollExtent,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
              );
            } else {
              widget.controller.animateTo(
                0,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
              );
            }
          },
          backgroundColor: app_color,
          elevation: 4,
          child: Icon(
            _scrollingDown
                ? Icons.keyboard_double_arrow_down_rounded
                : Icons.keyboard_double_arrow_up_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
