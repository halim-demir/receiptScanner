import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'screens/main_nav_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // iOS specific: Ensure the Documents directory is accessed and has a 
  // placeholder if empty, so the "receiptscanner" folder appears in the 
  // Files app (On My iPhone) immediately.
  if (Platform.isIOS) {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final readme = File('${dir.path}/README.txt');
      if (!await readme.exists()) {
        await readme.writeAsString(
          'Bu klasör receiptscanner uygulaması tarafından Excel dosyalarınızı saklamak için kullanılır.',
          flush: true,
        );
      }
    } catch (e) {
      debugPrint('iOS klasör hazırlama hatası: $e');
    }
  }

  runApp(const ReceiptScannerApp());
}

class ReceiptScannerApp extends StatelessWidget {
  const ReceiptScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fiş Tarayıcı',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.bgDark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ),
      ),
      home: const MainNavScreen(),
    );
  }
}
