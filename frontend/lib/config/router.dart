import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/register_screen.dart';
import '../screens/confirm_email_screen.dart';
import '../screens/otp_auth_screen.dart';
import '../screens/home_shell.dart';
import '../screens/chat_screen.dart';
import '../screens/call_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/confirm-email',
      builder: (context, state) {
        final email = state.uri.queryParameters['email'] ?? '';
        final data = state.extra as Map<String, dynamic>?;
        return ConfirmEmailScreen(
          email: email,
          registrationData: data,
        );
      },
    ),
    GoRoute(
      path: '/otp-auth',
      builder: (context, state) => const OtpAuthScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeShell(),
    ),
    GoRoute(
      path: '/chat/:id',
      builder: (context, state) {
        final chatId = state.pathParameters['id'] ?? '';
        final name = state.uri.queryParameters['name'] ?? 'Chat';
        final otherUserId = state.uri.queryParameters['otherUserId'] ?? '';
        return ChatScreen(
          chatId: chatId,
          chatName: name,
          otherUserId: otherUserId,
        );
      },
    ),
    GoRoute(
      path: '/call',
      builder: (context, state) {
        final name = state.uri.queryParameters['name'] ?? 'User';
        final otherUserId = state.uri.queryParameters['otherUserId'] ?? '';
        final chatId = state.uri.queryParameters['chatId'] ?? '';
        final isVideo = state.uri.queryParameters['isVideo'] == 'true';
        final callId = state.uri.queryParameters['callId'];
        return CallScreen(
          name: name,
          otherUserId: otherUserId,
          chatId: chatId,
          isVideo: isVideo,
          callId: callId,
        );
      },
    ),
  ],
);
