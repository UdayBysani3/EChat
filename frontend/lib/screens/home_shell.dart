import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../services/supabase_service.dart';
import '../services/chat_service.dart';
import '../config/theme.dart';
import '../widgets/full_screen_image_view.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  int _currentIndex = 0;

  final List<String> _titles = ['Chats', 'Requests'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Set status to online upon initializing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatServiceProvider).updateUserStatus('online');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Attempt setting status to offline upon disposing
    try {
      ref.read(chatServiceProvider).updateUserStatus('offline');
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final chatService = ref.read(chatServiceProvider);
    if (state == AppLifecycleState.resumed) {
      chatService.updateUserStatus('online');
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      chatService.updateUserStatus('offline');
    }
  }

  void _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ObsidianMintColors.surface,
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out from EChat?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ObsidianMintColors.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(supabaseServiceProvider).signOut();
      if (mounted) {
        context.go('/login');
      }
    }
  }

  void _showNewChatDialog() {
    final emailController = TextEditingController();
    bool isSearching = false;
    String? dialogError;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: ObsidianMintColors.surface,
            title: Text('New Chat Request', style: TextStyle(color: ObsidianMintColors.textPrimary)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Enter the email address of the person you want to connect with.',
                    style: TextStyle(color: ObsidianMintColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (dialogError != null) ...[
                    Text(
                      dialogError!,
                      style: TextStyle(color: ObsidianMintColors.error, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: emailController,
                    style: TextStyle(color: ObsidianMintColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      hintText: 'name@example.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ObsidianMintColors.primary,
                  foregroundColor: ObsidianMintColors.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: isSearching
                    ? null
                    : () async {
                        final email = emailController.text.trim();
                        if (email.isEmpty) {
                          setDialogState(() => dialogError = 'Please enter an email');
                          return;
                        }

                        setDialogState(() {
                          isSearching = true;
                          dialogError = null;
                        });

                        try {
                          final chatService = ref.read(chatServiceProvider);
                          
                          // 1. Search for user
                          final targetUser = await chatService.searchUserByEmail(email);
                          if (targetUser == null) {
                            setDialogState(() {
                              isSearching = false;
                              dialogError = 'No user found with this email';
                            });
                            return;
                          }

                          final targetId = targetUser['id'] as String;
                          final currentId = ref.read(supabaseServiceProvider).currentUser?.id;

                          if (targetId == currentId) {
                            setDialogState(() {
                              isSearching = false;
                              dialogError = 'You cannot chat with yourself';
                            });
                            return;
                          }

                          // 2. Send request
                          await chatService.sendChatRequest(targetId);
                          
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Chat request sent successfully!'),
                                backgroundColor: ObsidianMintColors.primaryContainer,
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() {
                            isSearching = false;
                            dialogError = e.toString().replaceFirst('Exception: ', '');
                          });
                        }
                      },
                child: isSearching
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianMintColors.onPrimary),
                      )
                    : const Text('Send Request'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditProfileBottomSheet() {
    final profile = ref.read(currentUserProfileProvider).value;
    final usernameController = TextEditingController(text: profile?['username'] as String? ?? '');
    final bioController = TextEditingController(text: profile?['bio'] as String? ?? '');
    final currentProfileImageUrl = profile?['profile_image'] as String?;

    XFile? pickedImageFile;
    bool isSaving = false;
    String? errorMsg;

    showModalBottomSheet(
      context: context,
      backgroundColor: ObsidianMintColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 20,
                      bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: ObsidianMintColors.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Edit Profile',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  if (errorMsg != null) ...[
                    Text(
                      errorMsg!,
                      style: TextStyle(color: ObsidianMintColors.error, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Profile picture editor preview
                  Center(
                    child: GestureDetector(
                      onTap: () async {
                        try {
                          final picker = ImagePicker();
                          final image = await picker.pickImage(
                            source: ImageSource.gallery,
                            maxWidth: 512,
                            maxHeight: 512,
                            imageQuality: 85,
                          );
                          if (image != null) {
                            setModalState(() {
                              pickedImageFile = image;
                            });
                          }
                        } catch (e) {
                          setModalState(() {
                            errorMsg = 'Failed to pick image: $e';
                          });
                        }
                      },
                      child: Stack(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ObsidianMintColors.primary.withValues(alpha: 0.1),
                              border: Border.all(color: ObsidianMintColors.primary, width: 1.5),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(40),
                              child: pickedImageFile != null
                                  ? Image.file(
                                      File(pickedImageFile!.path),
                                      fit: BoxFit.cover,
                                    )
                                  : (currentProfileImageUrl != null && currentProfileImageUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: currentProfileImageUrl,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) => const CircularProgressIndicator(),
                                          errorWidget: (context, url, error) => const Icon(Icons.person_rounded, size: 40),
                                        )
                                      : Center(
                                          child: Text(
                                            (usernameController.text.isNotEmpty)
                                                ? usernameController.text[0].toUpperCase()
                                                : 'U',
                                            style: TextStyle(
                                              fontSize: 32,
                                              fontWeight: FontWeight.bold,
                                              color: ObsidianMintColors.primary,
                                            ),
                                          ),
                                        )),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: ObsidianMintColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.camera_alt_rounded,
                                size: 16,
                                color: ObsidianMintColors.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: usernameController,
                    style: TextStyle(color: ObsidianMintColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: bioController,
                    maxLines: 3,
                    style: TextStyle(color: ObsidianMintColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Bio',
                      prefixIcon: Icon(Icons.info_outline_rounded),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final username = usernameController.text.trim();
                            final bio = bioController.text.trim();
                            if (username.isEmpty) {
                              setModalState(() => errorMsg = 'Username cannot be empty');
                              return;
                            }

                            setModalState(() {
                              isSaving = true;
                              errorMsg = null;
                            });

                            try {
                              String? uploadedImageUrl;
                              if (pickedImageFile != null) {
                                final chatService = ref.read(chatServiceProvider);
                                uploadedImageUrl = await chatService.uploadFile(
                                  pickedImageFile!.path,
                                  pickedImageFile!.name,
                                );
                              }

                              await ref.read(chatServiceProvider).updateProfile(
                                    username: username,
                                    bio: bio,
                                    profileImage: uploadedImageUrl,
                                  );

                              ref.invalidate(currentUserProfileProvider);

                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Profile updated successfully!'),
                                    backgroundColor: ObsidianMintColors.primaryContainer,
                                  ),
                                );
                              }
                            } catch (e) {
                              setModalState(() {
                                isSaving = false;
                                errorMsg = e.toString().replaceFirst('Exception: ', '');
                              });
                            }
                          },
                    child: isSaving
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ObsidianMintColors.onPrimary,
                            ),
                          )
                        : const Text('Save Changes'),
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

  @override
  Widget build(BuildContext context) {

    final currentUser = ref.watch(supabaseServiceProvider).currentUser;
    final userEmail = currentUser?.email ?? 'user@example.com';
    final profileAsync = ref.watch(currentUserProfileProvider);

    final requestsAsync = ref.watch(pendingRequestsProvider);
    final pendingCount = requestsAsync.maybeWhen(
      data: (list) => list.length,
      orElse: () => 0,
    );

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) {
            return Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
                if (pendingCount > 0)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: ObsidianMintColors.primary,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 8,
                        minHeight: 8,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        title: Text(_titles[_currentIndex]),
        actions: [
          IconButton(
            icon: Icon(Icons.logout_rounded, color: ObsidianMintColors.error),
            onPressed: _logout,
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: ObsidianMintColors.background,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      profileAsync.when(
              data: (profile) {
                final username = profile?['username'] as String? ?? 'EChat User';
                final bio = profile?['bio'] as String? ?? 'No bio yet';
                final profileImageUrl = profile?['profile_image'] as String?;

                return Container(
                  width: double.infinity,
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 24,
                    left: 20,
                    right: 20,
                    bottom: 24,
                  ),
                  decoration: BoxDecoration(
                    color: ObsidianMintColors.surface,
                    border: Border(
                      bottom: BorderSide(color: ObsidianMintColors.outlineVariant, width: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => FullScreenImageView(
                                  imageUrl: profileImageUrl,
                                  heroTag: 'drawer_profile_pic',
                                ),
                              ),
                            );
                          }
                        },
                        child: Hero(
                          tag: 'drawer_profile_pic',
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ObsidianMintColors.primary.withValues(alpha: 0.1),
                              border: Border.all(color: ObsidianMintColors.primary, width: 1.5),
                              image: profileImageUrl != null && profileImageUrl.isNotEmpty
                                  ? DecorationImage(
                                      image: NetworkImage(profileImageUrl),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: profileImageUrl == null || profileImageUrl.isEmpty
                                ? Center(
                                    child: Text(
                                      username.isNotEmpty ? username[0].toUpperCase() : 'U',
                                      style: TextStyle(
                                        color: ObsidianMintColors.primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 24,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18), // Added padding below the profile image
                      Text(
                        username,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: ObsidianMintColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        userEmail,
                        style: TextStyle(
                          fontSize: 13,
                          color: ObsidianMintColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        bio,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: ObsidianMintColors.textSecondary.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => Container(
                width: double.infinity,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 24,
                  left: 20,
                  right: 20,
                  bottom: 24,
                ),
                decoration: BoxDecoration(
                  color: ObsidianMintColors.surface,
                  border: Border(
                    bottom: BorderSide(color: ObsidianMintColors.outlineVariant, width: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ObsidianMintColors.primary.withValues(alpha: 0.1),
                        border: Border.all(color: ObsidianMintColors.primary, width: 1.5),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: ObsidianMintColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Loading...',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: ObsidianMintColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      userEmail,
                      style: TextStyle(
                        fontSize: 13,
                        color: ObsidianMintColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              error: (err, stack) => Container(
                width: double.infinity,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 24,
                  left: 20,
                  right: 20,
                  bottom: 24,
                ),
                decoration: BoxDecoration(
                  color: ObsidianMintColors.surface,
                  border: Border(
                    bottom: BorderSide(color: ObsidianMintColors.outlineVariant, width: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ObsidianMintColors.primary.withValues(alpha: 0.1),
                        border: Border.all(color: ObsidianMintColors.primary, width: 1.5),
                      ),
                      child: Icon(Icons.error_outline_rounded, color: ObsidianMintColors.error, size: 28),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Error loading profile',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: ObsidianMintColors.error,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      userEmail,
                      style: TextStyle(
                        fontSize: 13,
                        color: ObsidianMintColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.chat_bubble_outline_rounded, color: ObsidianMintColors.textSecondary),
              title: Text('Chats', style: TextStyle(color: ObsidianMintColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentIndex = 0);
              },
            ),
            ListTile(
              leading: Icon(Icons.notifications_none_rounded, color: ObsidianMintColors.textSecondary),
              title: Text('Requests', style: TextStyle(color: ObsidianMintColors.textPrimary)),
              trailing: pendingCount > 0
                  ? Badge(
                      label: Text(pendingCount.toString()),
                      backgroundColor: ObsidianMintColors.primary,
                      textColor: ObsidianMintColors.onPrimary,
                    )
                  : null,
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentIndex = 1);
              },
            ),
            Divider(color: ObsidianMintColors.outlineVariant, height: 1),
            ListTile(
              leading: Icon(Icons.edit_rounded, color: ObsidianMintColors.textSecondary),
              title: Text('Edit Profile', style: TextStyle(color: ObsidianMintColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _showEditProfileBottomSheet();
              },
            ),
            SwitchListTile(
              secondary: Icon(
                ref.watch(themeModeProvider) == ThemeMode.dark
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
                color: ObsidianMintColors.textSecondary,
              ),
              title: Text(
                'Dark Mode',
                style: TextStyle(color: ObsidianMintColors.textPrimary),
              ),
              value: ref.watch(themeModeProvider) == ThemeMode.dark,
              onChanged: (val) {
                ref.read(themeModeProvider.notifier).toggleTheme();
              },
            ),
            const Spacer(),
            ListTile(
              leading: Icon(Icons.logout_rounded, color: ObsidianMintColors.error),
              title: Text('Sign Out', style: TextStyle(color: ObsidianMintColors.error)),
              onTap: () {
                Navigator.pop(context);
                _logout();
              },
            ),
                      SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildChatsTab(),
          _buildRequestsTab(),
        ],
      ),
      floatingActionButton: (_currentIndex == 0 || _currentIndex == 1)
          ? FloatingActionButton(
              backgroundColor: ObsidianMintColors.primary,
              foregroundColor: ObsidianMintColors.onPrimary,
              onPressed: _showNewChatDialog,
              child: Icon(_currentIndex == 0 ? Icons.chat_rounded : Icons.person_add_rounded),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            activeIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chats',
          ),
          BottomNavigationBarItem(
            icon: pendingCount > 0
                ? Badge(
                    label: Text(pendingCount.toString()),
                    backgroundColor: ObsidianMintColors.primary,
                    textColor: ObsidianMintColors.onPrimary,
                    child: const Icon(Icons.group_add_outlined),
                  )
                : const Icon(Icons.group_add_outlined),
            activeIcon: pendingCount > 0
                ? Badge(
                    label: Text(pendingCount.toString()),
                    backgroundColor: ObsidianMintColors.primary,
                    textColor: ObsidianMintColors.onPrimary,
                    child: const Icon(Icons.group_add_rounded),
                  )
                : const Icon(Icons.group_add_rounded),
            label: 'Requests',
          ),
        ],
      ),
    );
  }

  Widget _buildChatsTab() {
    final chatsAsync = ref.watch(chatsListProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(chatsListProvider),
      color: ObsidianMintColors.primary,
      backgroundColor: ObsidianMintColors.surface,
      child: chatsAsync.when(
        data: (chats) {
          if (chats.isEmpty) {
            return Center(
              child: Text(
                'No active chats.\nTap the chat button to send a request!',
                textAlign: TextAlign.center,
                style: TextStyle(color: ObsidianMintColors.textSecondary),
              ),
            );
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: chats.length,
            separatorBuilder: (context, index) => Divider(
              color: ObsidianMintColors.outlineVariant,
              height: 1,
              indent: 84,
            ),
            itemBuilder: (context, index) {
              final chat = chats[index];
              final recipient = chat['recipient'] as Map<String, dynamic>;
              final isOnline = recipient['status'] == 'online';
              final name = recipient['username'] ?? recipient['email'] ?? 'User';
              final lastMsg = chat['last_message'] as String;
              final lastMsgTime = chat['last_message_time'] != null
                  ? _formatLastMessageTime(chat['last_message_time'] as String)
                  : '';

              return InkWell(
                onTap: () {
                  context.push(
                    '/chat/${chat['chat_id']}?name=$name&otherUserId=${recipient['id']}',
                  );
                },
                child: Container(
                  height: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          GestureDetector(
                            onTap: () {
                              final profileImage = recipient['profile_image'] as String?;
                              if (profileImage != null && profileImage.isNotEmpty) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => FullScreenImageView(
                                      imageUrl: profileImage,
                                      heroTag: 'chat_list_avatar_${recipient['id']}',
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Hero(
                              tag: 'chat_list_avatar_${recipient['id']}',
                              child: CircleAvatar(
                                radius: 26,
                                backgroundColor: ObsidianMintColors.surface,
                                backgroundImage: recipient['profile_image'] != null && (recipient['profile_image'] as String).isNotEmpty
                                    ? CachedNetworkImageProvider(recipient['profile_image'] as String)
                                    : null,
                                child: (recipient['profile_image'] == null || (recipient['profile_image'] as String).isEmpty)
                                    ? Text(
                                        name.substring(0, 1).toUpperCase(),
                                        style: TextStyle(
                                          color: ObsidianMintColors.primary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 20,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          if (isOnline)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: ObsidianMintColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: ObsidianMintColors.background,
                                    width: 2.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: ObsidianMintColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    lastMsgTime,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: ObsidianMintColors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              lastMsg,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: ObsidianMintColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => Center(
          child: CircularProgressIndicator(color: ObsidianMintColors.primary),
        ),
        error: (err, stack) => Center(
          child: Text(
            'Failed to load chats: $err',
            style: TextStyle(color: ObsidianMintColors.error),
          ),
        ),
      ),
    );
  }



  Widget _buildRequestsTab() {
    final requestsAsync = ref.watch(pendingRequestsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(pendingRequestsProvider),
      color: ObsidianMintColors.primary,
      backgroundColor: ObsidianMintColors.surface,
      child: requestsAsync.when(
        data: (requests) {
          if (requests.isEmpty) {
            return Center(
              child: Text(
                'No pending chat requests',
                style: TextStyle(color: ObsidianMintColors.textSecondary),
              ),
            );
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            separatorBuilder: (context, index) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final request = requests[index];
              final sender = request['sender'] as Map<String, dynamic>;
              final email = sender['email'] as String;
              final name = sender['username'] ?? email;

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.mark_email_unread_rounded, color: ObsidianMintColors.primary, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Chat Request',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: ObsidianMintColors.textPrimary,
                                  ),
                              ),
                            ],
                          ),
                          Text(
                            _formatLastMessageTime(request['created_at'] as String),
                            style: TextStyle(fontSize: 12, color: ObsidianMintColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: ObsidianMintColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'wants to connect with you via $email.',
                        style: TextStyle(fontSize: 13, color: ObsidianMintColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: ObsidianMintColors.error,
                            ),
                            onPressed: () async {
                              try {
                                await ref.read(chatServiceProvider).declineChatRequest(request['id'] as String);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Failed: $e'), backgroundColor: ObsidianMintColors.error),
                                  );
                                }
                              }
                            },
                            child: const Text('Decline'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ObsidianMintColors.primary,
                              foregroundColor: ObsidianMintColors.onPrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                            ),
                            onPressed: () async {
                              try {
                                await ref.read(chatServiceProvider).acceptChatRequest(
                                      request['id'] as String,
                                      sender['id'] as String,
                                    );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Chat request accepted!'),
                                      backgroundColor: ObsidianMintColors.primaryContainer,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Failed: $e'), backgroundColor: ObsidianMintColors.error),
                                  );
                                }
                              }
                            },
                            child: const Text('Accept'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => Center(
          child: CircularProgressIndicator(color: ObsidianMintColors.primary),
        ),
        error: (err, stack) => Center(
          child: Text(
            'Failed to load requests: $err',
            style: TextStyle(color: ObsidianMintColors.error),
          ),
        ),
      ),
    );
  }

  String _formatLastMessageTime(String timestampStr) {
    try {
      final dateTime = DateTime.parse(timestampStr).toLocal();
      final now = DateTime.now();
      if (dateTime.year == now.year && dateTime.month == now.month && dateTime.day == now.day) {
        final hour = dateTime.hour.toString().padLeft(2, '0');
        final minute = dateTime.minute.toString().padLeft(2, '0');
        return '$hour:$minute';
      } else if (dateTime.year == now.year &&
          dateTime.month == now.month &&
          dateTime.day == now.day - 1) {
        return 'Yesterday';
      } else {
        return '${dateTime.day}/${dateTime.month}';
      }
    } catch (e) {
      return '';
    }
  }
}
