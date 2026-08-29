# Communal Meet — conferencing + chat for cooperatives

## Context

Cooperatives currently have no way to meet their members. They can transact, invoice and
message by SMS, but an AGM, an executive meeting or a member consultation happens off
platform. **Communal Meet** closes that: a standalone mobile app where a cooperative holds
audio/video conferences with its members, plus always-on chat — one group chat per
cooperative (auto-created) and 1:1 private chats between people who share a cooperative.

The media plane is not being built. It already exists in `~/Documents/freepass` (the ZeroRate
platform). Communal consumes it **as a merchant tenant**, exactly the way the merchant
portal's own managed conference (`livekit-fe`) does.

### How the merchant linkage actually works (the open question)

Communal is a *business* on the ZeroRate merchant portal. That business owns a **merchant
app** (Multimedia Streaming category) with the `video_conference` service enabled, which
carries a `livePublicKey` / `liveSecretKey`. Those keys are the whole linkage — three uses:

1. **Service identity.** `POST {zerorate-authsvc}/auth/m2m/token` with
   `grant_type=client_credentials`, `client_id=livePublicKey`, `client_secret=liveSecretKey`
   returns a 15-minute JWT stamped with our `businessId`
   (`zerorateauthsvc/src/auth/m2m/m2m.service.ts`). That JWT is the Bearer for every
   media-manager call.
2. **TURN attribution.** `POST {coturn}/v1/auth/token {public_app_key}` → admin JWT →
   `POST /v1/credentials {identity}` → ephemeral ICE servers. Relay usage bills to that app
   (pattern: `zeroratemerchantportal/lib/coturn.ts`).
3. **Tenancy.** Every room is namespaced `<businessId>--<room>` and every identity is
   `<businessId>--<who>`. Un-namespaced rooms leak across merchants — the portal learned this
   the hard way (see the comments in `zeroratemerchantportal/actions/rtc.actions.ts`).

The keys **never leave our backend**. So Communal needs a BFF, and that is the new service
below. Recordings written through the manager's file egress land in Communal's own cold
bucket and surface in the portal's media library — which is where our own staff see usage.

Nothing in `freepass` is modified by this work.

### What the platform gives us vs. what we build

| Capability | Source |
|---|---|
| SFU rooms, ≤200 participants, room tokens, lobby/knock, mute/kick, file+RTMP egress | `zeroratewebrtckit/livekit-manager` — `POST /token`, `/rooms/*`, `/egress/*`, `/calls/*` |
| 1:1 ringing (caller→callee signalling) | manager `POST /calls/initiate|accept|decline|end` |
| TURN relay | `turns-stg.soa.africa` (`/v1/auth/token`, `/v1/credentials`) |
| In-call chat | LiveKit data channel, ephemeral — `livekit-fe/src/components/ChatRail.tsx` |
| **Persistent group + private chat** | **ours — does not exist anywhere in `freepass`** |
| **Coop membership, identity, auth, push** | **ours — the Communal fleet** |

`livekit-fe` (the portal's browser conference client) is the reference implementation for
room lifecycle, lobby admission, green room, recording start/finalise and grid behaviour.
Read it before writing the Flutter equivalents; do not re-derive the flows.

## Decisions taken

- **New standalone Flutter app** `meet_mobile/`, alongside `mobile/`, `collector_mobile/`,
  `sms_mobile_app/`. Structured so its feature code can later be lifted into `mobile/`.
- **Native `livekit_client`** — Flutter joins the SFU directly over the LiveKit protocol, the
  same wire `livekit-fe` uses. The JS `zerorate-rtc-sdk` is not used at all (it is a
  web/React-Native SDK; its P2P `connectra_basic` path caps at 10 and we need 200).
- **WebSocket chat** in the new service, with FCM push when the socket is down.
- Merchant app keys already exist.

## Architecture

```
meet_mobile (Flutter)                     meetsvc :8092 (Go, new)                external
────────────────────                      ──────────────────────                 ────────
member/coop-admin JWT ──┐
  GET  /api/meet/v1/spaces ──────────────▸ JWKS verify (guard, coop_id, sub)
  POST /api/meet/v1/meetings ────────────▸ host check: coop_administrators
  POST /meetings/{id}/join ──────────────▸ m2m token ─────────────────────────▸ zerorate authsvc
                                           manager POST /token (room,identity) ▸ livekit-manager
                                           coturn /v1/credentials ───────────▸ turns-stg
  ◂── { token, livekitUrl, room, iceServers }
LiveKit Room ══════════ wss (media) ══════════════════════════════════════════▸ LiveKit SFU
  WS   /api/meet/v1/ws ─────────────────▸ hub: message.new / typing / read /
                                                 call.ring / meeting.started
                                           publish notifications.push ───────▸ notificationsvc → FCM
                                           consume cooperative.created,
                                                   member.added/removed ◂─────  RabbitMQ (communal)
```

All app traffic goes through `local-gateway` (dev) on the existing `/api/…` origin — one new
prefix, `/api/meet/`.

## Scope

**In v1:** coop group chat (auto-created, backfilled), 1:1 chat between co-members, group
video/audio meetings with lobby + host controls, 1:1 calls with ring/answer over FCM,
scheduled meetings, in-call chat, recording (host opt-in), push notifications, host rights
for coop admins.

**Deferred, called out explicitly:** guest/external invitees (the portal's
`conference-guest-join` + `CONFERENCE_INVITE_SECRET` path), chat attachments/voice notes,
livestream mode for cooperatives over 200 members (interactive ceiling is 200 —
`connectra_plus`; larger AGMs need RTMP/HLS egress), a host console in the coop web
dashboard, E2EE (SFU path is DTLS-hop-by-hop, not end-to-end), recording playback in-app.

## Part A — `backend/meetsvc` (new Go service, port 8092)

Scaffold from `backend/go-service-template`; follow `backend/support-svc` for everything the
template omits (chi routing, `internal/db` + migrations, `ReassertRepeatable`, ratelimit,
docs, broker consumers). Module `github.com/communal/meetsvc`.

### Schema — `internal/db/migrations/000001_create_meet_tables.sql`

`meet_` prefix, in the shared `communal` database. Note the fleet's prefix trap: authsvc's
default connection prepends `tbl_`, so these are only ever touched from Go/`mysql_no_prefix`.

- `meet_conversations` — `id`, `kind` (`coop_group`|`dm`), `cooperative_id` (null for dm),
  `title`, `posting_policy` (`all_members`|`admins_only`, default `all_members`),
  `dm_key` (sorted `profileA:profileB`, unique — makes DM creation idempotent),
  `last_message_id`, `last_message_at`, timestamps.
- `meet_conversation_participants` — `conversation_id`, `profile_id`, `role`
  (`member`|`admin`), `last_read_message_id`, `last_read_at`, `muted_until`, `joined_at`,
  `left_at`. Unique `(conversation_id, profile_id)`.
- `meet_messages` — `id`, `conversation_id`, `sender_profile_id` (null for system),
  `kind` (`text`|`system`|`call_event`), `body`, `reply_to_id`, `client_msg_id`
  (unique per conversation — retry-safe sends), `created_at`, `edited_at`, `deleted_at`.
  Index `(conversation_id, id DESC)` for keyset paging.
- `meet_meetings` — `id`, `cooperative_id`, `code` (short, URL-safe), `room_name`
  (`<businessId>--<coop>-<code>`, must satisfy the manager's `^[a-zA-Z0-9_-]{3,64}$`),
  `title`, `style` (`meeting`|`call`), `host_profile_id`, `status`
  (`scheduled`|`live`|`ended`), `lobby_enabled`, `recording_enabled`, `recording_path`,
  `scheduled_for`, `started_at`, `ended_at`.
- `meet_meeting_participants` — `meeting_id`, `profile_id`, `identity`, `role`
  (`publisher`|`subscriber`|`lobby`), `joined_at`, `left_at`, `admitted_by`.
- `meet_calls` — `id`, `caller_profile_id`, `callee_profile_id`, `cooperative_id`,
  `manager_call_id`, `room_name`, `video`, `status`
  (`ringing`|`accepted`|`declined`|`missed`|`ended`), timestamps.

Time handling per the fleet rule: no Go `time.Time` bound into a comparison — write with
`NOW()` and compare in SQL, in the column's own clock (see `go_mysql_clock_mismatch`).

### `internal/zerorate` — the platform client

One package, so there is one answer to "which SFU / which credential":

- `m2m.go` — cached client-credentials token (mint at ~13 min, refresh margin, single-flight
  like `coturn.ts`'s `adminJwt`).
- `manager.go` — `GenerateToken(room, identity, role, name)`, `CreateRoom`, `ListParticipants`,
  `AdmitParticipant`, `MutePublishedTrack`, `RemoveParticipant`, `StartFileEgress`,
  `InitiateCall/Accept/Decline/End`.
- `coturn.go` — port `issueIceServers` from `zeroratemerchantportal/lib/coturn.ts` verbatim in
  behaviour, **including that it never throws**: a TURN failure must not deny a meeting.
- `sfu.go` — resolve the SFU ws URL: pinned `LIVEKIT_WS_URL`, else discover via
  `POST /calls/initiate` and cache for the process (`livekit-fe` README documents why
  `/token` alone is not enough).
- `naming.go` — `RoomName(coopID, code)` and `Identity(profileID)`, both derived
  server-side from the verified JWT. A client-supplied room or identity is a cross-tenant
  primitive; it is never accepted as input.

### Routes — `/api/meet/v1/…` (all behind `auth.Middleware(jwks, …)`)

- `GET  /spaces` — the caller's cooperatives (from `coop_member_cooperatives` joined to
  `tbl_cooperatives`), each with its group conversation, unread count, live-meeting flag,
  and whether the caller is a host (`coop_administrators`).
- `GET  /conversations`, `GET /conversations/{id}/messages?before=&limit=`,
  `POST /conversations/{id}/messages`, `POST /conversations/{id}/read`,
  `POST /conversations/dm` (idempotent on `dm_key`; refuses two people who share no
  cooperative), `POST /conversations/{id}/mute`.
- `GET  /meetings?cooperative=`, `POST /meetings` (host only), `POST /meetings/{id}/join`
  → `{token, livekitUrl, room, iceServers, role}`, `POST /meetings/{id}/end`,
  `GET  /meetings/{id}/lobby`, `POST /meetings/{id}/lobby/{profileId}/admit`,
  `POST /meetings/{id}/participants/{identity}/{mute|remove}`,
  `POST /meetings/{id}/recording/start|finalize`.
- `POST /calls`, `POST /calls/{id}/{accept|decline|end}`, `GET /calls/recent`.
- `GET  /ws` — the chat/presence socket.
- `GET  /health`, `GET /docs`.

**Authorisation:** host = `guard == "coop-admin"` with a matching `coop_id`, **or** a member
whose `profile_id` is in `coop_administrators` for that cooperative. Plain members join and
chat. Remember `coop_id` is a **string** (`"Tco-8934"`) — `*string`, never an integer
(`jwt_coop_id_is_string`).

### WebSocket hub — `internal/hub`

`gorilla/websocket`. Per-connection: verify the same JWT (query param or `Sec-WebSocket-Protocol`
bearer), resolve profile, subscribe to that profile's conversation ids. Server→client frames:
`message.new`, `message.read`, `typing`, `presence`, `call.ring`, `call.cancelled`,
`meeting.started`, `meeting.ended`. Client→server: `typing`, `read`, `ping`. In-process
fan-out for now with a documented seam for a Redis pub/sub relay when meetsvc runs more than
one replica — a two-replica deploy silently splits the hub otherwise.
`local-gateway`'s `httputil.ReverseProxy` already forwards upgrades, so no gateway change
beyond the prefix.

### Events — `internal/events`

- Consume `cooperative.created` → create that cooperative's default group conversation and
  seed the president as `admin`. (Published at
  `cooperative-svc/internal/cooperative/service_cooperative.go:311`.)
- Consume `member.added` / `member.removed` → add/remove the participant and post a `system`
  message. (`service_member.go:389,465`.)
- **Backfill on boot** for cooperatives that predate the service, in the shape of
  `support-svc/internal/support/backfill.go` — idempotent, logged, converges however the
  services happen to start.
- Publish `notifications.push` envelopes on the **notifications broker** (a separate
  host/vhost), reusing `publishNotification` + `stampNotifEnvelope` from
  `cooperative-svc/internal/cooperative/service_settings.go:290`. Device tokens come from
  `tbl_members_profiles.device_token`.

⚠️ Dev `.env` points the notifications broker at the **production** host
(`dev_env_points_at_production_broker`) — a local publish is a real push to a real person.
Ring/push work is developed with `NOTIFICATIONS_RABBITMQ_URL` unset (publishes become no-ops)
until a device is deliberately enrolled.

### One small change outside meetsvc

`notificationsvc/app/Services/FirebaseService.php` always sends a `notification` block and
sets no priority. An incoming call needs a **data-only, high-priority** message
(`android.priority=high`, `apns-push-type` + `content-available`) or it will not wake the app
to ring. Add an optional `push_options` passthrough (`priority`, `data_only`, `voip`) —
additive, existing callers unaffected.

## Part B — `meet_mobile/` (Flutter)

Match `collector_mobile`'s conventions: `lib/{core,data,state,screens,widgets}`, `flutter_bloc`,
`dio`, `flutter_secure_storage`, `AppConfig` via `--dart-define` (`APP_ENV`, `BASE_URL`),
`google_fonts`, `flutter_screenutil`. Primary colour `#742CE7` on every action/approve
control (`app_primary_color_purple`).

New dependencies: `livekit_client`, `flutter_webrtc` (transitive), `permission_handler`,
`firebase_core` + `firebase_messaging`, `flutter_callkit_incoming`, `wakelock_plus`,
`web_socket_channel`.

Screens:

1. **Auth** — phone + 6-digit PIN against `POST /api/v1/login-checker` → `/api/v1/login`
   (the shared route already serves members *and* coop admins, so one app covers both).
   Register the FCM token via `POST /api/v1/profile/device-token`.
2. **Spaces / home** — cooperatives from `GET /spaces`; each row opens the group chat and
   shows a live-meeting banner. Recent DMs and recent calls below.
3. **Chat** — group and DM: keyset-paged history, optimistic send keyed by `client_msg_id`,
   typing indicators, read pointers, day separators, system messages, offline outbox in
   `sqflite`/`shared_preferences`. `admins_only` conversations hide the composer for members.
4. **Green room** — camera/mic preview + device pick before joining, per
   `livekit-fe/src/components/GreenRoom.tsx`.
5. **Meeting stage** — paged grid (12/page, mirroring `livekit-fe/src/lib/grid.ts`),
   active-speaker, screen-share stage, in-call chat over the LiveKit data channel (same
   `{type:"chat",sender,message}` payload as `ChatRail`, so a Flutter client and a browser
   client interoperate), raise hand, host controls (mute/remove/admit), recording toggle
   with the announcement `livekit-fe` already makes.
6. **Waiting room** — lobby role token; poll admission.
7. **Call UI** — WhatsApp-style full-bleed active speaker + self PiP for 1:1; ring via
   `flutter_callkit_incoming` driven by the data push, answer → `POST /calls/{id}/accept`
   → join the room.
8. **Scheduling** — host creates a meeting with a title and time; members see it in the
   space and get a push at start.

The client holds **nothing privileged**: no app key, no business id, no SFU address it chose
itself. It sends its member JWT and receives `{token, livekitUrl, room, iceServers}`.

Signing/release: reuse the fleet's **single unified keystore as repo-level secrets** — do not
add env-scoped `ANDROID_*`, which silently shadows it (`mobile_signing_unified_keystore`).

## Part C — wiring

- `backend/local-gateway/main.go` — `meet := mustProxy(envOr("MEET_URL", "http://127.0.0.1:8092"))`
  and `{"/api/meet/", meet}`; extend the startup log line.
- `backend/dev-start.sh` / root `dev-start.sh` — start meetsvc on 8092.
- meetsvc env: `DB_DSN`, `JWKS_URL`, `RABBITMQ_URL`, `NOTIFICATIONS_RABBITMQ_*`,
  `ZR_M2M_TOKEN_URL`, `ZR_CLIENT_ID`, `ZR_CLIENT_SECRET`, `ZR_MANAGER_BASE_URL`,
  `COTURN_API_BASE_URL`, `ZR_APP_PUBLIC_KEY`, `ZR_BUSINESS_ID`, `LIVEKIT_WS_URL`.
  Intra-host URLs use `127.0.0.1`, never a roaming LAN IP (`env_dev_ip_roams`).
- `.github/workflows` for meetsvc + meet_mobile copied from support-svc / collector_mobile.
  Actions billing has been intermittently blocked — a 3-second zero-step "failure" is the
  biller, not the commit (`deploy_actions_billing_block`).

## Part D — task tracking

Before any code: add a **Communal Meet** section to `OUTSTANDING.md` with every item below as
a checkbox, and keep it current as work lands. Nothing gets closed by listing leftovers in a
chat message (`feedback_keep_a_task_track`).

## Execution order

1. `OUTSTANDING.md` section + meetsvc scaffold, health, gateway route, dev-start.
2. Schema + repositories + `/spaces`.
3. Chat: REST + WebSocket hub + push; `cooperative.created` / `member.*` consumers + backfill.
   → *first demoable slice: default group chat exists for every cooperative.*
4. `internal/zerorate` + meetings: create/join/end, lobby, host controls.
5. Flutter: auth → spaces → chat (against step 3).
6. Flutter: green room → meeting stage → in-call chat → host controls.
7. 1:1 calls: ring push, CallKit, accept/decline; `FirebaseService` `push_options`.
8. Recording + scheduling + polish.

## Verification

**Platform reachable** — `docker compose up` in `~/Documents/freepass/zeroratewebrtckit`
(LiveKit `:7880`, manager `:8880`, redis `:6379`). Confirm the merchant credentials before
anything else:

```
curl -s $ZR_M2M_TOKEN_URL -H 'Content-Type: application/json' \
  -d '{"grant_type":"client_credentials","client_id":"'$ZR_CLIENT_ID'","client_secret":"'$ZR_CLIENT_SECRET'"}'
# → access_token + businessId. `invalid_client` = the app is disabled or the keys are stale.
curl -s $ZR_MANAGER_BASE_URL/token -H "Authorization: Bearer $TOK" \
  -d '{"room":"<bid>--smoke-1","identity":"<bid>--m1","role":"publisher"}'
```

**meetsvc** — `go build ./... && go test ./...`; table-driven tests for room-name/identity
derivation, host authorisation, `dm_key` idempotency, `client_msg_id` replay, and the
`cooperative.created` consumer + backfill (integration-tagged, like support-svc's).
Then by hand: publish a synthetic `cooperative.created` to the local `communal` exchange and
assert a group conversation appears; `wscat` two sockets and assert a `POST /messages` from
one arrives as `message.new` on the other.

**End to end (the real test — needs two devices)** —
`flutter run --dart-define=APP_ENV=development --dart-define=BASE_URL=http://<host-lan-ip>:8989`
on two phones, two members of the same cooperative:
1. Both see the cooperative's group chat with no setup; messages cross in under a second and
   survive killing the app (offline outbox + history).
2. The coop admin starts a meeting; the other joins from the banner; audio and video both
   ways, with `iceServers` present in the join response (confirm relay by killing the LAN
   route to the SFU).
3. Lobby on: the member waits, the host admits, media starts only after admission.
4. Host mutes and removes the member; both take effect on the device.
5. 1:1 call: callee's screen is off — CallKit rings, answer connects.
6. Recording: start, end the meeting, confirm the object exists in the merchant's bucket and
   appears in the portal's media library.

Cross-client check worth doing once: join the same room from `livekit-fe` in a browser and
from Flutter, and exchange in-call chat both ways — that proves the data-channel payload
matches rather than assuming it.

## Risks

- **200-participant ceiling.** Any cooperative larger than that cannot hold an interactive
  AGM. The fix is livestream mode (RTMP/HLS egress) and it is not in v1 — worth confirming
  the largest real cooperative before step 4.
- **No tenant check on the manager.** `JWTMiddleware` verifies only the signature and the
  relay accepts whatever room a caller names, so our `<businessId>--` namespacing is the
  *only* thing keeping meetings apart. That is a platform-side gap the portal has documented;
  our side must never let a room name arrive from a client.
- **Ring latency** goes Go → RabbitMQ → Laravel consumer → FCM. If it proves too slow, the
  fallback is meetsvc holding its own FCM service account for ring pushes only.
- **Hub is single-replica** until the Redis relay seam is filled in.
