# 💬 EChat — Secure Real-Time Messaging & Calling Application

EChat is a premium, secure, and reactive direct messaging application built with **Flutter** and **Supabase**. Designed with a modern, high-contrast **Obsidian & Mint** aesthetic, EChat delivers a fast, responsive, and feature-rich user experience for direct communications.

---

## ✨ Features

- **⚡ Real-Time Messaging**: Direct 1-on-1 messaging powered by Supabase Realtime changes and WebSockets.
- **📞 Voice & Video Calling**: Smooth in-app audio and video calls with real-time call states (ringing, connected, missed) and background listener prompts.
- **📁 Rich Media Sharing**:
  - Send text, images, and documents.
  - Audio recording and playback widget.
  - Interactive **OpenStreetMap** location sharing with direct redirection to navigation apps.
- **🔒 Secure Authentication**:
  - Secure email/password login.
  - Secure Password Reset flow via OTP verification codes sent through **EmailJS**.
  - Interactive password visibility toggles (eye icon) on all auth forms.
- **⚙️ Advanced Chat Settings**:
  - Instant user blocking/unblocking system.
  - Bulk message clearing (optimized bulk delete query).
  - Sent / Read message receipts.
- **👤 Profile Management**: Edit profile username and bio, upload/change profile picture to Supabase Storage, and tap avatars to view them full-screen with pinch-to-zoom.
- **🌓 Appearance & Typography**: Dynamic Dark/Light mode toggle loaded with the premium **Google Figtree** font.

---

## 🛠️ Technology Stack

- **Frontend**: Flutter (Dart)
- **State Management**: Flutter Riverpod (reactive providers)
- **Database & Backend**: Supabase (PostgreSQL, Auth, Realtime Postgres Changes, Storage Buckets)
- **Styling & Animations**: Vanilla Flutter with Custom Colors, Google Fonts, and `flutter_animate` micro-interactions
- **Map Services**: OpenStreetMap powered by `flutter_map`
- **Email Delivery**: EmailJS API

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK (latest stable channel)
- A Supabase account and project
- An EmailJS account

### Backend Setup (Supabase)

1. Open your **Supabase Dashboard** → **SQL Editor**.
2. Create a new query, copy the contents of the database setup script in the project root: `supabase_setup.sql` and run it. This will automatically:
   - Create tables (`users`, `chats`, `chat_members`, `messages`, `blocked_users`, `call_logs`).
   - Configure Row Level Security (RLS) policies and security helper functions.
   - Register tables to the publication for WebSocket-based Realtime notifications.
   - Configure the public `media` storage bucket for file uploads.

### Application Configuration

1. Rename the `.env.example` file in the `frontend` directory to `.env` (or update environment variables in your config files) with your credentials:
   ```env
   SUPABASE_URL=your_supabase_url
   SUPABASE_ANON_KEY=your_supabase_anon_key
   EMAILJS_SERVICE_ID=your_emailjs_service_id
   EMAILJS_TEMPLATE_ID=your_emailjs_template_id
   EMAILJS_PUBLIC_KEY=your_emailjs_public_key
