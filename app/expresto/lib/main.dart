import 'package:expresto/pages/home.dart';
import 'package:expresto/core/theme/app_colors.dart';
import 'package:expresto/core/api_client.dart';
import 'package:flutter/material.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ApiClient.init();

  // Quick auto-login/register for demo purposes
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString('auth_token') == null) {
    try {
      final HttpLink httpLink = HttpLink('http://10.113.21.127:8000/graphql');
      final client = GraphQLClient(link: httpLink, cache: GraphQLCache());

      final result = await client
          .mutate(
            MutationOptions(
              document: gql(r'''
                mutation {
                  register(input: {
                    email: "dummy@example.com",
                    password: "password123",
                    name: "Demo User",
                    phone: "+919876543210",
                    age: 25,
                    primaryLanguage: "en"
                  }) {
                    token
                  }
                }
              '''),
            ),
          )
          .timeout(const Duration(seconds: 5));

      if (result.data != null && result.data!['register'] != null) {
        final token = result.data!['register']['token'];
        await prefs.setString('auth_token', token);
        ApiClient.authToken = token;
      } else {
        // Already registered — login instead
        final loginRes = await client
            .mutate(
              MutationOptions(
                document: gql(r'''
                  mutation {
                    login(input: {
                      email: "dummy@example.com",
                      password: "password123"
                    }) {
                      token
                    }
                  }
                '''),
              ),
            )
            .timeout(const Duration(seconds: 5));

        if (loginRes.data != null && loginRes.data!['login'] != null) {
          final token = loginRes.data!['login']['token'];
          await prefs.setString('auth_token', token);
          ApiClient.authToken = token;
        }
      }
    } catch (e) {
      // Network unreachable or timeout — continue without token
      print("Failed to auto-login: $e");
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
        home: const HomePage(),
      ),
    );
  }
}
