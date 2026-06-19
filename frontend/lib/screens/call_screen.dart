import 'dart:async';
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
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.name,
    required this.otherUserId,
    required this.chatId,
    required this.isVideo,
    this.callId,
    this.isIncoming = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  String? _localUserId;
  String? _localUserName;
  bool _isZegoInitialized = false;
  RealtimeChannel? _callStatusChannel;
  bool _isConnected = false;
  bool _isNotAnswering = false;
  Timer? _ringTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _initZego();
    _connectCall();
    _listenToCallStatus();
    if (!widget.isIncoming) {
      _ringTimeoutTimer = Timer(const Duration(seconds: 15), () {
        _handleRingTimeout();
      });
    }
  }

  @override
  void dispose() {
    _ringTimeoutTimer?.cancel();
    _disconnectCall();
    if (_callStatusChannel != null) {
      Supabase.instance.client.removeChannel(_callStatusChannel!);
    }
    super.dispose();
  }

  void _handleRingTimeout() async {
    if (!mounted) return;
    if (_isConnected) return;

    debugPrint('[CallScreen] Call ring timeout reached (15s). Marking as missed.');
    if (widget.callId != null) {
      try {
        await Supabase.instance.client
            .from('call_logs')
            .update({'status': 'missed'})
            .eq('id', widget.callId!);
      } catch (e) {
        debugPrint('[CallScreen] Error updating call status to missed: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isNotAnswering = true;
      });
    }
  }

  void _listenToCallStatus() {
    if (widget.callId != null) {
      _callStatusChannel = Supabase.instance.client
          .channel('call-status-${widget.callId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'call_logs',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: widget.callId,
            ),
            callback: (payload) {
              final newStatus = payload.newRecord['status'] as String?;
              debugPrint('[CallScreen] Call status changed to: $newStatus');
              if (newStatus == 'connected') {
                _isConnected = true;
                _ringTimeoutTimer?.cancel();
              } else if (newStatus == 'ended' || newStatus == 'missed') {
                if (mounted) {
                  if (newStatus == 'missed' && !widget.isIncoming) {
                    setState(() {
                      _isNotAnswering = true;
                    });
                  } else {
                    context.pop();
                  }
                }
              }
            },
          );
      _callStatusChannel!.subscribe();
    }
  }

  void _connectCall() {
    if (widget.callId != null) {
      final newStatus = widget.isIncoming ? 'connected' : 'ringing';
      Supabase.instance.client
          .from('call_logs')
          .update({'status': newStatus})
          .eq('id', widget.callId!)
          .then((_) {})
          .catchError((_) {});
    }
  }

  bool _isDisconnected = false;

  void _disconnectCall() {
    if (_isDisconnected) return;
    _isDisconnected = true;
    if (widget.callId != null && !_isNotAnswering) {
      Supabase.instance.client
          .from('call_logs')
          .update({'status': 'ended'})
          .eq('id', widget.callId!)
          .then((_) {})
          .catchError((_) {});
    }
  }

  Future<void> _updateCallStatusToEnded() async {
    if (_isDisconnected) return;
    _isDisconnected = true;
    if (widget.callId != null && !_isNotAnswering) {
      try {
        debugPrint('[CallScreen] Updating call status to ended.');
        await Supabase.instance.client
            .from('call_logs')
            .update({'status': 'ended'})
            .eq('id', widget.callId!);
        debugPrint('[CallScreen] Call status updated to ended successfully.');
      } catch (e) {
        debugPrint('[CallScreen] Error updating call status to ended: $e');
      }
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
    if (_isNotAnswering) {
      return Scaffold(
        backgroundColor: ObsidianMintColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.phone_missed_rounded,
                color: ObsidianMintColors.error,
                size: 64,
              ),
              const SizedBox(height: 24),
              Text(
                'The user is not answering',
                style: TextStyle(
                  color: ObsidianMintColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ObsidianMintColors.primary,
                  foregroundColor: ObsidianMintColors.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  context.pop();
                },
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    }

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
          events: ZegoUIKitPrebuiltCallEvents(
            onCallEnd: (ZegoCallEndEvent event, VoidCallback defaultAction) async {
              await _updateCallStatusToEnded();
              defaultAction();
            },
          ),
        ),
      ),
    );
  }
}
