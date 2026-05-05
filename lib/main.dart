import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'data/models/fill.dart';
import 'data/repositories/fill_repository.dart';
import 'data/services/fill_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive bootstrap. Done before [runApp] so the first frame can read
  // a hydrated [FillStorage] without an async gap. `initFlutter` picks
  // a platform-appropriate documents directory via `path_provider`.
  await Hive.initFlutter();
  registerFillAdapters();
  final FillStorage fillStorage = await FillStorage.open();
  final FillRepository fillRepository = LocalFillRepository(
    storage: fillStorage,
  );

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(LuminaApp(fillRepositoryOverride: fillRepository));
}
