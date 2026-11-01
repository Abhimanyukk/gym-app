import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The shared loading animation for refreshes, authentication and future requests.
class DumbbellLoader extends StatefulWidget {
  const DumbbellLoader({
    super.key,
    this.size = 28,
    this.color,
    this.label = 'Loading',
  });

  final double size;
  final Color? color;
  final String label;

  @override
  State<DumbbellLoader> createState() => _DumbbellLoaderState();
}

class _DumbbellLoaderState extends State<DumbbellLoader>
    with SingleTickerProviderStateMixin {
  late final _rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_PullRefreshScope.visibleOf(context) ||
        MediaQuery.disableAnimationsOf(context)) {
      _rotation.stop();
      _rotation.value = 0;
    } else if (!_rotation.isAnimating) {
      _rotation.repeat();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PullRefreshScope.visibleOf(context)
      ? const SizedBox.shrink()
      : Semantics(
          label: widget.label,
          liveRegion: true,
          child: RotationTransition(
            turns: _rotation,
            child: SvgPicture.asset(
              'assets/icons/dumbell.svg',
              width: widget.size,
              height: widget.size,
              excludeFromSemantics: true,
              colorFilter: ColorFilter.mode(
                widget.color ?? Theme.of(context).colorScheme.primary,
                BlendMode.srcIn,
              ),
            ),
          ),
        );
}

// Inline request loaders yield to the page's pull indicator, without changing
// pending-request state, disabled controls, or initial/retry loading behavior.
class _PullRefreshScope extends InheritedWidget {
  const _PullRefreshScope({required this.visible, required super.child});

  final bool visible;

  static bool visibleOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_PullRefreshScope>()
          ?.visible ??
      false;

  @override
  bool updateShouldNotify(_PullRefreshScope oldWidget) =>
      visible != oldWidget.visible;
}

/// Forward body drags to the existing scroll position, not a second refresh
/// mechanism. Scrollable children still own their normal list gestures.
class ScrollDragRegion extends StatefulWidget {
  const ScrollDragRegion({
    super.key,
    required this.controller,
    required this.child,
    this.onUpdate,
    this.onlyAtTop = false,
  });

  final ScrollController controller;
  final Widget child;
  final ValueChanged<DragUpdateDetails>? onUpdate;
  final bool onlyAtTop;

  @override
  State<ScrollDragRegion> createState() => _ScrollDragRegionState();
}

class _ScrollDragRegionState extends State<ScrollDragRegion> {
  DragStartDetails? _start;
  Drag? _drag;

  void _update(DragUpdateDetails details) {
    widget.onUpdate?.call(details);
    if (_drag == null) {
      if (_start == null ||
          details.delta.dy <= 0 ||
          !widget.controller.hasClients ||
          (widget.onlyAtTop && widget.controller.position.extentBefore > 0)) {
        return;
      }
      _drag = widget.controller.position.drag(_start!, () => _drag = null);
    }
    _drag?.update(details);
  }

  void _cancel() {
    _start = null;
    _drag?.cancel();
    _drag = null;
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onVerticalDragStart: (details) => _start = details,
    onVerticalDragUpdate: _update,
    onVerticalDragEnd: (details) {
      _start = null;
      _drag?.end(details);
    },
    onVerticalDragCancel: _cancel,
    child: widget.child,
  );
}

/// Native pull-to-refresh lifecycle with a bare logo revealed above the content.
class DumbbellRefresh extends StatefulWidget {
  const DumbbellRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.scrollController,
    this.padding = EdgeInsets.zero,
  });

  final RefreshCallback onRefresh;
  final Widget child;
  final ScrollController? scrollController;
  final EdgeInsets padding;

  @override
  State<DumbbellRefresh> createState() => _DumbbellRefreshState();
}

class _DumbbellRefreshState extends State<DumbbellRefresh> {
  static const _minimumPull = 80.0;
  RefreshIndicatorStatus? _status;
  double _pullDistance = 0;

  bool get _dragging =>
      _status == RefreshIndicatorStatus.drag ||
      _status == RefreshIndicatorStatus.armed;

  void _statusChanged(RefreshIndicatorStatus? status) {
    if (!mounted) return;
    setState(() {
      _status = status;
      // noSpinner does not report null after dismissal. Done/canceled must
      // explicitly hide our indicator instead of leaving the last icon behind.
      if (status == RefreshIndicatorStatus.drag ||
          status == RefreshIndicatorStatus.done ||
          status == RefreshIndicatorStatus.canceled ||
          status == null) {
        _pullDistance = 0;
      }
    });
  }

  bool _scrollChanged(ScrollNotification notification) {
    if (!_dragging ||
        notification.depth != 0 ||
        notification.metrics.axisDirection != AxisDirection.down) {
      return false;
    }
    final delta = switch (notification) {
      ScrollUpdateNotification(:final dragDetails, :final scrollDelta)
          when dragDetails != null =>
        scrollDelta,
      OverscrollNotification(:final dragDetails, :final overscroll)
          when dragDetails != null =>
        overscroll,
      _ => null,
    };
    if (delta != null) {
      setState(() {
        _pullDistance -= delta;
      });
    }
    return false;
  }

  Future<void> _refresh() async {
    // Native thresholds shrink with the viewport. A short card must still
    // require a deliberate pull, rather than refreshing from a small movement.
    if (_pullDistance < _minimumPull) return;
    try {
      await widget.onRefresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to refresh. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final refreshing =
        (_status == RefreshIndicatorStatus.snap ||
            _status == RefreshIndicatorStatus.refresh) &&
        _pullDistance >= _minimumPull;
    // dover-gain-efficient: keep native arming/cancellation/release; track only
    // the visual pull and minimum intent, not a second gesture state machine.
    final extent = refreshing
        ? 56.0
        : _dragging
        ? ((_pullDistance - _minimumPull / 2) * .4).clamp(0.0, 56.0).toDouble()
        : 0.0;
    Widget body = Padding(padding: widget.padding, child: widget.child);
    if (widget.scrollController != null) {
      body = ScrollDragRegion(
        controller: widget.scrollController!,
        child: body,
      );
    }
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          ...ScrollConfiguration.of(context).dragDevices,
          PointerDeviceKind.mouse,
        },
      ),
      child: NotificationListener<ScrollNotification>(
        onNotification: _scrollChanged,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: extent),
          duration: _dragging || MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
          child: RefreshIndicator.noSpinner(
            onRefresh: _refresh,
            onStatusChange: _statusChanged,
            notificationPredicate: (notification) =>
                notification.depth == 0 &&
                notification.metrics.axis == Axis.vertical,
            child: _PullRefreshScope(visible: extent > 0, child: body),
          ),
          builder: (context, reveal, child) => ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Transform.translate(offset: Offset(0, reveal), child: child),
                if (extent > 0)
                  Positioned(
                    top: widget.padding.top,
                    left: widget.padding.left,
                    right: widget.padding.right,
                    height: reveal,
                    child: IgnorePointer(
                      child: ClipRect(
                        child: Center(
                          child: Opacity(
                            key: const ValueKey('pull-refresh-indicator'),
                            opacity: (reveal / 40).clamp(0.0, 1.0).toDouble(),
                            child: refreshing
                                ? const DumbbellLoader(label: 'Refreshing')
                                : SvgPicture.asset(
                                    'assets/icons/dumbell.svg',
                                    width: 28,
                                    height: 28,
                                    colorFilter: ColorFilter.mode(
                                      Theme.of(context).colorScheme.primary,
                                      BlendMode.srcIn,
                                    ),
                                    semanticsLabel:
                                        _status ==
                                                RefreshIndicatorStatus.armed &&
                                            _pullDistance >= _minimumPull
                                        ? 'Release to refresh'
                                        : 'Pull down to refresh',
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// dover-gain-efficient: rebuild local data only until a real repository exists.
// The debug-only delay previews the loader; never claim a server sync succeeded.
Future<void> refreshLocalView(
  BuildContext context, {
  required bool preview,
  required VoidCallback rebuild,
}) async {
  if (kDebugMode && preview) {
    await Future<void>.delayed(const Duration(milliseconds: 650));
  }
  if (!context.mounted) return;
  rebuild();
  if (!preview) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Backend not connected. Live data cannot be refreshed yet.',
        ),
      ),
    );
  }
}
