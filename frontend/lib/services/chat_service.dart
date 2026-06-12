import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:echat/services/supabase_service.dart';

class ChatService {
  final SupabaseClient _client = Supabase.instance.client;

  String? get currentUserId => _client.auth.currentUser?.id;

  // Search a user by email in the database
  Future<Map<String, dynamic>?> searchUserByEmail(String email) async {
    final response = await _client
        .from('users')
        .select('id, email, username, profile_image, bio, status')
        .eq('email', email.trim().toLowerCase())
        .maybeSingle();
    return response;
  }

  // Send a chat request
  Future<void> sendChatRequest(String receiverId) async {
    final senderId = currentUserId;
    if (senderId == null) throw Exception('User not authenticated');
    if (senderId == receiverId) throw Exception('Cannot send a request to yourself');

    // Check if blocked interaction is active
    if (await isBlocked(receiverId)) {
      throw Exception('Unable to send chat request: blocked connection.');
    }

    // 1. Check if a chat room already exists between these two users
    final myChats = await _client
        .from('chat_members')
        .select('chat_id')
        .eq('user_id', senderId);
    
    if (myChats.isNotEmpty) {
      final myChatIds = myChats.map((m) => m['chat_id'] as String).toList();
      final commonChat = await _client
          .from('chat_members')
          .select()
          .inFilter('chat_id', myChatIds)
          .eq('user_id', receiverId);
      
      if (commonChat.isNotEmpty) {
        throw Exception('You are already friends with this user.');
      }
    }

    // 2. Check if a request already exists between these users (pending or accepted)
    final existingRequest = await _client
        .from('chat_requests')
        .select()
        .or('and(sender_id.eq.$senderId,receiver_id.eq.$receiverId),and(sender_id.eq.$receiverId,receiver_id.eq.$senderId)')
        .maybeSingle();

    if (existingRequest != null) {
      final status = existingRequest['status'] as String;
      if (status == 'pending') {
        throw Exception('A chat request is already pending with this user.');
      } else if (status == 'accepted') {
        throw Exception('You are already friends with this user.');
      } else {
        // if previously declined, delete the old request so we can insert a fresh one
        await _client
            .from('chat_requests')
            .delete()
            .eq('id', existingRequest['id']);
      }
    }

    await _client.from('chat_requests').insert({
      'sender_id': senderId,
      'receiver_id': receiverId,
      'status': 'pending',
    });
  }

  // Get pending chat requests received by the current user
  Future<List<Map<String, dynamic>>> getPendingRequests() async {
    final userId = currentUserId;
    if (userId == null) return [];

    final response = await _client
        .from('chat_requests')
        .select('*, sender:users!chat_requests_sender_id_fkey(id, email, username, profile_image)')
        .eq('receiver_id', userId)
        .eq('status', 'pending');

    return List<Map<String, dynamic>>.from(response);
  }

  // Accept a chat request (Atomic-like execution)
  Future<void> acceptChatRequest(String requestId, String senderId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    // Generate a UUID client-side so we don't need to SELECT back from chats
    // (the SELECT RLS policy requires membership, which doesn't exist yet)
    final chatId = _generateUUID();

    // 1. Update the request status to accepted
    await _client
        .from('chat_requests')
        .update({'status': 'accepted'})
        .eq('id', requestId);

    // 2. Create a new chat row with the pre-generated ID
    await _client.from('chats').insert({'id': chatId});

    // 3. Add both users as members of the new chat
    await _client.from('chat_members').insert([
      {'chat_id': chatId, 'user_id': senderId},
      {'chat_id': chatId, 'user_id': userId},
    ]);
  }

  /// Generate a RFC 4122 v4 UUID using a cryptographically secure RNG
  String _generateUUID() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));

    // Set version (4) and variant (10xx) bits per RFC 4122
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  // Decline/Ignore a chat request
  Future<void> declineChatRequest(String requestId) async {
    await _client
        .from('chat_requests')
        .delete()
        .eq('id', requestId);
  }

  // Fetch active chats list along with recipient profile and last message
  Future<List<Map<String, dynamic>>> getChatsList() async {
    final userId = currentUserId;
    if (userId == null) return [];

    // Step 1: Find all chat IDs where current user is a member
    final myMemberships = await _client
        .from('chat_members')
        .select('chat_id')
        .eq('user_id', userId);

    final chatIds = myMemberships.map((m) => m['chat_id'] as String).toList();
    if (chatIds.isEmpty) return [];

    // Step 2: Fetch all members of those chats, excluding ourselves
    final chatMembers = await _client
        .from('chat_members')
        .select('chat_id, user:users(id, email, username, profile_image, status)')
        .inFilter('chat_id', chatIds)
        .neq('user_id', userId);

    final results = <Map<String, dynamic>>[];

    for (var member in chatMembers) {
      final chatId = member['chat_id'] as String;
      final recipient = member['user'] as Map<String, dynamic>;

      // Step 3: Fetch the last message for this chat
      final lastMsgResponse = await _client
          .from('messages')
          .select('content, created_at, sender_id')
          .eq('chat_id', chatId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      results.add({
        'chat_id': chatId,
        'recipient': recipient,
        'last_message': lastMsgResponse?['content'] ?? 'No messages yet',
        'last_message_time': lastMsgResponse?['created_at'],
        'last_message_sender_id': lastMsgResponse?['sender_id'],
      });
    }

    // Sort by last message time descending (newest first)
    results.sort((a, b) {
      final aTime = a['last_message_time'] != null
          ? DateTime.parse(a['last_message_time'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b['last_message_time'] != null
          ? DateTime.parse(b['last_message_time'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return results;
  }

  // Fetch messages history
  Future<List<Map<String, dynamic>>> getMessages(String chatId) async {
    final response = await _client
        .from('messages')
        .select('id, sender_id, content, message_type, created_at, status')
        .eq('chat_id', chatId)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  // Send a text message (verifies block status first)
  Future<void> sendTextMessage(String chatId, String content) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    // Check if blocked
    final members = await _client
        .from('chat_members')
        .select('user_id')
        .eq('chat_id', chatId)
        .neq('user_id', userId);
    
    String? recipientId;
    if (members.isNotEmpty) {
      recipientId = members.first['user_id'] as String;
      if (await isBlocked(recipientId)) {
        throw Exception('Unable to send message: blocked connection.');
      }
    }

    await _client.from('messages').insert({
      'chat_id': chatId,
      'sender_id': userId,
      'receiver_id': recipientId,
      'content': content.trim(),
      'message_type': 'text',
      'status': 'sent',
    });
  }

  // Upload a file to Supabase storage bucket 'media'
  Future<String> uploadFile(String localPath, String fileName) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw Exception('File does not exist: $localPath');
    }

    final sanitizedFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_$sanitizedFileName';
    final path = 'chat_attachments/$uniqueName';

    await _client.storage.from('media').upload(
      path,
      file,
      fileOptions: const FileOptions(
        cacheControl: '3600',
        upsert: false,
      ),
    );

    return _client.storage.from('media').getPublicUrl(path);
  }

  // Upload bytes to Supabase storage bucket 'media'
  Future<String> uploadBytes(Uint8List bytes, String fileName) async {
    final sanitizedFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_$sanitizedFileName';
    final path = 'chat_attachments/$uniqueName';

    await _client.storage.from('media').uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(
        cacheControl: '3600',
        upsert: false,
      ),
    );

    return _client.storage.from('media').getPublicUrl(path);
  }

  // Send a media message (image, audio, file)
  Future<void> sendMediaMessage(String chatId, String fileUrl, String messageType) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    // Check if blocked
    final members = await _client
        .from('chat_members')
        .select('user_id')
        .eq('chat_id', chatId)
        .neq('user_id', userId);
    
    String? recipientId;
    if (members.isNotEmpty) {
      recipientId = members.first['user_id'] as String;
      if (await isBlocked(recipientId)) {
        throw Exception('Unable to send message: blocked connection.');
      }
    }

    await _client.from('messages').insert({
      'chat_id': chatId,
      'sender_id': userId,
      'receiver_id': recipientId,
      'content': fileUrl,
      'message_type': messageType,
      'status': 'sent',
    });
  }

  // Send location message
  Future<void> sendLocationMessage(String chatId, double latitude, double longitude) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    // Check if blocked
    final members = await _client
        .from('chat_members')
        .select('user_id')
        .eq('chat_id', chatId)
        .neq('user_id', userId);
    
    String? recipientId;
    if (members.isNotEmpty) {
      recipientId = members.first['user_id'] as String;
      if (await isBlocked(recipientId)) {
        throw Exception('Unable to send message: blocked connection.');
      }
    }

    await _client.from('messages').insert({
      'chat_id': chatId,
      'sender_id': userId,
      'receiver_id': recipientId,
      'content': '$latitude,$longitude',
      'message_type': 'location',
      'status': 'sent',
    });
  }

  // Listen to realtime messages in a specific chat
  Stream<List<Map<String, dynamic>>> streamMessages(String chatId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('chat_id', chatId)
        .order('created_at', ascending: true);
  }

  // Listen to changes in received chat requests in real-time
  Stream<List<Map<String, dynamic>>> streamPendingRequests() {
    final userId = currentUserId;
    if (userId == null) return const Stream.empty();

    return _client
        .from('chat_requests')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', userId);
  }

  // UPDATE USER ONLINE STATUS (PRESENCE)
  Future<void> updateUserStatus(String status) async {
    final userId = currentUserId;
    if (userId == null) return;

    await _client
        .from('users')
        .update({'status': status})
        .eq('id', userId);
  }

  // MARK MESSAGES AS READ (READ RECEIPTS)
  Future<void> markMessagesAsRead(String chatId) async {
    final userId = currentUserId;
    if (userId == null) return;

    await _client
        .from('messages')
        .update({'status': 'read'})
        .eq('chat_id', chatId)
        .neq('sender_id', userId)
        .eq('status', 'sent');
  }

  // BLOCK SYSTEM APIs
  Future<void> blockUser(String blockedId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    await _client.from('blocked_users').insert({
      'blocker_id': userId,
      'blocked_id': blockedId,
    });
  }

  Future<void> unblockUser(String blockedId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    await _client
        .from('blocked_users')
        .delete()
        .eq('blocker_id', userId)
        .eq('blocked_id', blockedId);
  }

  Future<bool> isBlocked(String targetId) async {
    final userId = currentUserId;
    if (userId == null) return false;

    final response = await _client
        .from('blocked_users')
        .select()
        .or('and(blocker_id.eq.$userId,blocked_id.eq.$targetId),and(blocker_id.eq.$targetId,blocked_id.eq.$userId)')
        .maybeSingle();

    return response != null;
  }

  Future<List<Map<String, dynamic>>> getBlockedUsers() async {
    final userId = currentUserId;
    if (userId == null) return [];

    final response = await _client
        .from('blocked_users')
        .select('*, blocked:users!blocked_users_blocked_id_fkey(id, email, username, profile_image)')
        .eq('blocker_id', userId);

    return List<Map<String, dynamic>>.from(response);
  }

  // React to a message (toggle emoji reaction)
  Future<void> reactToMessage(String messageId, String emoji, Map<String, dynamic> currentReactions) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final updatedReactions = Map<String, dynamic>.from(currentReactions);
    if (updatedReactions[userId] == emoji) {
      // Toggle off if they clicked the same emoji
      updatedReactions.remove(userId);
    } else {
      updatedReactions[userId] = emoji;
    }

    await _client
        .from('messages')
        .update({'reactions': updatedReactions})
        .eq('id', messageId);
  }

  // Delete a message (only sender is allowed)
  Future<void> deleteMessage(String messageId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    await _client
        .from('messages')
        .delete()
        .eq('id', messageId)
        .eq('sender_id', userId);
  }

  // Clear all messages sent by current user in a chat in one query
  Future<void> clearMyMessages(String chatId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    await _client
        .from('messages')
        .delete()
        .eq('chat_id', chatId)
        .eq('sender_id', userId);
  }

  // Update current user username, bio, and optionally profile image
  Future<void> updateProfile({required String username, required String bio, String? profileImage}) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final updates = <String, dynamic>{
      'username': username.trim(),
      'bio': bio.trim(),
    };

    if (profileImage != null) {
      updates['profile_image'] = profileImage;
    }

    await _client
        .from('users')
        .update(updates)
        .eq('id', userId);
  }

  // ─────────────────────────────────────────────────────────────
  // CALLING SYSTEM APIs
  // ─────────────────────────────────────────────────────────────

  // Log a new call
  Future<String> logCall({
    required String receiverId,
    required String chatId,
    required bool isVideo,
  }) async {
    final callerId = currentUserId;
    if (callerId == null) throw Exception('User not authenticated');

    final response = await _client.from('call_logs').insert({
      'caller_id': callerId,
      'receiver_id': receiverId,
      'chat_id': chatId,
      'is_video': isVideo,
      'status': 'initiated',
    }).select('id').single();

    return response['id'] as String;
  }

  // Update call log status
  Future<void> updateCallStatus(String callId, String status) async {
    await _client
        .from('call_logs')
        .update({'status': status})
        .eq('id', callId);
  }

  // Fetch all call logs for current user (caller or receiver)
  Future<List<Map<String, dynamic>>> getCallHistory() async {
    final userId = currentUserId;
    if (userId == null) return [];

    final response = await _client
        .from('call_logs')
        .select('*, caller:users!call_logs_caller_id_fkey(id, email, username, profile_image), receiver:users!call_logs_receiver_id_fkey(id, email, username, profile_image)')
        .or('caller_id.eq.$userId,receiver_id.eq.$userId')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }
}

// ─────────────────────────────────────────────────────────────
// Singleton ChatService instance
// ─────────────────────────────────────────────────────────────
final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService();
});

// ─────────────────────────────────────────────────────────────
// REACTIVE: Chats list stream
// Uses Supabase Realtime Postgres Changes to listen for:
//   - New chats (chat_members INSERT)
//   - New/updated messages (messages INSERT/UPDATE)
//   - User status changes (users UPDATE)
// On any of these events, the full chats list is re-fetched.
// ─────────────────────────────────────────────────────────────
final chatsListProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  // Watch sessionProvider to ensure the stream is recreated when auth state changes (e.g., logout/login)
  final session = ref.watch(sessionProvider);
  final userId = session?.user.id;

  if (userId == null) return const Stream.empty();

  final chatService = ref.watch(chatServiceProvider);
  final client = Supabase.instance.client;

  final controller = StreamController<List<Map<String, dynamic>>>();

  // Initial fetch
  Future<void> fetchAndEmit() async {
    try {
      final chats = await chatService.getChatsList();
      if (!controller.isClosed) {
        controller.add(chats);
      }
    } catch (e) {
      if (!controller.isClosed) {
        controller.addError(e);
      }
    }
  }

  fetchAndEmit();

  // Subscribe to Realtime Postgres Changes on multiple tables
  final channel = client.channel('home-chats-realtime')

    // When a new member row appears (chat accepted), refresh
    .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'chat_members',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (_) => fetchAndEmit(),
    )

    // When any new message arrives in any chat, refresh (updates last message)
    .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (_) => fetchAndEmit(),
    )

    // When message status changes (read receipts), refresh
    .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'messages',
      callback: (_) => fetchAndEmit(),
    )

    // When message is deleted, refresh
    .onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'messages',
      callback: (_) => fetchAndEmit(),
    )

    // When user status changes (online/offline), refresh
    .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'users',
      callback: (_) => fetchAndEmit(),
    );

  channel.subscribe();

  // Cleanup channel + controller on provider dispose
  ref.onDispose(() {
    client.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});

// ─────────────────────────────────────────────────────────────
// REACTIVE: Pending chat requests stream
// Listens on chat_requests table for INSERT/UPDATE/DELETE
// targeting the current user as receiver.
// ─────────────────────────────────────────────────────────────
final pendingRequestsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  // Watch sessionProvider to ensure the stream is recreated when auth state changes
  final session = ref.watch(sessionProvider);
  final userId = session?.user.id;

  if (userId == null) return const Stream.empty();

  final chatService = ref.watch(chatServiceProvider);
  final client = Supabase.instance.client;

  final controller = StreamController<List<Map<String, dynamic>>>();

  // Initial fetch
  Future<void> fetchAndEmit() async {
    try {
      final requests = await chatService.getPendingRequests();
      if (!controller.isClosed) {
        controller.add(requests);
      }
    } catch (e) {
      if (!controller.isClosed) {
        controller.addError(e);
      }
    }
  }

  fetchAndEmit();

  // Subscribe to Realtime Postgres Changes on chat_requests
  final channel = client.channel('home-requests-realtime')

    // New request received
    .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'chat_requests',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'receiver_id',
        value: userId,
      ),
      callback: (_) => fetchAndEmit(),
    )

    // Request status changed (accepted/declined)
    .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'chat_requests',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'receiver_id',
        value: userId,
      ),
      callback: (_) => fetchAndEmit(),
    )

    // Request deleted
    .onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'chat_requests',
      callback: (_) => fetchAndEmit(),
    );

  channel.subscribe();

  ref.onDispose(() {
    client.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});

// ─────────────────────────────────────────────────────────────
// REACTIVE: Real-time messages for a specific chat
// Uses Supabase's built-in .stream() which creates a
// Realtime subscription and syncs full state automatically.
// ─────────────────────────────────────────────────────────────
final chatMessagesStreamProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, chatId) {
  final chatService = ref.watch(chatServiceProvider);
  return chatService.streamMessages(chatId);
});

// ─────────────────────────────────────────────────────────────
// REACTIVE: Real-time user status (online/offline)
// Streams changes to a user's status from the users table.
// ─────────────────────────────────────────────────────────────
final userStatusProvider = StreamProvider.family<String, String>((ref, userId) {
  final client = Supabase.instance.client;
  final controller = StreamController<String>();

  Future<void> fetchStatus() async {
    try {
      final res = await client
          .from('users')
          .select('status')
          .eq('id', userId)
          .maybeSingle();
      final status = res?['status'] as String? ?? 'offline';
      if (!controller.isClosed) {
        controller.add(status);
      }
    } catch (_) {
      if (!controller.isClosed) {
        controller.add('offline');
      }
    }
  }

  fetchStatus();

  final channel = client
      .channel('user-status-$userId')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'users',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: userId,
        ),
        callback: (payload) {
          if (payload.newRecord['status'] == null) return;
          final newStatus = payload.newRecord['status'] as String? ?? 'offline';
          if (!controller.isClosed) {
            controller.add(newStatus);
          }
        },
      )
      .subscribe();

  ref.onDispose(() {
    client.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});

// ─────────────────────────────────────────────────────────────
// REACTIVE: Other user profile details stream
// Streams changes to a specific user's profile from the users table.
// ─────────────────────────────────────────────────────────────
final otherUserProfileProvider = StreamProvider.family<Map<String, dynamic>?, String>((ref, userId) {
  final client = Supabase.instance.client;
  final controller = StreamController<Map<String, dynamic>?>();

  Future<void> fetchProfile() async {
    try {
      final res = await client
          .from('users')
          .select('id, email, username, profile_image, bio, status')
          .eq('id', userId)
          .maybeSingle();
      if (!controller.isClosed) {
        controller.add(res);
      }
    } catch (_) {
      if (!controller.isClosed) {
        controller.add(null);
      }
    }
  }

  fetchProfile();

  final channel = client
      .channel('other-user-profile-$userId')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'users',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: userId,
        ),
        callback: (payload) {
          if (!controller.isClosed) {
            controller.add(payload.newRecord);
          }
        },
      )
      .subscribe();

  ref.onDispose(() {
    client.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});

// ─────────────────────────────────────────────────────────────
// REACTIVE: Current user profile details stream
// Streams changes to the current user's profile from the users table.
// ─────────────────────────────────────────────────────────────
final currentUserProfileProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  // Watch sessionProvider to ensure the stream is recreated when auth state changes
  final session = ref.watch(sessionProvider);
  final userId = session?.user.id;
  if (userId == null) return const Stream.empty();

  final client = Supabase.instance.client;

  final controller = StreamController<Map<String, dynamic>?>();

  Future<void> fetchProfile() async {
    try {
      final res = await client
          .from('users')
          .select('id, email, username, profile_image, bio, status')
          .eq('id', userId)
          .maybeSingle();
      if (!controller.isClosed) {
        controller.add(res);
      }
    } catch (_) {
      if (!controller.isClosed) {
        controller.add(null);
      }
    }
  }

  fetchProfile();

  final channel = client
      .channel('my-profile')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'users',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: userId,
        ),
        callback: (payload) {
          if (!controller.isClosed) {
            controller.add(payload.newRecord);
          }
        },
      )
      .subscribe();

  ref.onDispose(() {
    client.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});

// ─────────────────────────────────────────────────────────────
// REACTIVE: Call history stream
// Listens on call_logs table for insertions/updates involving the current user.
// ─────────────────────────────────────────────────────────────
final callHistoryProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final chatService = ref.watch(chatServiceProvider);
  final session = ref.watch(sessionProvider);
  final userId = session?.user.id;

  if (userId == null) return const Stream.empty();

  final client = Supabase.instance.client;
  final controller = StreamController<List<Map<String, dynamic>>>();

  Future<void> fetchAndEmit() async {
    try {
      final logs = await chatService.getCallHistory();
      if (!controller.isClosed) {
        controller.add(logs);
      }
    } catch (e) {
      if (!controller.isClosed) {
        controller.addError(e);
      }
    }
  }

  fetchAndEmit();

  final channel = client.channel('call-logs-realtime')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'call_logs',
        callback: (_) => fetchAndEmit(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'call_logs',
        callback: (_) => fetchAndEmit(),
      );

  channel.subscribe();

  ref.onDispose(() {
    client.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});

// ─────────────────────────────────────────────────────────────
// REACTIVE: Incoming calls stream
// Listens for calls where status = 'initiated' and receiver = current user.
// ─────────────────────────────────────────────────────────────
final incomingCallsStreamProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final session = ref.watch(sessionProvider);
  final userId = session?.user.id;

  if (userId == null) return const Stream.empty();

  final client = Supabase.instance.client;
  final controller = StreamController<Map<String, dynamic>?>();

  Future<void> checkIncoming() async {
    try {
      final res = await client
          .from('call_logs')
          .select('*, caller:users!call_logs_caller_id_fkey(id, email, username, profile_image)')
          .eq('receiver_id', userId)
          .eq('status', 'initiated')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (!controller.isClosed) {
        controller.add(res);
      }
    } catch (_) {}
  }

  checkIncoming();

  final channel = client.channel('incoming-calls-realtime')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'call_logs',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'receiver_id',
          value: userId,
        ),
        callback: (payload) {
          checkIncoming();
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'call_logs',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'receiver_id',
          value: userId,
        ),
        callback: (payload) {
          checkIncoming();
        },
      );

  channel.subscribe();

  ref.onDispose(() {
    client.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});
