# Expresto + Hack Nocturne Backend Integration Report

Date: March 13, 2026
Repo: C:\dev\hack_nocturne-2.0-Ctrl-zzz
Scope: Connect the Flutter app in expresto/ to the Django GraphQL backend in backend/

## 1) What exists right now

Backend (backend/):
- Django 5 + Strawberry GraphQL + Channels
- GraphQL endpoint: http://localhost:8000/graphql
- WebSocket endpoint: ws://localhost:8000/graphql
- Auth: Bearer JWT in Authorization header
- Docker-first startup via docker compose

Frontend (expresto/):
- Flutter app with page-based structure under expresto/lib/pages/
- Uses local/mock style models/data today
- No GraphQL client dependency yet

## 2) Target integration architecture

Use one shared API layer in Flutter:
- HTTP GraphQL for queries/mutations
- WebSocket GraphQL for subscriptions
- JWT stored locally after login/register
- Repository layer per domain (users, emergency, practice, bystander, signs)

Suggested Flutter layering:
- expresto/lib/core/config/backend_config.dart
- expresto/lib/core/network/graphql_client_provider.dart
- expresto/lib/core/auth/token_store.dart
- expresto/lib/data/repositories/*.dart
- expresto/lib/data/graphql/*.dart (operations + fragments)

## 3) Backend readiness checklist

1. Start backend stack:
   - from backend/: docker compose up --build
2. Confirm GraphQL is reachable:
   - http://localhost:8000/graphql
3. Confirm CORS supports Flutter origins:
   - set CORS_ALLOWED_ORIGINS in backend/.env for your app origins
   - include at least:
     - http://localhost:3000 (already default)
     - http://localhost:8080 (if Flutter web runs here)
     - http://127.0.0.1:8080
4. Confirm JWT secret and env values in backend/.env are set for local/dev

## 4) Flutter dependency additions

Add these to expresto/pubspec.yaml:
- graphql_flutter
- hive_flutter
- flutter_secure_storage
- web_socket_channel
- uuid (optional, for operation IDs/session IDs)

Then run:
- flutter pub get

## 5) Concrete connection steps in Expresto

Step A: Add backend config
- Keep host and endpoints centralized.
- Use localhost for Android emulator override (10.0.2.2) when needed.

Step B: Build auth token store
- Persist JWT on login/register.
- Read token on app startup.
- Clear token on logout or token decode failure.

Step C: Build GraphQL client provider
- HTTP link for normal ops
- WebSocket link for subscriptions
- Auth link injects Authorization: Bearer <token>
- Split link routes subscriptions to WS and rest to HTTP

Step D: Replace mock data feature-by-feature
- Start with low-risk paths:
  1) Auth (register/login/me)
  2) Signs (signDatabase, sign, criticalSigns)
  3) Profile (updateProfile, addEmergencyContact)
  4) Emergency flow (startCall, activateCall, submitFrame, endCall)
  5) Subscriptions for live updates

Step E: Add per-feature repository contracts
- Keep UI widgets/pages independent of GraphQL details.
- Return typed models mapped from GraphQL JSON.

## 6) Screen-to-backend operation mapping

Suggested mapping from current pages:
- expresto/lib/pages/profile.dart
  - me, updateProfile
- expresto/lib/pages/contacts.dart
  - addEmergencyContact
- expresto/lib/pages/lesson.dart
  - signDatabase, sign
- expresto/lib/pages/emergency.dart
  - startCall, activateCall, endCall, submitFrame
- expresto/lib/pages/live_call.dart
  - emergencyCallUpdated subscription
  - operatorMessageReceived subscription
  - webrtc signaling mutations/subscription
- expresto/lib/pages/practice.dart
  - startPractice, submitSignAttempt, endPractice
- expresto/lib/pages/bystander.dart
  - startBystanderSession, sendBystanderMessage, requestAiSuggestion
- expresto/lib/pages/call_history.dart
  - callHistory, callReport

## 7) Minimum implementation sequence (recommended)

Phase 1 (1 day):
- Add dependencies
- Add config + token storage + GraphQL client
- Wire login/register + me

Phase 2 (1 to 2 days):
- Integrate signs and profile/contact data
- Replace local mock reads on those pages

Phase 3 (2 to 3 days):
- Integrate emergency flow mutations and history/report queries
- Add robust error handling and retry strategy

Phase 4 (1 to 2 days):
- Add subscriptions (live call, bystander, signaling)
- Add reconnect and token-refresh fallback behavior

## 8) Known integration gotchas and fixes

1. Android emulator networking:
- localhost in emulator does not point to host machine backend.
- Use 10.0.2.2:8000 for Android emulator.

2. Web CORS:
- If Flutter web cannot call backend, update CORS_ALLOWED_ORIGINS and restart backend container.

3. Auth header format:
- Must be exactly Authorization: Bearer <token>

4. Subscription auth:
- Ensure the same JWT is sent in WebSocket connection payload/headers.

5. Local model bypass in backend:
- BYPASS_MODEL=true returns deterministic inference-like response.
- Keep it true for first integration pass.

## 9) Verification checklist

Backend health:
- GraphQL query works in browser/GraphQL playground
- Register/Login returns token

Frontend behavior:
- App can login and stay signed in after restart
- Profile page pulls real user data
- Emergency start/end persists in call history
- At least one live subscription updates UI in real time

## 10) Push-ready status for this request

Delivered in this repo:
- New folder: app/
- New report: app/EXPRESTO_BACKEND_JOIN_REPORT.md

This report is scoped to joining backend/ with expresto/ inside C:\dev\hack_nocturne-2.0-Ctrl-zzz.
