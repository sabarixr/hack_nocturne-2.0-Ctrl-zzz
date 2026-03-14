import 'package:expresto/pages/home.dart';
import 'package:expresto/pages/login.dart';
import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/core/api_client.dart';
import 'package:flutter/material.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiClient.init();

  final prefs = await SharedPreferences.getInstance();
  final hasToken = prefs.getString('auth_token') != null;

  runApp(MyApp(startWithHome: hasToken));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.startWithHome});

  final bool startWithHome;

  @override
  Widget build(BuildContext context) {
    return GraphQLProvider(
      client: ApiClient.client,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: AppColors.background,
          fontFamily: 'sans-serif',
          snackBarTheme: const SnackBarThemeData(
            backgroundColor: AppColors.panel,
            contentTextStyle: TextStyle(color: AppColors.textPrimary),
          ),
        ),
        home: startWithHome ? const HomePage() : const LoginPage(),
      ),
    );
  }
}
