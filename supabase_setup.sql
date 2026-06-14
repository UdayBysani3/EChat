-- =============================================================
-- ECHAT — Complete Supabase Database Setup
-- Run this once in Supabase Dashboard → SQL Editor → New Query
-- =============================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- =============================================================
-- TABLES
-- =============================================================

-- 1. Users (mirrors auth.users)
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL UNIQUE,
    username TEXT UNIQUE,
    profile_image TEXT,
    bio TEXT,
    status TEXT DEFAULT 'offline',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. Chats
CREATE TABLE IF NOT EXISTS public.chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 3. Chat Members (many-to-many: chats ↔ users)
CREATE TABLE IF NOT EXISTS public.chat_members (
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    PRIMARY KEY (chat_id, user_id)
);

-- 4. Chat Requests
CREATE TABLE IF NOT EXISTS public.chat_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    receiver_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
    sender_notified_on_decline BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT unique_sender_receiver UNIQUE (sender_id, receiver_id)
);

-- 5. Messages
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    receiver_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    message_type TEXT DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'audio', 'file', 'location')),
    status TEXT DEFAULT 'sent' CHECK (status IN ('sent', 'read')),
    reactions JSONB DEFAULT '{}'::jsonb NOT NULL,
    reply_to_id UUID REFERENCES public.messages(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 6. Blocked Users
CREATE TABLE IF NOT EXISTS public.blocked_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    blocked_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT unique_blocker_blocked UNIQUE (blocker_id, blocked_id),
    CONSTRAINT self_block_check CHECK (blocker_id <> blocked_id)
);

-- 7. Call Logs (calling history)
CREATE TABLE IF NOT EXISTS public.call_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caller_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    receiver_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    chat_id UUID REFERENCES public.chats(id) ON DELETE CASCADE,
    is_video BOOLEAN DEFAULT false,
    status TEXT DEFAULT 'initiated' CHECK (status IN ('initiated', 'ringing', 'connected', 'missed', 'ended')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);


-- =============================================================
-- AUTH TRIGGER (auto-sync new signups to public.users)
-- =============================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id, email, username, profile_image, status)
  VALUES (
    new.id,
    new.email,
    COALESCE(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
    new.raw_user_meta_data->>'profile_image',
    'offline'
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Sync any existing auth users that were created before this script
INSERT INTO public.users (id, email, username, profile_image, status)
SELECT id, email, COALESCE(raw_user_meta_data->>'username', split_part(email, '@', 1)), raw_user_meta_data->>'profile_image', 'offline'
FROM auth.users
ON CONFLICT (id) DO UPDATE
SET profile_image = EXCLUDED.profile_image, username = EXCLUDED.username;


-- =============================================================
-- ROW LEVEL SECURITY POLICIES
-- =============================================================

-- users
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view all profiles" ON public.users;
DROP POLICY IF EXISTS "Users can update own profile" ON public.users;
DROP POLICY IF EXISTS "Allow insert for auth trigger" ON public.users;

CREATE POLICY "Users can view all profiles" ON public.users FOR SELECT TO authenticated USING (true);
CREATE POLICY "Users can update own profile" ON public.users FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = id);
CREATE POLICY "Allow insert for auth trigger" ON public.users FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = id);

-- chats
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view their chats" ON public.chats;
DROP POLICY IF EXISTS "Authenticated users can create chats" ON public.chats;

CREATE POLICY "Users can view their chats" ON public.chats FOR SELECT TO authenticated
  USING (id IN (SELECT chat_id FROM public.chat_members WHERE user_id = (SELECT auth.uid())));
CREATE POLICY "Authenticated users can create chats" ON public.chats FOR INSERT TO authenticated WITH CHECK (true);

-- Security Definer helper to check chat membership without RLS recursion
CREATE OR REPLACE FUNCTION public.is_chat_member(chat_id_param UUID, user_id_param UUID)
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
SET search_path = 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.chat_members
    WHERE chat_id = chat_id_param AND user_id = user_id_param
  );
$$;

-- Security Definer helper to check if email exists in public.users table (allows anonymous check during login/reset)
CREATE OR REPLACE FUNCTION public.check_user_email_exists(email_param TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.users WHERE LOWER(email) = LOWER(email_param)
  );
END;
$$;

-- chat_members
ALTER TABLE public.chat_members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view chat memberships" ON public.chat_members;
DROP POLICY IF EXISTS "Authenticated users can add chat members" ON public.chat_members;

CREATE POLICY "Users can view chat memberships" ON public.chat_members FOR SELECT TO authenticated
  USING (public.is_chat_member(chat_id, (SELECT auth.uid())));
CREATE POLICY "Authenticated users can add chat members" ON public.chat_members FOR INSERT TO authenticated WITH CHECK (true);

-- chat_requests
ALTER TABLE public.chat_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own chat requests" ON public.chat_requests;
DROP POLICY IF EXISTS "Users can send chat requests" ON public.chat_requests;
DROP POLICY IF EXISTS "Users can update received requests" ON public.chat_requests;
DROP POLICY IF EXISTS "Users can delete own requests" ON public.chat_requests;

CREATE POLICY "Users can view own chat requests" ON public.chat_requests FOR SELECT TO authenticated
  USING (sender_id = (SELECT auth.uid()) OR receiver_id = (SELECT auth.uid()));
CREATE POLICY "Users can send chat requests" ON public.chat_requests FOR INSERT TO authenticated
  WITH CHECK (sender_id = (SELECT auth.uid()));
CREATE POLICY "Users can update received requests" ON public.chat_requests FOR UPDATE TO authenticated
  USING (receiver_id = (SELECT auth.uid()));
CREATE POLICY "Users can delete own requests" ON public.chat_requests FOR DELETE TO authenticated
  USING (sender_id = (SELECT auth.uid()) OR receiver_id = (SELECT auth.uid()));

-- messages
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view messages in their chats" ON public.messages;
DROP POLICY IF EXISTS "Users can send messages" ON public.messages;
DROP POLICY IF EXISTS "Users can update message status" ON public.messages;
DROP POLICY IF EXISTS "Users can delete own messages" ON public.messages;

CREATE POLICY "Users can view messages in their chats" ON public.messages FOR SELECT TO authenticated
  USING (sender_id = (SELECT auth.uid()) OR receiver_id = (SELECT auth.uid()));
CREATE POLICY "Users can send messages" ON public.messages FOR INSERT TO authenticated
  WITH CHECK (sender_id = (SELECT auth.uid()));
CREATE POLICY "Users can update message status" ON public.messages FOR UPDATE TO authenticated
  USING (sender_id = (SELECT auth.uid()) OR receiver_id = (SELECT auth.uid()));
CREATE POLICY "Users can delete own messages" ON public.messages FOR DELETE TO authenticated
  USING (sender_id = (SELECT auth.uid()));

-- blocked_users
ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view their blocks" ON public.blocked_users;
DROP POLICY IF EXISTS "Users can block others" ON public.blocked_users;
DROP POLICY IF EXISTS "Users can unblock" ON public.blocked_users;

CREATE POLICY "Users can view their blocks" ON public.blocked_users FOR SELECT TO authenticated
  USING (blocker_id = (SELECT auth.uid()) OR blocked_id = (SELECT auth.uid()));
CREATE POLICY "Users can block others" ON public.blocked_users FOR INSERT TO authenticated
  WITH CHECK (blocker_id = (SELECT auth.uid()));
CREATE POLICY "Users can unblock" ON public.blocked_users FOR DELETE TO authenticated
  USING (blocker_id = (SELECT auth.uid()));

-- call_logs
ALTER TABLE public.call_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own call logs" ON public.call_logs;
DROP POLICY IF EXISTS "Users can insert call logs" ON public.call_logs;
DROP POLICY IF EXISTS "Users can update call logs" ON public.call_logs;
DROP POLICY IF EXISTS "Users can delete call logs" ON public.call_logs;

CREATE POLICY "Users can view own call logs" ON public.call_logs FOR SELECT TO authenticated
  USING (caller_id = (SELECT auth.uid()) OR receiver_id = (SELECT auth.uid()));
CREATE POLICY "Users can insert call logs" ON public.call_logs FOR INSERT TO authenticated
  WITH CHECK (caller_id = (SELECT auth.uid()));
CREATE POLICY "Users can update call logs" ON public.call_logs FOR UPDATE TO authenticated
  USING (caller_id = (SELECT auth.uid()) OR receiver_id = (SELECT auth.uid()));
CREATE POLICY "Users can delete call logs" ON public.call_logs FOR DELETE TO authenticated
  USING (caller_id = (SELECT auth.uid()) OR receiver_id = (SELECT auth.uid()));


-- =============================================================
-- REALTIME & PERFORMANCE
-- =============================================================

-- Safely add tables to publication by checking if they are already in publication
-- (Supabase allows ADD TABLE but if they are already added, we drop/add or just let it continue)
ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public.messages;
ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public.chat_requests;
ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public.users;
ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public.chat_members;
ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public.blocked_users;
ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public.call_logs;

ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_requests;
ALTER PUBLICATION supabase_realtime ADD TABLE public.users;
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_members;
ALTER PUBLICATION supabase_realtime ADD TABLE public.blocked_users;
ALTER PUBLICATION supabase_realtime ADD TABLE public.call_logs;

CREATE INDEX IF NOT EXISTS idx_users_email ON public.users (email);
CREATE INDEX IF NOT EXISTS idx_chat_requests_receiver ON public.chat_requests (receiver_id, status);
CREATE INDEX IF NOT EXISTS idx_chat_members_user ON public.chat_members (user_id);
CREATE INDEX IF NOT EXISTS idx_messages_chat_created ON public.messages (chat_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_call_logs_caller_receiver ON public.call_logs (caller_id, receiver_id);


-- =============================================================
-- STORAGE SETUP & POLICIES (for media/avatars)
-- =============================================================

-- Ensure the media bucket exists and is public
INSERT INTO storage.buckets (id, name, public)
VALUES ('media', 'media', true)
ON CONFLICT (id) DO NOTHING;

-- RLS Policies on storage.objects for media bucket
-- Allow public select/read access
DROP POLICY IF EXISTS "Allow public read on media" ON storage.objects;
CREATE POLICY "Allow public read on media" ON storage.objects
  FOR SELECT TO public USING (bucket_id = 'media');

-- Allow public upload access (so anonymous users can upload files/profile pics during signup)
DROP POLICY IF EXISTS "Allow public insert on media" ON storage.objects;
CREATE POLICY "Allow public insert on media" ON storage.objects
  FOR INSERT TO public WITH CHECK (bucket_id = 'media');

-- Allow public update/delete access
DROP POLICY IF EXISTS "Allow public update/delete on media" ON storage.objects;
CREATE POLICY "Allow public update/delete on media" ON storage.objects
  FOR ALL TO public USING (bucket_id = 'media');

-- Enable replica identity FULL on critical tables to send full row information on deletes for instant client sync
ALTER TABLE public.messages REPLICA IDENTITY FULL;
ALTER TABLE public.chat_members REPLICA IDENTITY FULL;
ALTER TABLE public.users REPLICA IDENTITY FULL;
ALTER TABLE public.chat_requests REPLICA IDENTITY FULL;
ALTER TABLE public.call_logs REPLICA IDENTITY FULL;


-- =============================================================
-- EXTRA CONSTRAINTS & OPTIMIZED RPC FUNCTIONS
-- =============================================================

-- Symmetric index to prevent duplicate chat requests in reverse direction
CREATE UNIQUE INDEX IF NOT EXISTS unique_sender_receiver_symmetric ON public.chat_requests (
    LEAST(sender_id, receiver_id),
    GREATEST(sender_id, receiver_id)
);

-- Mark declined chat requests as notified to the sender
CREATE OR REPLACE FUNCTION public.mark_decline_notified(request_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  UPDATE public.chat_requests
  SET sender_notified_on_decline = true
  WHERE id = request_id AND sender_id = auth.uid();
END;
$$;

-- Optimized chat retrieval RPC resolving N+1 querying bottlenecks
CREATE OR REPLACE FUNCTION public.get_user_chats(user_uuid UUID)
RETURNS TABLE (
  chat_id UUID,
  recipient_id UUID,
  recipient_email TEXT,
  recipient_username TEXT,
  recipient_profile_image TEXT,
  recipient_status TEXT,
  last_message_content TEXT,
  last_message_type TEXT,
  last_message_time TIMESTAMP WITH TIME ZONE,
  last_message_sender_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH user_chats AS (
    SELECT cm.chat_id, cm2.user_id AS recipient_id
    FROM public.chat_members cm
    JOIN public.chat_members cm2 ON cm.chat_id = cm2.chat_id AND cm2.user_id <> user_uuid
    WHERE cm.user_id = user_uuid
  ),
  chat_last_messages AS (
    SELECT DISTINCT ON (m.chat_id)
      m.chat_id,
      m.content,
      m.message_type,
      m.created_at,
      m.sender_id
    FROM public.messages m
    ORDER BY m.chat_id, m.created_at DESC
  )
  SELECT
    uc.chat_id,
    u.id AS recipient_id,
    u.email AS recipient_email,
    u.username AS recipient_username,
    u.profile_image AS recipient_profile_image,
    u.status AS recipient_status,
    lm.content AS last_message_content,
    lm.message_type AS last_message_type,
    lm.created_at AS last_message_time,
    lm.sender_id AS last_message_sender_id
  FROM user_chats uc
  JOIN public.users u ON uc.recipient_id = u.id
  LEFT JOIN chat_last_messages lm ON uc.chat_id = lm.chat_id
  ORDER BY COALESCE(lm.created_at, '1970-01-01'::timestamp with time zone) DESC;
END;
$$;
