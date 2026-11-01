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
    if (MediaQuery.disableAnimationsOf(context)) {
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
  Widget build(BuildContext context) => Semantics(
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

/// Native pull thresholds and async lifecycle, with our logo instead of a spinner.
class DumbbellRefresh extends StatefulWidget {
  const DumbbellRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final RefreshCallback onRefresh;
  final Widget child;

  @override
  State<DumbbellRefresh> createState() => _DumbbellRefreshState();
}

class _DumbbellRefreshState extends State<DumbbellRefresh> {
  RefreshIndicatorStatus? _status;

  Future<void> _refresh() async {
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
        _status == RefreshIndicatorStatus.snap ||
        _status == RefreshIndicatorStatus.refresh;
    return Stack(
      children: [
        ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              ...ScrollConfiguration.of(context).dragDevices,
              PointerDeviceKind.mouse,
            },
          ),
          child: RefreshIndicator.noSpinner(
            onRefresh: _refresh,
            onStatusChange: (status) => setState(() => _status = status),
            child: widget.child,
          ),
        ),
        if (_status != null && _status != RefreshIndicatorStatus.canceled)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Material(
                  color: Theme.of(context).colorScheme.primary,
                  shape: const CircleBorder(),
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: refreshing
                        ? const DumbbellLoader(
                            size: 32,
                            color: Colors.white,
                            label: 'Refreshing',
                          )
                        : SvgPicture.asset(
                            'assets/icons/dumbell.svg',
                            width: 32,
                            height: 32,
                            colorFilter: const ColorFilter.mode(
                              Colors.white,
                              BlendMode.srcIn,
                            ),
                            semanticsLabel:
                                _status == RefreshIndicatorStatus.armed
                                ? 'Release to refresh'
                                : 'Pull down to refresh',
                          ),
                  ),
                ),
              ),
            ),
          ),
      ],
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
