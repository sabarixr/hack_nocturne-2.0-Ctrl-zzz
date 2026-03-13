# SignBridge Backend

Django 5 + Strawberry GraphQL backend for the SignBridge emergency communication app.

## Stack

| Layer | Technology |
|---|---|
| Framework | Django 5, Django Channels |
| API | Strawberry-Django (GraphQL + WebSocket subscriptions) |
| Database | PostgreSQL 16 |
| Cache / Pub-Sub | Redis 7 |
| Auth | PyJWT (HS256, Bearer token) |
| AI | Google Gemini (`gemini-pro`) |
| Sign inference | TFLite / LSTM (or bypass dummy) |
| Container | Docker Compose |

## Quick start

```bash
cp .env.example .env          # fill in secrets
docker compose up --build
```

The backend starts on `http://localhost:8000/graphql`.

On first boot it:
1. Runs `migrate`
2. Seeds 60 signs via `loaddata apps/signs/fixtures/signs.json`
3. Starts Daphne (ASGI/WebSocket)

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `SECRET_KEY` | `django-insecure-change-me` | Django secret |
| `JWT_SECRET_KEY` | `jwt-secret-change-me` | JWT signing key |
| `DATABASE_URL` | `postgresql://signbridge:signbridge@db:5432/signbridge` | Postgres DSN |
| `REDIS_URL` | `redis://redis:6379/0` | Redis DSN |
| `GEMINI_API_KEY` | _(empty)_ | Google AI API key |
| `BYPASS_MODEL` | `true` | Skip LSTM inference, return dummy result |
| `TFLITE_MODEL_PATH` | `models/sign_classifier.tflite` | TFLite model path |
| `LSTM_MODEL_PATH` | `models/sign_lstm.h5` | LSTM model path |
| `NOTIFY_EMERGENCY_CONTACTS` | `false` | Enable Twilio SMS notifications |

## GraphQL API overview

### Auth
| Operation | Type | Description |
|---|---|---|
| `register` | Mutation | Create account, returns JWT |
| `login` | Mutation | Authenticate, returns JWT |

### User / Profile
| Operation | Type | Description |
|---|---|---|
| `me` | Query | Current user profile |
| `updateProfile` | Mutation | Update name/phone/language |
| `addEmergencyContact` | Mutation | Add emergency contact |
| `saveCalibrationProfile` | Mutation | Save calibration data |

### Signs
| Operation | Type | Description |
|---|---|---|
| `signDatabase` | Query | All signs (filterable by category, search, is_critical) |
| `sign` | Query | Single sign by ID |
| `criticalSigns` | Query | Emergency-priority signs |

### Emergency Call
| Operation | Type | Description |
|---|---|---|
| `startCall` | Mutation | Create call (status: CONNECTING) |
| `activateCall` | Mutation | Mark call ACTIVE |
| `submitFrame` | Mutation | Submit frame data; auto-computes urgency |
| `endCall` | Mutation | End call |
| `postCallReport` | Mutation | Update outcome notes |
| `activeCall` | Query | Current active call |
| `callHistory` | Query | Paginated ended calls |
| `callReport` | Query | Aggregate report for a call |

### WebRTC Signaling
| Operation | Type | Description |
|---|---|---|
| `initiateWebrtc` | Mutation | Submit SDP offer |
| `submitWebrtcAnswer` | Mutation | Submit SDP answer |
| `addIceCandidate` | Mutation | Add ICE candidate |

### Practice Mode
| Operation | Type | Description |
|---|---|---|
| `startPractice` | Mutation | Begin practice session |
| `submitSignAttempt` | Mutation | Run inference (bypass or TFLite), update profile accuracy |
| `endPractice` | Mutation | Complete session |
| `practiceSessions` | Query | User's practice history |
| `sessionAttempts` | Query | Attempts for a session |

### Bystander Mode
| Operation | Type | Description |
|---|---|---|
| `startBystanderSession` | Mutation | Link bystander to call |
| `sendBystanderMessage` | Mutation | Send a message |
| `requestAiSuggestion` | Mutation | Get Gemini suggestion (max 5/session) |
| `endBystanderSession` | Mutation | Close session |

### Subscriptions (WebSocket)
| Subscription | Description |
|---|---|
| `emergencyCallUpdated(callId)` | Real-time call status + urgency score |
| `operatorMessageReceived(callId)` | Incoming operator messages |
| `bystanderMessageStream(sessionId)` | Bystander chat + AI messages |
| `webrtcSignaling(callId)` | ICE candidate exchange |

WebSocket endpoint: `ws://localhost:8000/graphql`

## Urgency scoring

`urgency_score = 0.25×fear + 0.30×pain + 0.20×panic + 0.10×speed_norm + 0.15×tremor + 0.15×critical_sign_bonus`

Scores ≥ 0.75 on an ACTIVE call auto-transition to `EMERGENCY_TRIGGERED`.

## Sign inference bypass

Set `BYPASS_MODEL=true` (default) to skip real model inference and return `{label: <expected>, confidence: 0.85}`. Set to `false` and provide `TFLITE_MODEL_PATH` for real inference.
