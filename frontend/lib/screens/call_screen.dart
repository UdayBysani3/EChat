import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import '../config/theme.dart';
import '../services/app_config.dart';

class CallScreen extends StatefulWidget {
  final String name;
  final String otherUserId;
  final String chatId;
  final bool isVideo;
  final String? callId;

  const CallScreen({
    super.key,
    required this.name,
    required this.otherUserId,
    required this.chatId,
    required this.isVideo,
    this.callId,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  String? _localUserId;
  String? _localUserName;
  bool _isZegoInitialized = false;

  @override
  void initState() {
    super.initState();
    _initZego();
    _connectCall();
  }

  @override
  void dispose() {
    _disconnectCall();
    super.dispose();
  }

  void _connectCall() {
    if (widget.callId != null) {
      Supabase.instance.client
          .from('call_logs')
          .update({'status': 'connected'})
          .eq('id', widget.callId!)
          .then((_) {})
          .catchError((_) {});
    }
  }

  void _disconnectCall() {
    if (widget.callId != null) {
      Supabase.instance.client
          .from('call_logs')
          .update({'status': 'ended'})
          .eq('id', widget.callId!)
          .then((_) {})
          .catchError((_) {});
    }
  }

  Future<void> _initZego() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) context.pop();
      return;
    }

    // Zego requires alphanumeric/underscore userID
    _localUserId = user.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    _localUserName = user.email?.split('@')[0] ?? 'User';

    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('username')
          .eq('id', user.id)
          .maybeSingle();
      if (response != null && response['username'] != null) {
        _localUserName = response['username'] as String;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isZegoInitialized = true;
      });
    }
  }

  String getCallId() {
    if (widget.chatId.isNotEmpty) return widget.chatId;
    final list = [Supabase.instance.client.auth.currentUser?.id ?? '', widget.otherUserId];
    list.sort();
    return list.join('_').replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
  }

  @override
  Widget build(BuildContext context) {
    if (!_isZegoInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            color: ObsidianMintColors.primary,
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: ZegoUIKitPrebuiltCall(
          appID: AppConfig.zegoAppId,
          appSign: AppConfig.zegoAppSign,
          userID: _localUserId!,
          userName: _localUserName!,
          callID: getCallId(),
          config: widget.isVideo
              ? ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
              : ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall(),
        ),
      ),
    );
  }
}
