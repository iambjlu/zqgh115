import 'package:flutter/material.dart';

import 'live_google_map.dart';

class MapCard extends StatelessWidget {
  const MapCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: const SizedBox(height: 150, child: LiveGoogleMap()),
    );
  }
}
