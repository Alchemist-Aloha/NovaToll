import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The supplied 1429 x 1707 artwork with image-calibrated ramp markers.
///
/// RouteMap deliberately reports all records belonging to a selected visual
/// point. The parent remains responsible for selecting a direction or route.
class RouteMap extends StatefulWidget {
  const RouteMap({
    super.key,
    required this.ramps,
    required this.onChoose,
    this.entryId,
    this.exitId,
    this.reachableIds,
    this.bottomPadding = 0,
  });

  final List<Map<String, dynamic>> ramps;
  final void Function(List<Map<String, dynamic>>) onChoose;
  final String? entryId;
  final String? exitId;
  final Set<String>? reachableIds;
  final double bottomPadding;

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _Point {
  _Point(this.key, this.name, this.road, this.x, this.y, this.records);
  final String key;
  final String name;
  final String road;
  final double x;
  final double y;
  final List<Map<String, dynamic>> records;
}

class _RouteMapState extends State<RouteMap> {
  static const _mapWidth = 1429.0;
  static const _mapHeight = 1707.0;
  final _controller = TransformationController();
  double _scale = 1;
  Size _viewport = Size.zero;
  bool _didFit = false;
  Size _fittedViewport = Size.zero;
  double _fittedBottomPadding = 0;
  bool _userInteracted = false;

  static const _mapInset = 12.0;
  static const _tapDiameter = 56.0;
  bool _normalizing = false;
  bool _fitPending = false;
  static const _minimumUsableHeight = 80.0;

  double get _usableHeight => math.max(
    _minimumUsableHeight,
    _viewport.height - _mapInset * 2 - widget.bottomPadding,
  );

  double get _minimumScale => math.min(
    (_viewport.width - _mapInset * 2) / _mapWidth,
    _usableHeight / _mapHeight,
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransform);
    _controller.dispose();
    super.dispose();
  }

  Matrix4 get _fitMatrix {
    final scale = _minimumScale;
    // InteractiveViewer measures all three axes, including for a 2D map.
    final matrix = Matrix4.diagonal3Values(scale, scale, scale);
    matrix.setTranslationRaw(
      (_viewport.width - _mapWidth * scale) / 2,
      _mapInset + (_usableHeight - _mapHeight * scale) / 2,
      0,
    );
    return matrix;
  }

  void _onTransform() {
    if (_normalizing || _viewport.isEmpty) return;
    final matrix = _controller.value;
    final scale = matrix.getMaxScaleOnAxis();
    final minimum = _minimumScale;
    Matrix4 normalized;
    if (scale <= minimum + .000001) {
      normalized = _fitMatrix;
    } else {
      normalized = matrix.clone();
      final width = _mapWidth * scale;
      final height = _mapHeight * scale;
      final x = width <= _viewport.width - _mapInset * 2
          ? (_viewport.width - width) / 2
          : matrix.storage[12]
                .clamp(_viewport.width - _mapInset - width, _mapInset)
                .toDouble();
      final y = height <= _usableHeight
          ? _mapInset + (_usableHeight - height) / 2
          : matrix.storage[13]
                .clamp(_mapInset + _usableHeight - height, _mapInset)
                .toDouble();
      normalized.setTranslationRaw(x, y, 0);
    }
    if (normalized != matrix) {
      _normalizing = true;
      _controller.value = normalized;
      _normalizing = false;
    }
    final next = normalized.getMaxScaleOnAxis();
    if ((next - _scale).abs() > .000001 && mounted) {
      setState(() => _scale = next);
    }
  }

  String _road(dynamic road) =>
      <String, String>{
        '495': 'I-495',
        '95': 'I-95',
        '395': 'I-395',
        '66': 'I-66',
        '66outside': 'I-66 outside Beltway',
      }['$road'] ??
      '$road';

  String _normalize(String value) => value
      .replaceFirst(RegExp(r'^I-\d+(?: (?:east|west))? · '), '')
      .replaceFirst(RegExp(r' \((?:express|regular lanes)\)$'), '')
      .replaceFirst(RegExp(r'\s+(?:NB|SB)$'), '')
      .replaceAll(
        '495 Express Lanes Start/Georg Wash. Mem. Pkwy.',
        'George Washington Memorial Parkway',
      )
      .replaceAll(
        '495 Express Lanes End/George Wash. Mem. Pkwy.',
        'George Washington Memorial Parkway',
      );

  List<double>? _position(Map<String, dynamic> record) {
    final mapX = record['mapX'];
    final mapY = record['mapY'];
    if (mapX is num &&
        mapY is num &&
        mapX.isFinite &&
        mapY.isFinite &&
        mapX >= 0 &&
        mapX <= _mapWidth &&
        mapY >= 0 &&
        mapY <= _mapHeight) {
      return [mapX.toDouble(), mapY.toDouble()];
    }
    final id = '${record['id'] ?? ''}';
    const west = <String, List<double>>{
      '50': [712, 311],
      'monument': [653, 328],
      'stringfellow': [608, 340],
      '28': [510, 376],
      '29g': [239, 500],
    };
    if (id.startsWith('66w:') || id.startsWith('66g:')) {
      return west[id.split(':').last];
    }
    final latitude = double.tryParse('${record['latitude'] ?? ''}');
    final longitude = double.tryParse('${record['longitude'] ?? ''}');
    if (latitude == null || longitude == null) {
      return null;
    }
    final road = '${record['road'] ?? record['group'] ?? ''}';
    if (road.startsWith('66')) {
      return _interpolate(longitude, const [
        [-77.235, 905, 257],
        [-77.217, 917, 251],
        [-77.199, 957, 215],
        [-77.182, 984, 206],
        [-77.166, 1026, 231],
        [-77.152, 1067, 251],
        [-77.124, 1116, 267],
        [-77.10, 1138, 243],
        [-77.084, 1180, 232],
        [-77.068, 1225, 208],
        [-77.055, 1255, 220],
      ]);
    }
    if (road == '495') {
      return _interpolate(latitude, const [
        [38.969, 994, 27],
        [38.964, 982, 54],
        [38.945, 947, 100],
        [38.931, 928, 147],
        [38.9275, 924, 170],
        [38.9193, 927, 194],
        [38.9105, 924, 221],
        [38.886, 916, 253],
        [38.8758, 917, 294],
        [38.854, 919, 362],
        [38.84, 927, 393],
        [38.82, 917, 443],
        [38.811, 940, 466],
        [38.80, 988, 493],
        [38.79, 1009, 508],
      ]);
    }
    if (road == '395' || (road == '95' && latitude > 38.801)) {
      return _interpolate(latitude, const [
        [38.883, 1297, 278],
        [38.8664, 1276, 294],
        [38.851, 1243, 345],
        [38.845, 1207, 374],
        [38.83, 1137, 414],
        [38.811, 1051, 468],
        [38.80, 1009, 508],
      ]);
    }
    return _interpolate(latitude, const [
      [38.80, 1009, 508],
      [38.77, 998, 552],
      [38.75, 995, 604],
      [38.729, 982, 656],
      [38.70, 933, 707],
      [38.681, 918, 760],
      [38.6704, 904, 801],
      [38.6565, 869, 823],
      [38.6362, 800, 853],
      [38.608, 778, 921],
      [38.574, 740, 1002],
      [38.52, 691, 1113],
      [38.483, 602, 1232],
      [38.4525, 573, 1303],
      [38.422, 533, 1388],
      [38.38, 533, 1450],
      [38.344, 488, 1507],
      [38.30, 422, 1580],
      [38.26, 399, 1640],
    ]);
  }

  List<double> _interpolate(double value, List<List<num>> anchors) {
    final points = [...anchors]..sort((a, b) => b.first.compareTo(a.first));
    if (value >= points.first.first) {
      return [points.first[1].toDouble(), points.first[2].toDouble()];
    }
    if (value <= points.last.first) {
      return [points.last[1].toDouble(), points.last[2].toDouble()];
    }
    for (var i = 1; i < points.length; i++) {
      if (value >= points[i].first) {
        final a = points[i - 1], b = points[i];
        final f = (a.first - value) / (a.first - b.first);
        return [
          a[1] + f * (b[1] - a[1]),
          a[2] + f * (b[2] - a[2]),
        ].map((e) => e.toDouble()).toList();
      }
    }
    return [0, 0];
  }

  List<_Point> get _points {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final ramp in widget.ramps) {
      final label = _normalize(
        '${ramp['mapLabel'] ?? ramp['label'] ?? ramp['name'] ?? ramp['id'] ?? ''}',
      );
      final road = '${ramp['road'] ?? ramp['group'] ?? ''}';
      final pos = _position(ramp);
      if (pos == null) continue;
      final key = ramp['mapKey'] as String? ?? '$road:$label';
      groups.putIfAbsent(key, () => []).add(ramp);
    }
    return groups.entries.map((entry) {
      final first = entry.value.first;
      final pos = _position(first)!;
      return _Point(
        entry.key,
        _normalize(
          '${first['mapLabel'] ?? first['label'] ?? first['name'] ?? ''}',
        ),
        '${first['road'] ?? first['group'] ?? ''}',
        pos[0],
        pos[1],
        entry.value,
      );
    }).toList();
  }

  bool _reachable(_Point point) {
    final ids = widget.reachableIds;
    return ids == null ||
        ids.contains(point.key) ||
        point.records.any(
          (r) => r['ramp'] == 'exit' && ids.contains('${r['id']}'),
        );
  }

  bool _selected(_Point point, String? id) =>
      id != null && point.records.any((r) => '${r['id']}' == id);

  void _fit() {
    if (_viewport.isEmpty) {
      return;
    }
    _controller.value = _fitMatrix;
    _fittedViewport = _viewport;
    _fittedBottomPadding = widget.bottomPadding;
    _userInteracted = false;
    if (mounted) setState(() => _didFit = true);
  }

  void _scheduleFit() {
    if (_fitPending) return;
    final geometryChanged =
        _fittedViewport != _viewport ||
        _fittedBottomPadding != widget.bottomPadding;
    if (_didFit && !geometryChanged) return;
    _fitPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitPending = false;
      if (!mounted) return;
      if (!_userInteracted) {
        _fit();
      } else {
        _fittedViewport = _viewport;
        _fittedBottomPadding = widget.bottomPadding;
        _onTransform();
      }
    });
  }

  void _zoom(double factor) {
    final old = _controller.value.getMaxScaleOnAxis();
    final minimum = _viewport.isEmpty ? .08 : _minimumScale;
    final next = (old * factor).clamp(minimum, 4.0).toDouble();
    if (next <= minimum + .000001) {
      _fit();
      return;
    }
    final center = Offset(_viewport.width / 2, _mapInset + _usableHeight / 2);
    final scene = MatrixUtils.transformPoint(
      _controller.value.clone()..invert(),
      center,
    );
    final ratio = next / old;
    final matrix = _controller.value.clone()
      ..translateByDouble(scene.dx, scene.dy, 0, 1)
      ..scaleByDouble(ratio, ratio, ratio, 1)
      ..translateByDouble(-scene.dx, -scene.dy, 0, 1);
    _userInteracted = true;
    _controller.value = matrix;
  }

  void _choose(_Point point, {Offset? viewportPosition}) {
    if (!_reachable(point)) {
      return;
    }
    final tapped =
        viewportPosition ??
        MatrixUtils.transformPoint(_controller.value, Offset(point.x, point.y));
    final overlap = _points
        .where(_reachable)
        .where(
          (p) =>
              (MatrixUtils.transformPoint(_controller.value, Offset(p.x, p.y)) -
                      tapped)
                  .distance <=
              24,
        )
        .toList();
    if (overlap.length > 1) {
      unawaited(
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: Theme.of(context).colorScheme.surface,
          builder: (context) {
            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Choose the ramp at this point',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  for (final candidate in overlap)
                    ListTile(
                      title: Text(
                        '${_road(candidate.road)} · ${candidate.name}',
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onChoose(candidate.records);
                      },
                    ),
                ],
              ),
            );
          },
        ),
      );
    } else {
      widget.onChoose(point.records);
    }
  }

  Future<void> _showSearch() async {
    final point = await showDialog<_Point>(
      context: context,
      builder: (context) => _RampSearchDialog(
        points: _points,
        roadLabel: _road,
        isReachable: _reachable,
      ),
    );
    if (mounted && point != null && _reachable(point)) {
      widget.onChoose(point.records);
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = _points.where(
      (point) => _reachable(point) || _selected(point, widget.entryId),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final window = MediaQuery.sizeOf(context);
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : window.width;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : window.height;
        return SizedBox(
          width: width,
          height: height,
          child: LayoutBuilder(
            builder: (context, box) {
              _viewport = Size(box.maxWidth, box.maxHeight);
              _scheduleFit();
              final colors = Theme.of(context).colorScheme;
              final showFullMap =
                  MediaQuery.sizeOf(context).shortestSide >= 600;
              return ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    InteractiveViewer(
                      transformationController: _controller,
                      minScale: _minimumScale,
                      maxScale: 4,
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      constrained: false,
                      onInteractionStart: (_) => _userInteracted = true,
                      panEnabled: true,
                      scaleEnabled: true,
                      child: SizedBox(
                        width: _mapWidth,
                        height: _mapHeight,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Image.asset(
                                'assets/map.png',
                                fit: BoxFit.fill,
                              ),
                            ),
                            for (final point in points)
                              Positioned(
                                left:
                                    point.x -
                                    _tapDiameter / 2 / _scale.clamp(.01, 100),
                                top:
                                    point.y -
                                    _tapDiameter / 2 / _scale.clamp(.01, 100),
                                child: _marker(point),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (_usableHeight >= 232)
                      Positioned(
                        right: 12,
                        bottom: 16 + widget.bottomPadding,
                        child: Column(
                          children: [
                            _mapButton(
                              Icons.search,
                              _showSearch,
                              'Search ramps',
                            ),
                            const SizedBox(height: 8),
                            _mapButton(Icons.add, () => _zoom(1.5), 'Zoom in'),
                            const SizedBox(height: 8),
                            _mapButton(
                              Icons.remove,
                              () => _zoom(1 / 1.5),
                              'Zoom out',
                            ),
                            if (showFullMap) ...[
                              const SizedBox(height: 8),
                              _mapButton(Icons.fit_screen, _fit, 'Full map'),
                            ],
                          ],
                        ),
                      )
                    else
                      Positioned(
                        right: 12,
                        bottom: 16 + widget.bottomPadding,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _mapButton(
                              Icons.search,
                              _showSearch,
                              'Search ramps',
                            ),
                          ],
                        ),
                      ),
                    Positioned(
                      left: 12,
                      right: 72,
                      bottom: 12 + widget.bottomPadding,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest.withValues(
                            alpha: .92,
                          ),
                          borderRadius: BorderRadius.all(Radius.circular(5)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          child: Text(
                            'Illustrative map · not to scale',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _mapButton(IconData icon, VoidCallback onPressed, String tooltip) =>
      SizedBox(
        width: 48,
        height: 48,
        child: Tooltip(
          message: tooltip,
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon),
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHigh,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      );

  Widget _marker(_Point point) {
    final colors = Theme.of(context).colorScheme;
    final origin = _selected(point, widget.entryId);
    final exit = _selected(point, widget.exitId);
    final reachable = _reachable(point);
    return Semantics(
      button: true,
      label:
          '${point.name}, ${_road(point.road)}${origin
              ? ', selected entry'
              : exit
              ? ', selected exit'
              : ''}',
      onTap: reachable ? () => _choose(point) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: reachable
            ? (details) {
                final box = context.findRenderObject()! as RenderBox;
                _choose(
                  point,
                  viewportPosition: box.globalToLocal(details.globalPosition),
                );
              }
            : null,
        child: SizedBox(
          key: ValueKey('ramp-hit:${point.key}'),
          width: _tapDiameter / _scale.clamp(.01, 100),
          height: _tapDiameter / _scale.clamp(.01, 100),
          child: Center(
            child: Container(
              key: ValueKey('ramp-marker:${point.key}'),
              width: (origin || exit ? 34 : 20) / _scale.clamp(.01, 100),
              height: (origin || exit ? 34 : 20) / _scale.clamp(.01, 100),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: exit
                    ? colors.error
                    : origin
                    ? colors.primary
                    : reachable
                    ? colors.primaryContainer
                    : colors.surfaceContainerHighest,
                border: Border.all(
                  color: exit
                      ? colors.onError
                      : origin
                      ? colors.onPrimary
                      : colors.primary,
                  width: (origin || exit ? 3 : 2) / _scale.clamp(.01, 100),
                ),
              ),
              child: (origin || exit)
                  ? Padding(
                      padding: EdgeInsets.all(6 / _scale.clamp(.01, 100)),
                      child: FittedBox(
                        child: Text(
                          origin ? 'A' : 'B',
                          style: TextStyle(
                            color: exit ? colors.onError : colors.onPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _RampSearchDialog extends StatefulWidget {
  const _RampSearchDialog({
    required this.points,
    required this.roadLabel,
    required this.isReachable,
  });
  final List<_Point> points;
  final String Function(dynamic) roadLabel;
  final bool Function(_Point) isReachable;

  @override
  State<_RampSearchDialog> createState() => _RampSearchDialogState();
}

class _RampSearchDialogState extends State<_RampSearchDialog> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final matches = widget.points
        .where(
          (point) => '${widget.roadLabel(point.road)} ${point.name}'
              .toLowerCase()
              .contains(query.toLowerCase()),
        )
        .toList();
    return Dialog(
      child: SizedBox(
        width: 560,
        height: math.min(560, MediaQuery.sizeOf(context).height * .75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Find a ramp',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close search',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                autofocus: true,
                onChanged: (value) => setState(() => query = value),
                decoration: const InputDecoration(
                  labelText: 'Ramp or road',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: matches.isEmpty
                    ? const Center(child: Text('No matching ramps'))
                    : ListView.builder(
                        itemCount: matches.length,
                        itemBuilder: (context, index) {
                          final point = matches[index];
                          final reachable = widget.isReachable(point);
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            title: Text(
                              '${widget.roadLabel(point.road)} · ${point.name}',
                            ),
                            enabled: reachable,
                            subtitle: reachable
                                ? null
                                : const Text('Unavailable for this route'),
                            onTap: reachable
                                ? () => Navigator.pop(context, point)
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
