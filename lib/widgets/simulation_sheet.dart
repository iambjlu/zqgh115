import 'package:flutter/material.dart';

import '../models/simulation_values.dart';
import '../theme/hud_colors.dart';


class SimulationSheet extends StatefulWidget {
  const SimulationSheet({
    super.key,
    required this.initialValues,
    required this.onChanged,
  });

  final SimulationValues initialValues;
  final ValueChanged<SimulationValues> onChanged;

  @override
  State<SimulationSheet> createState() => _SimulationSheetState();
}

class _SimulationSheetState extends State<SimulationSheet> {
  late SimulationValues _values = widget.initialValues;

  void _update(SimulationValues next) {
    setState(() => _values = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('模擬控制', style: textTheme.titleMedium),
            const SizedBox(height: 12),
            _SliderField(
              label: '自身車速',
              value: _values.bikeSpeed,
              unit: 'km/h',
              min: 0,
              max: 45,
              onChanged: (v) => _update(_values.copyWith(bikeSpeed: v)),
            ),
            const SizedBox(height: 12),
            _ThreatGroup(
              title: '左後方車輛',
              tagColor: HudColors.safe,
              distance: _values.leftDistance,
              approaching: _values.leftApproaching,
              onDistanceChanged: (v) => _update(_values.copyWith(leftDistance: v)),
              onApproachingChanged: (v) => _update(_values.copyWith(leftApproaching: v)),
            ),
            const SizedBox(height: 12),
            _ThreatGroup(
              title: '右後方車輛',
              tagColor: HudColors.danger,
              distance: _values.rightDistance,
              approaching: _values.rightApproaching,
              onDistanceChanged: (v) => _update(_values.copyWith(rightDistance: v)),
              onApproachingChanged: (v) => _update(_values.copyWith(rightApproaching: v)),
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('前方路況', style: Theme.of(context).textTheme.labelLarge),
                    _FrontField(
                      label: '左前',
                      value: _values.frontLeft,
                      onChanged: (v) => _update(_values.copyWith(frontLeft: v)),
                    ),
                    _FrontField(
                      label: '正前',
                      value: _values.frontCenter,
                      onChanged: (v) => _update(_values.copyWith(frontCenter: v)),
                    ),
                    _FrontField(
                      label: '右前',
                      value: _values.frontRight,
                      onChanged: (v) => _update(_values.copyWith(frontRight: v)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 前方單一方向的路況下拉選單：沒有／坑洞／障礙物／坑洞加障礙物。
class _FrontField extends StatelessWidget {
  const _FrontField({required this.label, required this.value, required this.onChanged});

  static const _labels = {
    FrontHazard.none: '無',
    FrontHazard.pothole: '坑洞',
    FrontHazard.obstacle: '障礙物',
    FrontHazard.both: '坑洞＋障礙物',
  };

  final String label;
  final FrontHazard value;
  final ValueChanged<FrontHazard> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        DropdownButton<FrontHazard>(
          value: value,
          items: [
            for (final h in FrontHazard.values)
              DropdownMenuItem(value: h, child: Text(_labels[h]!)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}

class _ThreatGroup extends StatelessWidget {
  const _ThreatGroup({
    required this.title,
    required this.tagColor,
    required this.distance,
    required this.approaching,
    required this.onDistanceChanged,
    required this.onApproachingChanged,
  });

  static const distanceOptions = [5.0, 15.0, 30.0, 99.0]; // 近 / 中 / 遠 / 沒車
  static final _distanceLabels = {5.0: '近', 15.0: '中', 30.0: '遠', 99.0: '沒車'};

  final String title;
  final Color tagColor;
  final double distance;
  final bool approaching;
  final ValueChanged<double> onDistanceChanged;
  final ValueChanged<bool> onApproachingChanged;

  @override
  Widget build(BuildContext context) {
    // 下拉選單只接受清單裡的值，距離若不在預設選項中（例如舊資料），
    // 就退回最接近的一個，避免 DropdownButton 找不到對應值而噴錯。
    final nearestDistance = distanceOptions.reduce(
      (a, b) => (a - distance).abs() <= (b - distance).abs() ? a : b,
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 10, color: tagColor),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('距離'),
                DropdownButton<double>(
                  value: nearestDistance,
                  items: [
                    for (final option in distanceOptions)
                      DropdownMenuItem(value: option, child: Text(_distanceLabels[option]!)),
                  ],
                  onChanged: (v) {
                    if (v != null) onDistanceChanged(v);
                  },
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('逼近'),
              value: approaching,
              onChanged: onApproachingChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.label,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final String unit;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: textTheme.bodyMedium),
            Text('${value.round()} $unit', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
      ],
    );
  }
}
