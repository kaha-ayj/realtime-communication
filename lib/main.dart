import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'models/app_user.dart';
import 'providers/app_provider.dart';
import 'screens/admin_shell.dart';
import 'screens/cashier_shell.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/menu_service.dart';
import 'services/miomipay_service.dart';
import 'thema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const PosApp());
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<MenuService>(create: (_) => MenuService()),
        Provider<OrderService>(create: (_) => OrderService()),
        Provider<MiomiPayService>(create: (_) => MiomiPayService()),
        ChangeNotifierProxyProvider4<AuthService, MenuService, OrderService,
            MiomiPayService, AppProvider>(
          create: (ctx) => AppProvider(
            authService: ctx.read<AuthService>(),
            menuService: ctx.read<MenuService>(),
            orderService: ctx.read<OrderService>(),
            miomiPayService: ctx.read<MiomiPayService>(),
          ),
          update: (_, auth, menu, order, pay, prev) =>
              prev ??
              AppProvider(
                authService: auth,
                menuService: menu,
                orderService: order,
                miomiPayService: pay,
              ),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'POS Sederhana',
        theme: PosTheme.lightTheme,
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();

    return StreamBuilder<AppUser?>(
      stream: authService.watchCurrentUser(),
      builder: (context, snapshot) {
        // Still loading auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }

        final user = snapshot.data;

        if (user == null) {
          return const LoginScreen();
        }

        // Sync user into provider
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.read<AppProvider>().setCurrentUser(user);
        });

        return switch (user.role) {
          UserRole.admin => const AdminShell(),
          UserRole.kasir => const CashierShell(),
        };
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: PosColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.point_of_sale_rounded, size: 60, color: Colors.white),
            SizedBox(height: 20),
            Text(
              'POS Sederhana',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 20),
            CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}
