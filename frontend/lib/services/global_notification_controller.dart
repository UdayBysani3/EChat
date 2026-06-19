import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../config/theme.dart';
import '../config/router.dart';
import 'chat_service.dart';

class GlobalNotificationController {
  final Ref ref;
  GlobalNotificationController(this.ref) {
    _init();
  }

  OverlayEntry? _callOverlayEntry;
  OverlayEntry? _messageOverlayEntry;
  Timer? _messageOverlayTimer;
  AudioPlayer? _ringtonePlayer;
  String? _activeCallId;
  bool _showingDeclinedDialog = false;

  void _init() {
    debugPrint('[GlobalNotificationController] Initializing...');

    // 1. Listen to incoming calls
    ref.listen<AsyncValue<List<Map<String, dynamic>>>>(incomingCallsProvider, (
      previous,
      next,
    ) {
      final calls = next.value ?? [];
      debugPrint(
        '[GlobalNotificationController] Incoming calls check: count=${calls.length}',
      );
      if (calls.isNotEmpty) {
        _showCallOverlay(calls.first);
      } else {
        _dismissCall();
      }
    });

    // 4. Listen to global messages
    ref.listen<AsyncValue<Map<String, dynamic>>>(globalMessagesProvider, (
      previous,
      next,
    ) {
      final message = next.value;
      debugPrint(
        '[GlobalNotificationController] New global message check: message=$message',
      );
      if (message != null) {
        _handleNewIncomingMessage(message);
      }
    });

    // 5. Listen to declined requests for popup notifications
    ref.listen<
      AsyncValue<List<Map<String, dynamic>>>
    >(declinedRequestsProvider, (previous, next) {
      final declined = next.value ?? [];
      debugPrint(
        '[GlobalNotificationController] Declined requests check: count=${declined.length}',
      );
      if (declined.isNotEmpty) {
        _handleDeclinedRequests(declined);
      }
    });
  }

  void _playRingtone() async {
    debugPrint('[GlobalNotificationController] Ringtone disabled (silent call display).');
  }

  void _stopRingtone() {
    try {
      _ringtonePlayer?.stop();
    } catch (_) {}
  }

  void _showCallOverlay(Map<String, dynamic> call) {
    final callId = call['id'] as String;
    if (_activeCallId == callId) return;

    _activeCallId = callId;
    _playRingtone();

    final caller = call['caller'] as Map<String, dynamic>?;
    final callerName =
        caller?['username'] as String? ?? caller?['email'] as String? ?? 'User';
    final callerProfileImage = caller?['profile_image'] as String?;
    final isVideo = call['is_video'] as bool? ?? false;
    final chatId = call['chat_id'] as String;

    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) {
      debugPrint('[GlobalNotificationController] Overlay state is null!');
      return;
    }

    _callOverlayEntry?.remove();
    _callOverlayEntry = OverlayEntry(
      builder: (context) {
        return Material(
          color: Colors.black54,
          child: Center(
            child: AlertDialog(
              backgroundColor: ObsidianMintColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              contentPadding: const EdgeInsets.all(24),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        ...List.generate(3, (index) {
                          return Container(
                                width: 90 + (index * 25),
                                height: 90 + (index * 25),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: ObsidianMintColors.primary.withValues(
                                    alpha: 0.1,
                                  ),
                                ),
                              )
                              .animate(
                                onPlay: (controller) => controller.repeat(),
                              )
                              .scale(
                                begin: const Offset(0.8, 0.8),
                                end: const Offset(1.2, 1.2),
                                duration: 1200.ms,
                                delay: (index * 300).ms,
                                curve: Curves.easeInOut,
                              )
                              .fadeOut(duration: 1200.ms);
                        }),
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: ObsidianMintColors.primaryContainer,
                          backgroundImage:
                              callerProfileImage != null &&
                                  callerProfileImage.isNotEmpty
                              ? CachedNetworkImageProvider(callerProfileImage)
                              : null,
                          child:
                              callerProfileImage == null ||
                                  callerProfileImage.isEmpty
                              ? Text(
                                  callerName.isNotEmpty
                                      ? callerName.substring(0, 1).toUpperCase()
                                      : 'U',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: ObsidianMintColors.primary,
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      callerName,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: ObsidianMintColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isVideo
                          ? 'Incoming Video Call...'
                          : 'Incoming Voice Call...',
                      style: TextStyle(
                        fontSize: 14,
                        color: ObsidianMintColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        FloatingActionButton(
                          heroTag: 'decline_btn_$callId',
                          backgroundColor: ObsidianMintColors.error,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          onPressed: () async {
                            _dismissCall();
                            await ref
                                .read(chatServiceProvider)
                                .updateCallStatus(callId, 'ended');
                          },
                          child: const Icon(Icons.call_end_rounded, size: 28),
                        ),
                        FloatingActionButton(
                          heroTag: 'accept_btn_$callId',
                          backgroundColor: ObsidianMintColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          onPressed: () async {
                            _dismissCall();
                            appRouter.push(
                              '/call?name=${Uri.encodeComponent(callerName)}&otherUserId=${Uri.encodeComponent(caller?['id'] ?? '')}&isVideo=$isVideo&chatId=$chatId&callId=$callId&isIncoming=true',
                            );
                          },
                          child: Icon(
                            isVideo
                                ? Icons.videocam_rounded
                                : Icons.phone_rounded,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_callOverlayEntry!);
    debugPrint('[GlobalNotificationController] Call overlay inserted');
  }

  void _dismissCall() {
    _stopRingtone();
    _callOverlayEntry?.remove();
    _callOverlayEntry = null;
    _activeCallId = null;
    debugPrint('[GlobalNotificationController] Call overlay dismissed');
  }

  void _handleNewIncomingMessage(Map<String, dynamic> message) async {
    final activeChatId = ref.read(activeChatIdProvider);
    if (activeChatId == message['chat_id']) return;

    try {
      final senderProfile = await ref
          .read(chatServiceProvider)
          .getUserProfile(message['sender_id']);
      final senderName =
          senderProfile?['username'] as String? ??
          senderProfile?['email'] as String? ??
          'User';
      final senderAvatar = senderProfile?['profile_image'] as String?;
      final content = message['content'] as String? ?? '';
      final type = message['message_type'] as String? ?? 'text';
      final chatId = message['chat_id'] as String;
      final senderId = message['sender_id'] as String;

      String previewText = content;
      if (type == 'image') {
        previewText = '📷 Sent an image';
      } else if (type == 'audio') {
        previewText = '🎵 Sent a voice note';
      } else if (type == 'file') {
        previewText = '📄 Sent a document';
      } else if (type == 'location') {
        previewText = '📍 Shared a location';
      }

      _showInAppNotificationBanner(
        chatId: chatId,
        senderId: senderId,
        senderName: senderName,
        senderAvatar: senderAvatar,
        previewText: previewText,
      );
    } catch (e) {
      debugPrint('Notification fetch error: $e');
    }
  }

  void _showInAppNotificationBanner({
    required String chatId,
    required String senderId,
    required String senderName,
    required String? senderAvatar,
    required String previewText,
  }) {
    _messageOverlayTimer?.cancel();
    _messageOverlayEntry?.remove();
    _messageOverlayEntry = null;

    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _messageOverlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () {
                _messageOverlayTimer?.cancel();
                _messageOverlayEntry?.remove();
                _messageOverlayEntry = null;
                appRouter.push(
                  '/chat/$chatId?name=${Uri.encodeComponent(senderName)}&otherUserId=$senderId',
                );
              },
              child:
                  Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: ObsidianMintColors.surfaceContainerLowest
                              .withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                          border: Border.all(
                            color: ObsidianMintColors.outlineVariant,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor:
                                  ObsidianMintColors.primaryContainer,
                              backgroundImage:
                                  senderAvatar != null &&
                                      senderAvatar.isNotEmpty
                                  ? CachedNetworkImageProvider(senderAvatar)
                                  : null,
                              child:
                                  senderAvatar == null || senderAvatar.isEmpty
                                  ? Text(
                                      senderName.isNotEmpty
                                          ? senderName[0].toUpperCase()
                                          : 'U',
                                      style: TextStyle(
                                        color: ObsidianMintColors.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    senderName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: ObsidianMintColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    previewText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: ObsidianMintColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: ObsidianMintColors.primary,
                              size: 20,
                            ),
                          ],
                        ),
                      )
                      .animate()
                      .slideY(
                        begin: -0.5,
                        end: 0,
                        duration: 300.ms,
                        curve: Curves.easeOutBack,
                      )
                      .fade(duration: 250.ms),
            ),
          ),
        );
      },
    );

    overlay.insert(_messageOverlayEntry!);

    _messageOverlayTimer = Timer(const Duration(seconds: 4), () {
      _messageOverlayEntry?.remove();
      _messageOverlayEntry = null;
    });
  }

  void _handleDeclinedRequests(List<Map<String, dynamic>> declined) async {
    if (_showingDeclinedDialog) return;
    if (declined.isEmpty) return;

    final request = declined.first;
    final requestId = request['id'] as String;
    final receiver = request['receiver'] as Map<String, dynamic>?;
    final receiverName =
        receiver?['username'] as String? ??
        receiver?['email'] as String? ??
        'User';

    final context = rootNavigatorKey.currentContext;
    if (context == null) return;

    _showingDeclinedDialog = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: ObsidianMintColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: ObsidianMintColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Request Status',
                style: TextStyle(
                  color: ObsidianMintColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            '$receiverName declined your chat request.',
            style: TextStyle(color: ObsidianMintColors.textPrimary),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ObsidianMintColors.primary,
                foregroundColor: ObsidianMintColors.onPrimary,
              ),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                _showingDeclinedDialog = false;
                try {
                  await ref
                      .read(chatServiceProvider)
                      .markDeclineNotified(requestId);
                } catch (e) {
                  debugPrint('Error marking declined request notified: $e');
                }
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void dispose() {
    _stopRingtone();
    _ringtonePlayer?.dispose();
    _messageOverlayTimer?.cancel();
    _messageOverlayEntry?.remove();
    _callOverlayEntry?.remove();
  }
}

final globalNotificationControllerProvider =
    Provider<GlobalNotificationController>((ref) {
      final controller = GlobalNotificationController(ref);
      ref.onDispose(() => controller.dispose());
      return controller;
    });
