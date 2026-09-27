import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Phone layouts are designed upright, like the existing SkorX app; a court
  // scoreboard that flips sideways mid-rally loses points. Not awaited: the
  // manifest and Info.plist already lock portrait, and the first frame (the
  // launch animation) should not wait on a platform round trip.
  unawaited(SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]));
  runApp(const ProviderScope(child: SkorxApp()));
}
