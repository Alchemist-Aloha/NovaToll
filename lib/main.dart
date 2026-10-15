import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'app.dart';
export 'app.dart' show NovaTollApp;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  runApp(const NovaTollApp());
}
