import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:uri_content/uri_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/chat_service.dart';
import '../services/supabase_service.dart';
import '../config/theme.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/full_screen_image_view.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String chatName;
  final String otherUserId;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.chatName,
    required this.otherUserId,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;
  bool _isTextEmpty = true;

  // Realtime Broadcast Typing Channel
  RealtimeChannel? _typingChannel;
  bool _otherUserIsTyping = false;
  bool _isCurrentlyTyping = false;
  Timer? _typingTimer;

  // Audio Recording State
  bool _isRecording = false;
  AudioRecorder? _audioRecorder;
  Timer? _recordTimer;
  int _recordDuration = 0;

  bool _isBlockedByMe = false;
  Map<String, dynamic>? _replyMessage;
  final _focusNode = FocusNode();
  final Map<String, GlobalKey> _messageKeys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeChatIdProvider.notifier).state = widget.chatId;
    });
    _markChatAsRead();
    _setupTypingChannel();
    _messageController.addListener(_onTextChanged);
    _audioRecorder = AudioRecorder();
    _checkBlockStatus();
  }

  Future<void> _checkBlockStatus() async {
    try {
      final isBlocked = await ref
          .read(chatServiceProvider)
          .isBlocked(widget.otherUserId);
      if (mounted) {
        setState(() {
          _isBlockedByMe = isBlocked;
        });
      }
    } catch (_) {}
  }

  bool _isCallLogMessage(String content) {
    final parts = content.split('|');
    if (parts.length != 3) return false;
    final status = parts[0];
    return status == 'initiated' ||
        status == 'ringing' ||
        status == 'connected' ||
        status == 'missed' ||
        status == 'ended';
  }

  String _translateCallLogMessage(String content, bool isMe) {
    final parts = content.split('|');
    if (parts.length != 3) return content;
    final status = parts[0];
    final isVideo = parts[1] == 'true';
    final duration = int.tryParse(parts[2]) ?? 0;

    if (status == 'initiated') {
      return isVideo ? 'Outgoing Video Call' : 'Outgoing Voice Call';
    } else if (status == 'missed') {
      if (isMe) {
        return isVideo ? 'Outgoing Video Call' : 'Outgoing Voice Call';
      } else {
        return isVideo ? 'Missed Video Call' : 'Missed Voice Call';
      }
    } else if (status == 'ended') {
      if (duration > 0) {
        final minutes = duration ~/ 60;
        final seconds = duration % 60;
        final durationStr = minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';
        return isVideo ? 'Video Call Ended ($durationStr)' : 'Voice Call Ended ($durationStr)';
      } else {
        if (isMe) {
          return isVideo ? 'Outgoing Video Call' : 'Outgoing Voice Call';
        } else {
          return isVideo ? 'Missed Video Call' : 'Missed Voice Call';
        }
      }
    } else {
      return isVideo ? 'Video Call: $status' : 'Voice Call: $status';
    }
  }

  IconData _getCallLogIcon(String content, bool isMe) {
    final parts = content.split('|');
    if (parts.length != 3) return Icons.phone;
    final status = parts[0];
    final isVideo = parts[1] == 'true';
    final duration = int.tryParse(parts[2]) ?? 0;

    if (status == 'initiated') {
      return isVideo ? Icons.videocam_rounded : Icons.phone_rounded;
    } else if (status == 'missed') {
      if (isMe) {
        return Icons.call_made_rounded;
      } else {
        return isVideo ? Icons.missed_video_call_rounded : Icons.phone_missed_rounded;
      }
    } else if (status == 'ended') {
      if (duration > 0) {
        return isVideo ? Icons.videocam_rounded : Icons.phone_rounded;
      } else {
        if (isMe) {
          return Icons.call_made_rounded;
        } else {
          return isVideo ? Icons.missed_video_call_rounded : Icons.phone_missed_rounded;
        }
      }
    } else {
      return isVideo ? Icons.videocam_rounded : Icons.phone_rounded;
    }
  }

  Color? _getCallLogIconColor(String content, bool isMe) {
    final parts = content.split('|');
    if (parts.length != 3) return null;
    final status = parts[0];
    final duration = int.tryParse(parts[2]) ?? 0;

    if (status == 'missed') {
      if (!isMe) {
        return ObsidianMintColors.error;
      }
    } else if (status == 'ended' && duration == 0) {
      if (!isMe) {
        return ObsidianMintColors.error;
      }
    }
    return isMe ? null : ObsidianMintColors.primary;
  }

  @override
  void dispose() {
    ref.read(activeChatIdProvider.notifier).state = null;
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _recordTimer?.cancel();
    _audioRecorder?.dispose();
    _cleanupTypingChannel();
    super.dispose();
  }

  void _markChatAsRead([List<Map<String, dynamic>>? messages]) {
    final userId = ref.read(supabaseServiceProvider).currentUser?.id;
    if (userId == null) return;

    if (messages != null) {
      final hasUnread = messages.any(
        (m) => m['sender_id'] != userId && m['status'] == 'sent',
      );
      if (!hasUnread) return;
    }

    // Run asynchronously to mark incoming messages as read
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(chatServiceProvider).markMessagesAsRead(widget.chatId);
      } catch (_) {}
    });
  }

  void _setupTypingChannel() {
    final client = Supabase.instance.client;
    final currentUserId = ref.read(supabaseServiceProvider).currentUser?.id;
    if (currentUserId == null) return;

    _typingChannel = client.channel('chat:${widget.chatId}');

    _typingChannel!.onBroadcast(
      event: 'typing',
      callback: (payload) {
        final innerPayload =
            payload['payload'] as Map<String, dynamic>? ?? payload;
        final userId = innerPayload['userId'] as String?;
        final isTyping = innerPayload['isTyping'] as bool? ?? false;

        if (userId != currentUserId && mounted) {
          setState(() {
            _otherUserIsTyping = isTyping;
          });
        }
      },
    );

    _typingChannel!.subscribe();
  }

  void _cleanupTypingChannel() {
    if (_typingChannel != null) {
      final client = Supabase.instance.client;
      client.removeChannel(_typingChannel!);
    }
  }

  void _onTextChanged() {
    final currentUserId = ref.read(supabaseServiceProvider).currentUser?.id;
    if (_typingChannel == null || currentUserId == null) return;

    final hasText = _messageController.text.trim().isNotEmpty;
    if (_isTextEmpty != !hasText) {
      setState(() {
        _isTextEmpty = !hasText;
      });
    }

    if (hasText) {
      if (!_isCurrentlyTyping) {
        _isCurrentlyTyping = true;
        _typingChannel!.sendBroadcastMessage(
          event: 'typing',
          payload: {'userId': currentUserId, 'isTyping': true},
        );
      }

      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 2), () {
        _isCurrentlyTyping = false;
        if (mounted) {
          _typingChannel!.sendBroadcastMessage(
            event: 'typing',
            payload: {'userId': currentUserId, 'isTyping': false},
          );
        }
      });
    } else {
      if (_isCurrentlyTyping) {
        _isCurrentlyTyping = false;
        _typingTimer?.cancel();
        _typingChannel!.sendBroadcastMessage(
          event: 'typing',
          payload: {'userId': currentUserId, 'isTyping': false},
        );
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollToMessage(String messageId) {
    final key = _messageKeys[messageId];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final replyId = _replyMessage?['id']?.toString();
    _messageController.clear();
    setState(() {
      _isSending = true;
      _replyMessage = null;
    });

    try {
      final chatService = ref.read(chatServiceProvider);
      await chatService.sendTextMessage(
        widget.chatId,
        text,
        replyToId: replyId,
      );

      // Stop typing status instantly upon sending message
      if (_isCurrentlyTyping) {
        _isCurrentlyTyping = false;
        _typingTimer?.cancel();
        final currentUserId = ref.read(supabaseServiceProvider).currentUser?.id;
        if (currentUserId != null && _typingChannel != null) {
          _typingChannel!.sendBroadcastMessage(
            event: 'typing',
            payload: {'userId': currentUserId, 'isTyping': false},
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to send: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            backgroundColor: ObsidianMintColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    }
  }

  Future<void> _uploadAndSendMedia(
    Uint8List bytes,
    String fileName,
    String messageType,
  ) async {
    final replyId = _replyMessage?['id']?.toString();
    setState(() {
      _isSending = true;
      _replyMessage = null;
    });
    try {
      final chatService = ref.read(chatServiceProvider);
      // Upload to storage
      final publicUrl = await chatService.uploadBytes(bytes, fileName);
      // Send message
      await chatService.sendMediaMessage(
        widget.chatId,
        publicUrl,
        messageType,
        replyToId: replyId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to upload/send media: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            backgroundColor: ObsidianMintColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 70, // optimized sizing
      );

      if (pickedFile != null) {
        final fileName = pickedFile.name;
        final bytes = await pickedFile.readAsBytes();
        await _uploadAndSendMedia(bytes, fileName, 'image');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: ${e.toString()}'),
            backgroundColor: ObsidianMintColors.error,
          ),
        );
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: kIsWeb,
      );

      if (result != null) {
        final fileName = result.files.single.name;
        Uint8List? fileBytes = result.files.single.bytes;
        if (fileBytes == null && result.files.single.path != null) {
          fileBytes = await File(result.files.single.path!).readAsBytes();
        }

        if (fileBytes != null) {
          await _uploadAndSendMedia(fileBytes, fileName, 'file');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking file: ${e.toString()}'),
            backgroundColor: ObsidianMintColors.error,
          ),
        );
      }
    }
  }

  Future<void> _pickAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        withData: kIsWeb,
      );

      if (result != null) {
        final fileName = result.files.single.name;
        Uint8List? fileBytes = result.files.single.bytes;
        if (fileBytes == null && result.files.single.path != null) {
          fileBytes = await File(result.files.single.path!).readAsBytes();
        }

        if (fileBytes != null) {
          await _uploadAndSendMedia(fileBytes, fileName, 'audio');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking audio file: ${e.toString()}'),
            backgroundColor: ObsidianMintColors.error,
          ),
        );
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      if (_audioRecorder == null) return;

      if (await _audioRecorder!.hasPermission()) {
        String path;
        if (kIsWeb) {
          path = 'voice_note.m4a';
        } else {
          final tempDir = await getTemporaryDirectory();
          path =
              '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        }

        await _audioRecorder!.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );

        setState(() {
          _isRecording = true;
          _recordDuration = 0;
        });

        _recordTimer?.cancel();
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _recordDuration++;
          });
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Microphone permission is required to record voice notes.',
              ),
              backgroundColor: ObsidianMintColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting recording: ${e.toString()}'),
            backgroundColor: ObsidianMintColors.error,
          ),
        );
      }
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    try {
      _recordTimer?.cancel();
      final path = await _audioRecorder?.stop();

      setState(() {
        _isRecording = false;
      });

      if (send && path != null) {
        final fileName =
            'voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
        Uint8List bytes;
        if (kIsWeb) {
          final response = await http.get(Uri.parse(path));
          bytes = response.bodyBytes;
        } else {
          bytes = await File(path).readAsBytes();
        }
        await _uploadAndSendMedia(bytes, fileName, 'audio');

        if (!kIsWeb) {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        }
      } else if (path != null && !kIsWeb) {
        // Delete discarded file
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error stopping recording: ${e.toString()}'),
            backgroundColor: ObsidianMintColors.error,
          ),
        );
      }
    }
  }

  String _formatRecordDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  void _showLocationDialog() {
    final latController = TextEditingController(text: '37.7749');
    final lngController = TextEditingController(text: '-122.4194');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: ObsidianMintColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: ObsidianMintColors.outlineVariant,
              width: 1,
            ),
          ),
          title: Text(
            'Share Location',
            style: TextStyle(
              color: ObsidianMintColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ObsidianMintColors.primary,
                    foregroundColor: ObsidianMintColors.onPrimary,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _shareCurrentLocation();
                  },
                  icon: const Icon(Icons.my_location_rounded),
                  label: const Text('Use Present Location'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'OR PIN LOCATION',
                        style: TextStyle(
                          fontSize: 10,
                          color: ObsidianMintColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Choose a simulated landmark or enter custom coordinates.',
                  style: TextStyle(
                    color: ObsidianMintColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                // Preset options
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildLocationPreset(
                      label: 'SF Headquarter',
                      lat: 37.7749,
                      lng: -122.4194,
                      onSelect: (lat, lng) {
                        latController.text = lat.toString();
                        lngController.text = lng.toString();
                      },
                    ),
                    _buildLocationPreset(
                      label: 'New York',
                      lat: 40.7128,
                      lng: -74.0060,
                      onSelect: (lat, lng) {
                        latController.text = lat.toString();
                        lngController.text = lng.toString();
                      },
                    ),
                    _buildLocationPreset(
                      label: 'Paris',
                      lat: 48.8566,
                      lng: 2.3522,
                      onSelect: (lat, lng) {
                        latController.text = lat.toString();
                        lngController.text = lng.toString();
                      },
                    ),
                    _buildLocationPreset(
                      label: 'Tokyo',
                      lat: 35.6762,
                      lng: 139.6503,
                      onSelect: (lat, lng) {
                        latController.text = lat.toString();
                        lngController.text = lng.toString();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: latController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: TextStyle(color: ObsidianMintColors.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Latitude',
                          labelStyle: TextStyle(
                            color: ObsidianMintColors.textSecondary,
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: ObsidianMintColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: lngController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: TextStyle(color: ObsidianMintColors.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Longitude',
                          labelStyle: TextStyle(
                            color: ObsidianMintColors.textSecondary,
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: ObsidianMintColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: ObsidianMintColors.textSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ObsidianMintColors.primary,
                foregroundColor: ObsidianMintColors.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                final lat = double.tryParse(latController.text) ?? 37.7749;
                final lng = double.tryParse(lngController.text) ?? -122.4194;
                Navigator.pop(context);
                _sendLocation(lat, lng);
              },
              child: const Text('Share'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLocationPreset({
    required String label,
    required double lat,
    required double lng,
    required void Function(double, double) onSelect,
  }) {
    return ActionChip(
      backgroundColor: ObsidianMintColors.surfaceElevated,
      side: BorderSide(color: ObsidianMintColors.outlineVariant),
      label: Text(
        label,
        style: TextStyle(color: ObsidianMintColors.textPrimary, fontSize: 11),
      ),
      onPressed: () => onSelect(lat, lng),
    );
  }

  Future<void> _sendLocation(double lat, double lng) async {
    final replyId = _replyMessage?['id']?.toString();
    setState(() {
      _isSending = true;
      _replyMessage = null;
    });
    try {
      final chatService = ref.read(chatServiceProvider);
      await chatService.sendLocationMessage(
        widget.chatId,
        lat,
        lng,
        replyToId: replyId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to share location: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            backgroundColor: ObsidianMintColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    }
  }

  Future<void> _shareCurrentLocation() async {
    setState(() => _isSending = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception(
          'Location services are disabled. Please enable them in your settings.',
        );
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      await _sendLocation(position.latitude, position.longitude);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error sharing location: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            backgroundColor: ObsidianMintColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: ObsidianMintColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: ObsidianMintColors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Share Attachment',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: ObsidianMintColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    _buildAttachmentItem(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      color: ObsidianMintColors.primary,
                      onTap: () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.camera);
                      },
                    ),
                    _buildAttachmentItem(
                      icon: Icons.image_rounded,
                      label: 'Gallery',
                      color: Colors.blueAccent,
                      onTap: () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.gallery);
                      },
                    ),
                    _buildAttachmentItem(
                      icon: Icons.description_rounded,
                      label: 'Document',
                      color: Colors.amber,
                      onTap: () {
                        Navigator.pop(context);
                        _pickFile();
                      },
                    ),
                    _buildAttachmentItem(
                      icon: Icons.location_on_rounded,
                      label: 'Location',
                      color: Colors.teal,
                      onTap: () {
                        Navigator.pop(context);
                        _showLocationDialog();
                      },
                    ),
                    _buildAttachmentItem(
                      icon: Icons.audiotrack_rounded,
                      label: 'Audio File',
                      color: Colors.purple,
                      onTap: () {
                        Navigator.pop(context);
                        _pickAudioFile();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttachmentItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: ObsidianMintColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String? timestampStr) {
    if (timestampStr == null) return '';
    try {
      final dateTime = DateTime.parse(timestampStr).toLocal();
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (e) {
      return '';
    }
  }

  Widget _buildReactionsDisplay(Map<String, dynamic>? reactions) {
    if (reactions == null || reactions.isEmpty) return const SizedBox.shrink();

    // Group reactions
    final Map<String, int> emojiCounts = {};
    reactions.forEach((userId, emoji) {
      if (emoji is String && emoji.isNotEmpty) {
        emojiCounts[emoji] = (emojiCounts[emoji] ?? 0) + 1;
      }
    });

    if (emojiCounts.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            spreadRadius: 0.5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emojiCounts.keys.join(''), style: const TextStyle(fontSize: 12)),
          if (reactions.length > 1) ...[
            const SizedBox(width: 4),
            Text(
              '${reactions.length}',
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showMessageOptions(
    BuildContext context,
    Map<String, dynamic> message,
    bool isMe,
  ) {
    final messageId = message['id'].toString();
    final reactions = message['reactions'] as Map<String, dynamic>? ?? {};
    bool showAllReactions = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ObsidianMintColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 20,
                      horizontal: 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle
                        Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: ObsidianMintColors.outlineVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        // Reactions row
                        Text(
                          'React to Message',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: ObsidianMintColors.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ...['👍', '❤️', '😂', '😮', '😢', '🙏'].map((
                              emoji,
                            ) {
                              final isSelected =
                                  reactions[ref
                                      .read(supabaseServiceProvider)
                                      .currentUser
                                      ?.id] ==
                                  emoji;
                              return InkWell(
                                onTap: () {
                                  Navigator.pop(context);
                                  ref
                                      .read(chatServiceProvider)
                                      .reactToMessage(
                                        messageId,
                                        emoji,
                                        reactions,
                                      );
                                },
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? ObsidianMintColors.primary.withValues(
                                            alpha: 0.2,
                                          )
                                        : Colors.transparent,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? ObsidianMintColors.primary
                                          : Colors.transparent,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 28),
                                  ),
                                ),
                              );
                            }),
                            // Plus button
                            InkWell(
                              onTap: () {
                                setState(() {
                                  showAllReactions = !showAllReactions;
                                });
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: showAllReactions
                                      ? ObsidianMintColors.primary.withValues(
                                          alpha: 0.2,
                                        )
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: showAllReactions
                                        ? ObsidianMintColors.primary
                                        : Colors.transparent,
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  Icons.add_circle_outline_rounded,
                                  size: 28,
                                  color: ObsidianMintColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (showAllReactions) ...[
                          const SizedBox(height: 16),
                          Text(
                            'More Reactions',
                            style: TextStyle(
                              fontSize: 12,
                              color: ObsidianMintColors.textSecondary
                                  .withValues(alpha: 0.7),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 160,
                            child: GridView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 7,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                  ),
                              itemCount: const [
                                '🔥',
                                '👏',
                                '🎉',
                                '✨',
                                '😍',
                                '😎',
                                '😊',
                                '🤔',
                                '🥳',
                                '😭',
                                '🥺',
                                '😡',
                                '😴',
                                '🙄',
                                '🤤',
                                '😋',
                                '😜',
                                '🤩',
                                '💩',
                                '🤡',
                                '👻',
                                '💀',
                                '👽',
                                '👾',
                                '💖',
                                '💗',
                                '💓',
                                '💙',
                                '💚',
                                '💛',
                                '💜',
                                '🖤',
                                '🤍',
                                '🤎',
                                '💯',
                                '⭐',
                                '🌟',
                                '💥',
                                '💫',
                                '💦',
                                '💨',
                                '💤',
                                '👋',
                                '👌',
                                '✌️',
                                '🤞',
                                '🔑',
                                '🎈',
                                '🎁',
                                '🎂',
                                '🍷',
                                '🍺',
                                '☕',
                                '🍕',
                                '🍔',
                                '🍟',
                                '🍩',
                                '🍪',
                                '🍫',
                                '🍿',
                                '🌍',
                                '🌋',
                                '🐾',
                                '🐶',
                                '🐱',
                                '🐭',
                                '🐹',
                                '🐰',
                                '🦊',
                                '🐻',
                                '🐼',
                                '🐨',
                                '🐯',
                                '🦁',
                                '🐮',
                                '🐷',
                                '🐸',
                                '🐵',
                                '🐔',
                                '🐧',
                                '🐦',
                                '🦆',
                                '🦅',
                                '🦉',
                                '🦇',
                                '🐝',
                                '🦄',
                                '🍎',
                                '🍌',
                                '🍒',
                                '🍓',
                                '🍀',
                                '🚀',
                                '🚗',
                                '🌈',
                                '🌅',
                                '💡',
                                '🎵',
                                '🎮',
                                '📱',
                              ].length,
                              itemBuilder: (context, index) {
                                final popularEmojis = const [
                                  '🔥',
                                  '👏',
                                  '🎉',
                                  '✨',
                                  '😍',
                                  '😎',
                                  '😊',
                                  '🤔',
                                  '🥳',
                                  '😭',
                                  '🥺',
                                  '😡',
                                  '😴',
                                  '🙄',
                                  '🤤',
                                  '😋',
                                  '😜',
                                  '🤩',
                                  '💩',
                                  '🤡',
                                  '👻',
                                  '💀',
                                  '👽',
                                  '👾',
                                  '💖',
                                  '💗',
                                  '💓',
                                  '💙',
                                  '💚',
                                  '💛',
                                  '💜',
                                  '🖤',
                                  '🤍',
                                  '🤎',
                                  '💯',
                                  '⭐',
                                  '🌟',
                                  '💥',
                                  '💫',
                                  '💦',
                                  '💨',
                                  '💤',
                                  '👋',
                                  '👌',
                                  '✌️',
                                  '🤞',
                                  '🔑',
                                  '🎈',
                                  '🎁',
                                  '🎂',
                                  '🍷',
                                  '🍺',
                                  '☕',
                                  '🍕',
                                  '🍔',
                                  '🍟',
                                  '🍩',
                                  '🍪',
                                  '🍫',
                                  '🍿',
                                  '🌍',
                                  '🌋',
                                  '🐾',
                                  '🐶',
                                  '🐱',
                                  '🐭',
                                  '🐹',
                                  '🐰',
                                  '🦊',
                                  '🐻',
                                  '🐼',
                                  '🐨',
                                  '🐯',
                                  '🦁',
                                  '🐮',
                                  '🐷',
                                  '🐸',
                                  '🐵',
                                  '🐔',
                                  '🐧',
                                  '🐦',
                                  '🦆',
                                  '🦅',
                                  '🦉',
                                  '🦇',
                                  '🐝',
                                  '🦄',
                                  '🍎',
                                  '🍌',
                                  '🍒',
                                  '🍓',
                                  '🍀',
                                  '🚀',
                                  '🚗',
                                  '🌈',
                                  '🌅',
                                  '💡',
                                  '🎵',
                                  '🎮',
                                  '📱',
                                ];
                                final emoji = popularEmojis[index];
                                final isSelected =
                                    reactions[ref
                                        .read(supabaseServiceProvider)
                                        .currentUser
                                        ?.id] ==
                                    emoji;
                                return InkWell(
                                  onTap: () {
                                    Navigator.pop(context);
                                    ref
                                        .read(chatServiceProvider)
                                        .reactToMessage(
                                          messageId,
                                          emoji,
                                          reactions,
                                        );
                                  },
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? ObsidianMintColors.primary
                                                .withValues(alpha: 0.2)
                                          : Colors.transparent,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected
                                            ? ObsidianMintColors.primary
                                            : Colors.transparent,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Text(
                                      emoji,
                                      style: const TextStyle(fontSize: 22),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                        Divider(
                          height: 24,
                          color: ObsidianMintColors.outlineVariant,
                        ),
                        // Actions list
                        if (isMe) ...[
                          ListTile(
                            leading: Icon(
                              Icons.delete_outline_rounded,
                              color: ObsidianMintColors.error,
                            ),
                            title: Text(
                              'Delete Message',
                              style: TextStyle(
                                color: ObsidianMintColors.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _confirmDeleteMessage(messageId);
                            },
                          ),
                        ],
                        ListTile(
                          leading: Icon(
                            Icons.copy_rounded,
                            color: ObsidianMintColors.textPrimary,
                          ),
                          title: Text(
                            'Copy Text',
                            style: TextStyle(
                              color: ObsidianMintColors.textPrimary,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            final content = message['content'] as String? ?? '';
                            Clipboard.setData(ClipboardData(text: content));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteMessage(String messageId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: ObsidianMintColors.surface,
          title: Text(
            'Delete Message',
            style: TextStyle(color: ObsidianMintColors.textPrimary),
          ),
          content: Text(
            'Are you sure you want to delete this message? This action cannot be undone.',
            style: TextStyle(color: ObsidianMintColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: ObsidianMintColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);
                try {
                  await ref.read(chatServiceProvider).deleteMessage(messageId);
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete: ${e.toString()}'),
                      backgroundColor: ObsidianMintColors.error,
                    ),
                  );
                }
              },
              child: Text(
                'Delete',
                style: TextStyle(
                  color: ObsidianMintColors.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showOtherUserProfileDialog() {
    final otherUser = ref
        .read(otherUserProfileProvider(widget.otherUserId))
        .value;
    final name = otherUser?['username'] as String? ?? widget.chatName;
    final email = otherUser?['email'] as String? ?? 'No email shared';
    final bio = otherUser?['bio'] as String? ?? 'No bio yet';
    final profileImageUrl = otherUser?['profile_image'] as String?;
    final status = otherUser?['status'] as String? ?? 'offline';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: ObsidianMintColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => FullScreenImageView(
                            imageUrl: profileImageUrl,
                            heroTag: 'other_user_profile_dialog_pic',
                          ),
                        ),
                      );
                    }
                  },
                  child: Hero(
                    tag: 'other_user_profile_dialog_pic',
                    child: CircleAvatar(
                      radius: 46,
                      backgroundColor: ObsidianMintColors.primaryContainer,
                      backgroundImage:
                          profileImageUrl != null && profileImageUrl.isNotEmpty
                          ? CachedNetworkImageProvider(profileImageUrl)
                          : null,
                      child: profileImageUrl == null || profileImageUrl.isEmpty
                          ? Text(
                              name.isNotEmpty
                                  ? name.substring(0, 1).toUpperCase()
                                  : 'U',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: ObsidianMintColors.primary,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: ObsidianMintColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: status == 'online'
                            ? ObsidianMintColors.primary
                            : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status.isNotEmpty
                          ? status[0].toUpperCase() + status.substring(1)
                          : 'Offline',
                      style: TextStyle(
                        fontSize: 12,
                        color: ObsidianMintColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: ObsidianMintColors.outlineVariant),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Email Address',
                    style: TextStyle(
                      fontSize: 11,
                      color: ObsidianMintColors.outline,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    email,
                    style: TextStyle(
                      fontSize: 14,
                      color: ObsidianMintColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Bio',
                    style: TextStyle(
                      fontSize: 11,
                      color: ObsidianMintColors.outline,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    bio,
                    style: TextStyle(
                      fontSize: 14,
                      color: ObsidianMintColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: TextStyle(
                      color: ObsidianMintColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleBlockUser() async {
    final chatService = ref.read(chatServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final isBlocked = await chatService.isBlocked(widget.otherUserId);
      if (isBlocked) {
        await chatService.unblockUser(widget.otherUserId);
        if (mounted) {
          setState(() {
            _isBlockedByMe = false;
          });
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Unblocked ${widget.chatName}',
              style: TextStyle(color: ObsidianMintColors.onPrimaryContainer),
            ),
            backgroundColor: ObsidianMintColors.primaryContainer,
          ),
        );
      } else {
        await chatService.blockUser(widget.otherUserId);
        if (mounted) {
          setState(() {
            _isBlockedByMe = true;
          });
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text('Blocked ${widget.chatName}'),
            backgroundColor: ObsidianMintColors.error,
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: ObsidianMintColors.error,
        ),
      );
    }
  }

  Future<void> _clearChatMessages() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: ObsidianMintColors.surface,
          title: Text(
            'Clear My Messages',
            style: TextStyle(color: ObsidianMintColors.textPrimary),
          ),
          content: Text(
            'Are you sure you want to delete all messages you sent in this chat? This cannot be undone.',
            style: TextStyle(color: ObsidianMintColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: ObsidianMintColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'Clear',
                style: TextStyle(
                  color: ObsidianMintColors.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final chatService = ref.read(chatServiceProvider);
      try {
        await chatService.clearMyMessages(widget.chatId);

        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Cleared your messages from this chat.',
              style: TextStyle(color: ObsidianMintColors.onPrimaryContainer),
            ),
            backgroundColor: ObsidianMintColors.primaryContainer,
          ),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to clear: $e'),
            backgroundColor: ObsidianMintColors.error,
          ),
        );
      }
    }
  }

  Widget _buildMessageContent(Map<String, dynamic> message, bool isMe) {
    final type = message['message_type'] as String? ?? 'text';
    final content = message['content'] as String? ?? '';

    switch (type) {
      case 'image':
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => FullScreenImageView(
                  imageUrl: content,
                  heroTag: message['id'].toString(),
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Hero(
              tag: message['id'].toString(),
              child: CachedNetworkImage(
                imageUrl: content,
                width: 200,
                height: 200,
                fit: BoxFit.cover,
                placeholder: (context, url) => SizedBox(
                  width: 200,
                  height: 200,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: ObsidianMintColors.primary,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  width: 200,
                  height: 200,
                  color: ObsidianMintColors.surfaceElevated,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.broken_image_rounded,
                        color: ObsidianMintColors.error,
                        size: 40,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Image broken',
                        style: TextStyle(
                          color: ObsidianMintColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

      case 'audio':
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: AudioPlayerWidget(audioUrl: content, isMe: isMe),
        );

      case 'file':
        final fileName = Uri.parse(content).pathSegments.isNotEmpty
            ? Uri.parse(content).pathSegments.last
            : 'document.bin';
        final displayFileName =
            fileName.contains('_') &&
                fileName.indexOf('_') < fileName.length - 1
            ? fileName.substring(fileName.indexOf('_') + 1)
            : fileName;

        return InkWell(
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              final uri = Uri.parse(content);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (e) {
              debugPrint('[ChatScreen] Error opening attachment: $e');
              try {
                final uri = Uri.parse(content);
                await launchUrl(uri, mode: LaunchMode.platformDefault);
              } catch (err) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Could not open attachment: $err'),
                    backgroundColor: ObsidianMintColors.error,
                  ),
                );
              }
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isMe
                  ? ObsidianMintColors.onPrimary.withValues(alpha: 0.15)
                  : ObsidianMintColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isMe
                    ? ObsidianMintColors.onPrimary.withValues(alpha: 0.3)
                    : ObsidianMintColors.outlineVariant,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.insert_drive_file_rounded,
                  color: isMe
                      ? ObsidianMintColors.onPrimary
                      : ObsidianMintColors.primary,
                  size: 32,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayFileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isMe
                              ? ObsidianMintColors.onPrimary
                              : ObsidianMintColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Open attachment',
                        style: TextStyle(
                          fontSize: 10,
                          color: isMe
                              ? ObsidianMintColors.onPrimary.withValues(
                                  alpha: 0.7,
                                )
                              : ObsidianMintColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.open_in_new_rounded,
                  color: isMe
                      ? ObsidianMintColors.onPrimary.withValues(alpha: 0.6)
                      : ObsidianMintColors.textSecondary,
                  size: 16,
                ),
              ],
            ),
          ),
        );

      case 'location':
        final coords = content.split(',');
        double lat = 37.7749;
        double lng = -122.4194;
        if (coords.length == 2) {
          lat = double.tryParse(coords[0]) ?? 37.7749;
          lng = double.tryParse(coords[1]) ?? -122.4194;
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            bool launched = false;
            try {
              if (Platform.isAndroid) {
                final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
                launched = await launchUrl(
                  geoUri,
                  mode: LaunchMode.externalApplication,
                );
              } else if (Platform.isIOS) {
                final appleUri = Uri.parse('maps://?q=$lat,$lng');
                launched = await launchUrl(
                  appleUri,
                  mode: LaunchMode.externalApplication,
                );
                if (!launched) {
                  final appleMapsWebUri = Uri.parse(
                    'http://maps.apple.com/?q=$lat,$lng',
                  );
                  launched = await launchUrl(
                    appleMapsWebUri,
                    mode: LaunchMode.externalApplication,
                  );
                }
              }
            } catch (_) {}

            if (!launched) {
              final webUri = Uri.parse(
                'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
              );
              try {
                await launchUrl(webUri, mode: LaunchMode.externalApplication);
              } catch (_) {}
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 220,
                  height: 140,
                  child: IgnorePointer(
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: LatLng(lat, lng),
                        initialZoom: 14,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.none,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.echat',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(lat, lng),
                              width: 36,
                              height: 36,
                              child: Icon(
                                Icons.location_on_rounded,
                                color: ObsidianMintColors.error,
                                size: 36,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      color: isMe
                          ? ObsidianMintColors.onPrimary
                          : ObsidianMintColors.primary,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Shared Location (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})',
                      style: TextStyle(
                        fontSize: 11,
                        color: isMe
                            ? ObsidianMintColors.onPrimary
                            : ObsidianMintColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

      case 'text':
      default:
        if (_isCallLogMessage(content)) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getCallLogIcon(content, isMe),
                size: 16,
                color: _getCallLogIconColor(content, isMe) ?? (isMe ? ObsidianMintColors.onPrimary : ObsidianMintColors.primary),
              ),
              const SizedBox(width: 6),
              Text(
                _translateCallLogMessage(content, isMe),
                style: TextStyle(
                  fontSize: 15,
                  color: isMe
                      ? ObsidianMintColors.onPrimary
                      : ObsidianMintColors.textPrimary,
                ),
              ),
            ],
          );
        }
        return Text(
          content,
          style: TextStyle(
            fontSize: 15,
            color: isMe
                ? ObsidianMintColors.onPrimary
                : ObsidianMintColors.textPrimary,
          ),
        );
    }
  }

  void _onReplyToMessage(Map<String, dynamic> message) {
    setState(() {
      _replyMessage = message;
    });
    _focusNode.requestFocus();
  }

  Widget _buildReplyBubbleHeader({
    required Map<String, dynamic> originalMessage,
    required bool isMe,
    required String otherUserName,
    required String? currentUserId,
  }) {
    final origSenderId = originalMessage['sender_id'];
    final origIsMe = origSenderId == currentUserId;
    final senderName = origIsMe ? 'You' : otherUserName;
    final type = originalMessage['message_type'] as String? ?? 'text';
    final content = originalMessage['content'] as String? ?? '';

    String previewText = '';
    IconData? previewIcon;

    switch (type) {
      case 'image':
        previewText = 'Image';
        previewIcon = Icons.image_rounded;
        break;
      case 'audio':
        previewText = 'Voice note';
        previewIcon = Icons.audiotrack_rounded;
        break;
      case 'file':
        previewText = 'Document';
        previewIcon = Icons.insert_drive_file_rounded;
        break;
      case 'location':
        previewText = 'Location';
        previewIcon = Icons.location_on_rounded;
        break;
      case 'text':
      default:
        previewText = content;
        break;
    }

    final accentColor = isMe
        ? ObsidianMintColors.onPrimary
        : ObsidianMintColors.primary;

    final textColor = isMe
        ? ObsidianMintColors.onPrimary.withValues(alpha: 0.8)
        : ObsidianMintColors.textPrimary.withValues(alpha: 0.8);

    final titleColor = isMe
        ? ObsidianMintColors.onPrimary
        : ObsidianMintColors.primary;

    return GestureDetector(
      onTap: () => _scrollToMessage(originalMessage['id'].toString()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isMe
              ? ObsidianMintColors.onPrimary.withValues(alpha: 0.15)
              : ObsidianMintColors.outlineVariant.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      senderName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (previewIcon != null) ...[
                          Icon(previewIcon, size: 12, color: textColor),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            previewText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: textColor),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReplyPreviewBar(String otherUserName) {
    if (_replyMessage == null) return const SizedBox.shrink();

    final origSenderId = _replyMessage!['sender_id'];
    final currentUserId = ref.read(supabaseServiceProvider).currentUser?.id;
    final origIsMe = origSenderId == currentUserId;
    final senderName = origIsMe ? 'You' : otherUserName;
    final type = _replyMessage!['message_type'] as String? ?? 'text';
    final content = _replyMessage!['content'] as String? ?? '';

    String previewText = '';
    IconData? previewIcon;

    switch (type) {
      case 'image':
        previewText = 'Image';
        previewIcon = Icons.image_rounded;
        break;
      case 'audio':
        previewText = 'Voice note';
        previewIcon = Icons.audiotrack_rounded;
        break;
      case 'file':
        previewText = 'Document';
        previewIcon = Icons.insert_drive_file_rounded;
        break;
      case 'location':
        previewText = 'Location';
        previewIcon = Icons.location_on_rounded;
        break;
      case 'text':
      default:
        previewText = content;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: ObsidianMintColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ObsidianMintColors.outlineVariant,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: ObsidianMintColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to $senderName',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: ObsidianMintColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (previewIcon != null) ...[
                      Icon(
                        previewIcon,
                        size: 12,
                        color: ObsidianMintColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        previewText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: ObsidianMintColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close_rounded,
              size: 20,
              color: ObsidianMintColors.textSecondary,
            ),
            onPressed: () {
              setState(() {
                _replyMessage = null;
              });
            },
          ),
        ],
      ),
    ).animate().fade(duration: 150.ms).slideY(begin: 0.2, end: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(supabaseServiceProvider).currentUser?.id;
    final messagesAsyncValue = ref.watch(
      chatMessagesStreamProvider(widget.chatId),
    );

    // Watch other user's profile to get avatar, name, and status reactively
    final otherUserAsync = ref.watch(
      otherUserProfileProvider(widget.otherUserId),
    );
    final otherUser = otherUserAsync.value;

    final otherUserStatus = otherUser?['status'] as String? ?? 'offline';
    final statusText = _otherUserIsTyping
        ? 'typing...'
        : (otherUserStatus.isNotEmpty
              ? otherUserStatus[0].toUpperCase() + otherUserStatus.substring(1)
              : 'Offline');

    final displayName = otherUser?['username'] as String? ?? widget.chatName;
    final profileImageUrl = otherUser?['profile_image'] as String?;

    // Scroll to bottom and mark messages read when new ones arrive
    ref.listen(chatMessagesStreamProvider(widget.chatId), (previous, next) {
      if (next.hasValue) {
        _markChatAsRead(next.value ?? []);
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _showOtherUserProfileDialog,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: ObsidianMintColors.surface,
                backgroundImage:
                    profileImageUrl != null && profileImageUrl.isNotEmpty
                    ? CachedNetworkImageProvider(profileImageUrl)
                    : null,
                child: profileImageUrl == null || profileImageUrl.isEmpty
                    ? Text(
                        displayName.isNotEmpty
                            ? displayName.substring(0, 1).toUpperCase()
                            : 'C',
                        style: TextStyle(
                          color: ObsidianMintColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11,
                        color: _otherUserIsTyping
                            ? ObsidianMintColors.primary
                            : ObsidianMintColors.primary.withValues(alpha: 0.7),
                        fontWeight: _otherUserIsTyping
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_rounded),
            onPressed: () async {
              final router = GoRouter.of(context);
              final messenger = ScaffoldMessenger.of(context);
              try {
                final callId = await ref
                    .read(chatServiceProvider)
                    .logCall(
                      receiverId: widget.otherUserId,
                      chatId: widget.chatId,
                      isVideo: false,
                    );
                router.push(
                  '/call?name=${Uri.encodeComponent(displayName)}&otherUserId=${Uri.encodeComponent(widget.otherUserId)}&isVideo=false&chatId=${widget.chatId}&callId=$callId',
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Failed to initiate call: $e')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam_rounded),
            onPressed: () async {
              final router = GoRouter.of(context);
              final messenger = ScaffoldMessenger.of(context);
              try {
                final callId = await ref
                    .read(chatServiceProvider)
                    .logCall(
                      receiverId: widget.otherUserId,
                      chatId: widget.chatId,
                      isVideo: true,
                    );
                router.push(
                  '/call?name=${Uri.encodeComponent(displayName)}&otherUserId=${Uri.encodeComponent(widget.otherUserId)}&isVideo=true&chatId=${widget.chatId}&callId=$callId',
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Failed to initiate call: $e')),
                );
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            color: ObsidianMintColors.surface,
            onSelected: (value) async {
              switch (value) {
                case 'view_profile':
                  _showOtherUserProfileDialog();
                  break;
                case 'block':
                  await _toggleBlockUser();
                  break;
                case 'clear':
                  await _clearChatMessages();
                  break;
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem<String>(
                  value: 'view_profile',
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        color: ObsidianMintColors.textPrimary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'View Profile',
                        style: TextStyle(color: ObsidianMintColors.textPrimary),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(
                        _isBlockedByMe
                            ? Icons.check_circle_outline_rounded
                            : Icons.block_rounded,
                        color: _isBlockedByMe
                            ? ObsidianMintColors.primary
                            : ObsidianMintColors.error,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isBlockedByMe ? 'Unblock' : 'Block',
                        style: TextStyle(
                          color: _isBlockedByMe
                              ? ObsidianMintColors.primary
                              : ObsidianMintColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_sweep_outlined,
                        color: ObsidianMintColors.textPrimary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Clear My Messages',
                        style: TextStyle(color: ObsidianMintColors.textPrimary),
                      ),
                    ],
                  ),
                ),
              ];
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(color: ObsidianMintColors.background),
        child: Column(
          children: [
            // Messages List
            Expanded(
              child: messagesAsyncValue.when(
                data: (messages) {
                  if (messages.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 48,
                            color: ObsidianMintColors.outlineVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No messages here yet.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: ObsidianMintColors.textSecondary,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Say hello to start the conversation!',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: ObsidianMintColors.outline),
                          ),
                        ],
                      ).animate().fade(duration: 300.ms),
                    );
                  }

                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _scrollToBottom(),
                  );

                  return ListView.builder(
                    controller: _scrollController,
                    cacheExtent: 5000.0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMe = message['sender_id'] == currentUserId;
                      final time = _formatTime(message['created_at']);
                      final status = message['status'] as String? ?? 'sent';
                      final messageType =
                          message['message_type'] as String? ?? 'text';
                      final reactions =
                          message['reactions'] as Map<String, dynamic>? ?? {};
                      final hasReactions = reactions.isNotEmpty;

                      Map<String, dynamic>? originalMessage;
                      if (message['reply_to_id'] != null) {
                        try {
                          originalMessage = messages.firstWhere(
                            (m) => m['id'] == message['reply_to_id'],
                            orElse: () => <String, dynamic>{},
                          );
                          if (originalMessage.isEmpty) {
                            originalMessage = null;
                          }
                        } catch (_) {
                          originalMessage = null;
                        }
                      }

                      final messageId = message['id'].toString();
                      final messageKey = _messageKeys.putIfAbsent(messageId, () => GlobalKey());

                      return Padding(
                        key: messageKey,
                        padding: EdgeInsets.only(bottom: hasReactions ? 14 : 4),
                        child: Align(
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              SwipeToReply(
                                onReply: () => _onReplyToMessage(message),
                                child: GestureDetector(
                                  onLongPress: () => _showMessageOptions(
                                    context,
                                    message,
                                    isMe,
                                  ),
                                  child: Container(
                                    constraints: BoxConstraints(
                                      minWidth: hasReactions ? 80.0 : 0.0,
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                          0.75,
                                    ),
                                    padding:
                                        messageType == 'image' ||
                                            messageType == 'location'
                                        ? EdgeInsets.only(
                                            left: 4,
                                            right: 4,
                                            top: 4,
                                            bottom: hasReactions ? 18 : 4,
                                          )
                                        : EdgeInsets.only(
                                            left: 10,
                                            right: 10,
                                            top: 6,
                                            bottom: hasReactions ? 18 : 4,
                                          ),
                                    decoration: BoxDecoration(
                                      color: isMe
                                          ? ObsidianMintColors.primary
                                          : ObsidianMintColors.surface,
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(12),
                                        topRight: const Radius.circular(12),
                                        bottomLeft: Radius.circular(
                                          isMe ? 12 : 0,
                                        ),
                                        bottomRight: Radius.circular(
                                          isMe ? 0 : 12,
                                        ),
                                      ),
                                      border: isMe
                                          ? null
                                          : Border.all(
                                              color: ObsidianMintColors
                                                  .outlineVariant,
                                              width: 0.5,
                                            ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (originalMessage != null)
                                          _buildReplyBubbleHeader(
                                            originalMessage: originalMessage,
                                            isMe: isMe,
                                            otherUserName: displayName,
                                            currentUserId: currentUserId,
                                          ),
                                        if (messageType == 'text' || messageType == 'call' || _isCallLogMessage(message['content'] ?? ''))
                                          CompactTextMessage(
                                            content: _isCallLogMessage(message['content'] ?? '')
                                                ? _translateCallLogMessage(message['content'] ?? '', isMe)
                                                : message['content'] as String? ?? '',
                                            time: time,
                                            isMe: isMe,
                                            status: status,
                                            isCallLog: _isCallLogMessage(message['content'] ?? ''),
                                            callIcon: _isCallLogMessage(message['content'] ?? '')
                                                ? _getCallLogIcon(message['content'] ?? '', isMe)
                                                : null,
                                            callIconColor: _isCallLogMessage(message['content'] ?? '')
                                                ? _getCallLogIconColor(message['content'] ?? '', isMe)
                                                : null,
                                            textStyle: TextStyle(
                                              fontSize: 15,
                                              color: isMe
                                                  ? ObsidianMintColors.onPrimary
                                                  : ObsidianMintColors
                                                        .textPrimary,
                                            ),
                                            timeStyle: TextStyle(
                                              fontSize: 9,
                                              color: isMe
                                                  ? ObsidianMintColors.onPrimary
                                                        .withValues(alpha: 0.6)
                                                  : ObsidianMintColors
                                                        .textSecondary,
                                            ),
                                          )
                                        else
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _buildMessageContent(
                                                message,
                                                isMe,
                                              ),
                                              const SizedBox(height: 2),
                                              Padding(
                                                padding:
                                                    messageType == 'image' ||
                                                        messageType ==
                                                            'location'
                                                    ? const EdgeInsets.symmetric(
                                                        horizontal: 4,
                                                      )
                                                    : EdgeInsets.zero,
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      time,
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        color: isMe
                                                            ? ObsidianMintColors
                                                                  .onPrimary
                                                                  .withValues(
                                                                    alpha: 0.6,
                                                                  )
                                                            : ObsidianMintColors
                                                                  .textSecondary,
                                                      ),
                                                    ),
                                                    if (isMe) ...[
                                                      const SizedBox(width: 3),
                                                      Icon(
                                                        status == 'read'
                                                            ? Icons
                                                                  .done_all_rounded
                                                            : Icons
                                                                  .done_rounded,
                                                        size: 12,
                                                        color: status == 'read'
                                                            ? ObsidianMintColors
                                                                  .onPrimary
                                                            : ObsidianMintColors
                                                                  .onPrimary
                                                                  .withValues(
                                                                    alpha: 0.5,
                                                                  ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (hasReactions)
                                Positioned(
                                  bottom: -8,
                                  left: isMe ? null : 12,
                                  right: isMe ? 12 : null,
                                  child: _buildReactionsDisplay(reactions),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => Center(
                  child: CircularProgressIndicator(
                    color: ObsidianMintColors.primary,
                  ),
                ),
                error: (err, stack) => Center(
                  child: Text(
                    'Error: $err',
                    style: TextStyle(color: ObsidianMintColors.error),
                  ),
                ),
              ),
            ),

            // Input Row
            Container(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 8,
                bottom: 8 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                color: ObsidianMintColors.surface,
                border: Border(
                  top: BorderSide(
                    color: ObsidianMintColors.outlineVariant,
                    width: 0.5,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_replyMessage != null) _buildReplyPreviewBar(displayName),
                  _isRecording
                      ? Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.delete_forever_rounded,
                                color: ObsidianMintColors.error,
                              ),
                              onPressed: () => _stopRecording(send: false),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 40,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: ObsidianMintColors.background,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    const BlinkingDot(),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Recording  ${_formatRecordDuration(_recordDuration)}',
                                      style: TextStyle(
                                        color: ObsidianMintColors.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: ObsidianMintColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: Icon(
                                  Icons.send_rounded,
                                  color: ObsidianMintColors.onPrimary,
                                ),
                                onPressed: () => _stopRecording(send: true),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.add_circle_outline_rounded,
                                color: ObsidianMintColors.primary,
                              ),
                              onPressed: _showAttachmentSheet,
                            ),
                            Expanded(
                              child: TextFormField(
                                controller: _messageController,
                                focusNode: _focusNode,
                                style: TextStyle(
                                  color: ObsidianMintColors.textPrimary,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Type a message...',
                                  hintStyle: TextStyle(
                                    color: ObsidianMintColors.textSecondary,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  filled: true,
                                  fillColor: ObsidianMintColors.background,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                textInputAction: TextInputAction.send,
                                onFieldSubmitted: (_) => _sendMessage(),
                                contentInsertionConfiguration:
                                    ContentInsertionConfiguration(
                                      allowedMimeTypes: const <String>[
                                        'image/gif',
                                        'image/png',
                                        'image/jpeg',
                                        'image/webp',
                                      ],
                                      onContentInserted:
                                          (
                                            KeyboardInsertedContent content,
                                          ) async {
                                            try {
                                              Uint8List? bytes = content.data;
                                              if (bytes == null ||
                                                  bytes.isEmpty) {
                                                final UriContent uriContent =
                                                    UriContent();
                                                bytes = await uriContent.from(
                                                  Uri.parse(
                                                    content.uri.toString(),
                                                  ),
                                                );
                                              }
                                              if (bytes.isNotEmpty) {
                                                final ext = content.mimeType
                                                    .split('/')
                                                    .last;
                                                final fileName =
                                                    'keyboard_${DateTime.now().millisecondsSinceEpoch}.$ext';
                                                await _uploadAndSendMedia(
                                                  bytes,
                                                  fileName,
                                                  'image',
                                                );
                                              }
                                            } catch (e) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Failed to insert keyboard media: $e',
                                                    ),
                                                    backgroundColor:
                                                        ObsidianMintColors
                                                            .error,
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                    ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: ObsidianMintColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: _isSending
                                    ? SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: ObsidianMintColors.onPrimary,
                                        ),
                                      )
                                    : Icon(
                                        _isTextEmpty
                                            ? Icons.mic_none_rounded
                                            : Icons.send_rounded,
                                      ),
                                color: ObsidianMintColors.onPrimary,
                                onPressed: () {
                                  if (_isSending) return;
                                  if (_isTextEmpty) {
                                    _startRecording();
                                  } else {
                                    _sendMessage();
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BlinkingDot extends StatefulWidget {
  const BlinkingDot({super.key});

  @override
  State<BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: ObsidianMintColors.error,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class CompactTextMessage extends StatelessWidget {
  final String content;
  final String time;
  final bool isMe;
  final String status;
  final TextStyle textStyle;
  final TextStyle timeStyle;
  final bool isCallLog;
  final IconData? callIcon;
  final Color? callIconColor;

  const CompactTextMessage({
    super.key,
    required this.content,
    required this.time,
    required this.isMe,
    required this.status,
    required this.textStyle,
    required this.timeStyle,
    this.isCallLog = false,
    this.callIcon,
    this.callIconColor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxBubbleWidth = constraints.maxWidth;

        // Measure text size
        final textPainter = TextPainter(
          text: TextSpan(text: content, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: maxBubbleWidth);

        final double callIconPaddingWidth = isCallLog ? 22.0 : 0.0;
        final double textWidth = textPainter.width + callIconPaddingWidth;

        // Measure time + status row size
        final statusIconWidth = isMe ? 15.0 : 0.0;
        final timePainter = TextPainter(
          text: TextSpan(text: ' $time', style: timeStyle),
          textDirection: TextDirection.ltr,
        )..layout();

        final double timeWidth = timePainter.width + statusIconWidth + 8.0;

        // Check if it fits on one line
        final lines = textPainter.computeLineMetrics();
        final isSingleLine = lines.length <= 1;

        Widget buildText() {
          if (isCallLog && callIcon != null) {
            return Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        callIcon,
                        size: 16,
                        color: callIconColor ?? (isMe ? ObsidianMintColors.onPrimary : ObsidianMintColors.primary),
                      ),
                    ),
                  ),
                  TextSpan(text: content, style: textStyle),
                ],
              ),
            );
          } else {
            return Text(content, style: textStyle);
          }
        }

        if (isSingleLine && (textWidth + timeWidth < maxBubbleWidth)) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isCallLog && callIcon != null) ...[
                Icon(
                  callIcon,
                  size: 16,
                  color: callIconColor ?? (isMe ? ObsidianMintColors.onPrimary : ObsidianMintColors.primary),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(child: Text(content, style: textStyle)),
              const SizedBox(width: 8),
              _buildTimeRow(),
            ],
          );
        }

        // If multi-line, check if the last line has enough space for the time
        if (lines.isNotEmpty) {
          final lastLine = lines.last;
          final lastLineRemainingWidth = maxBubbleWidth - lastLine.width;
          if (lastLineRemainingWidth > timeWidth + 8.0) {
            return Stack(
              children: [
                buildText(),
                Positioned(bottom: 0, right: 0, child: _buildTimeRow()),
              ],
            );
          }
        }

        // Default: Column
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            buildText(),
            const SizedBox(height: 2),
            Align(alignment: Alignment.bottomRight, child: _buildTimeRow()),
          ],
        );
      },
    );
  }

  Widget _buildTimeRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(time, style: timeStyle),
        if (isMe) ...[
          const SizedBox(width: 3),
          Icon(
            status == 'read' ? Icons.done_all_rounded : Icons.done_rounded,
            size: 12,
            color: status == 'read'
                ? ObsidianMintColors.onPrimary
                : ObsidianMintColors.onPrimary.withValues(alpha: 0.5),
          ),
        ],
      ],
    );
  }
}

class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;

  const SwipeToReply({super.key, required this.child, required this.onReply});

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  double _dragOffset = 0.0;
  bool _thresholdReached = false;
  static const double _swipeThreshold = 60.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final double newOffset = _dragOffset + details.delta.dx;
    if (newOffset >= 0) {
      setState(() {
        if (newOffset > 100) {
          _dragOffset = 100 + (newOffset - 100) * 0.2;
        } else {
          _dragOffset = newOffset;
        }

        if (_dragOffset >= _swipeThreshold && !_thresholdReached) {
          _thresholdReached = true;
          HapticFeedback.lightImpact();
        } else if (_dragOffset < _swipeThreshold && _thresholdReached) {
          _thresholdReached = false;
        }
      });
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_thresholdReached) {
      widget.onReply();
    }
    setState(() {
      _thresholdReached = false;
    });
    final double currentOffset = _dragOffset;
    final animation = Tween<double>(begin: currentOffset, end: 0.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    animation.addListener(() {
      setState(() {
        _dragOffset = animation.value;
      });
    });
    _animationController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      behavior: HitTestBehavior.translucent,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          Positioned(
            left: -40 + (_dragOffset * 0.4),
            child: Opacity(
              opacity: (_dragOffset / _swipeThreshold).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: _thresholdReached ? 1.2 : 1.0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _thresholdReached
                        ? ObsidianMintColors.primary
                        : ObsidianMintColors.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.reply_rounded,
                    size: 18,
                    color: _thresholdReached
                        ? ObsidianMintColors.onPrimary
                        : ObsidianMintColors.primary,
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
