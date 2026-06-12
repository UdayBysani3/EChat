# Technical Architecture & Product Blueprint: Emerald Chat

## 1. COMPONENT ARCHITECTURE
- **Frontend Client:** Flutter (iOS/Android) with BLoC for state management.
- **API Gateway:** NestJS (TypeScript) handles REST/Websocket routing and rate limiting.
- **Real-time Layer:** Native WebSockets + Redis Pub/Sub for horizontal scaling.
- **Database Layer:** 
  - **PostgreSQL:** User profiles, relations, message metadata.
  - **TimescaleDB:** High-performance message history.
- **Cache:** Redis for presence, typing states, and session tokens.
- **Media:** AWS S3 + Cloudflare Images/CDN.
- **Calling:** WebRTC with custom STUN/TURN (Twilio backup).

## 2. TECH STACK RATIONALE
- **Flutter vs. React Native:** Native-level performance, superior pixel-level control (Canvas API), and single-codebase consistency for complex 60fps animations.
- **NestJS vs. Django:** Event-driven, non-blocking I/O is native to Node.js, making it significantly more efficient for high-concurrency socket connections.
- **PostgreSQL/TimescaleDB vs. MongoDB:** Strict relational integrity for E2EE key mapping and superior time-series indexing for multi-billion message scales.

## 4. DATABASE DESIGN (RELATIONAL)
### Users
- `id`: UUID (PK)
- `email`: String (Unique)
- `public_key_bundle`: JSONB (X3DH Pre-keys)
- `presence`: Enum (online, away, offline)

### Messages
- `id`: BigInt (PK, TimescaleDB Hypertable)
- `room_id`: UUID (FK)
- `sender_id`: UUID (FK)
- `encrypted_payload`: Text
- `status`: Enum (sent, delivered, seen)
- `created_at`: Timestamp

## 8. SECURITY & E2EE
- **X3DH (Extended Triple Diffie-Hellman):** For asynchronous key agreement.
- **Double Ratchet:** For per-message perfect forward secrecy.
- **Storage:** Private keys stored in Android Keystore / iOS Keychain; never leave the device.

## 12. PROJECT STRUCTURE
### Frontend (Flutter)
- `lib/core`: Networking, Encryption, Utilities.
- `lib/features/chat`: Data (Repos), Domain (Entities/Usecases), Presentation (BLoC/UI).
### Backend (NestJS)
- `src/modules/auth`: JWT, Refresh Strategy.
- `src/modules/chat`: Socket handlers, Room management.

## 13. ROADMAP
- **Phase 1 (W1-4):** Auth, PostgreSQL/Redis setup, basic REST API.
- **Phase 2 (W5-8):** WebSocket implementation, one-to-one texting, message status.
- **Phase 3 (W9-12):** E2EE Integration (Double Ratchet), Media S3 upload.
- **Phase 4 (W13-16):** WebRTC Calling, CI/CD, Production Hardening.
