# Communal Meet

Conferences and chat for cooperatives. A cooperative holds audio/video meetings with its
members — an AGM, an executive sitting, a member consultation — and everyone in it has an
always-on group chat plus private chats with the people they share a cooperative with.

The group chat is not something a cooperative sets up. It exists from the moment the
cooperative does, and its roster follows the membership.

## What is where

| | |
|---|---|
| `PLAN.md` | the build: architecture, schema, routes, screens, execution order, verification |
| this repo | the Flutter client (`meet_mobile`) |
| `backend/meetsvc` (separate repo) | the BFF — rooms, tokens, chat, the WebSocket, push |

## The media plane is not ours

Meetings run on the ZeroRate platform (`~/Documents/freepass`), which Communal consumes as a
**merchant tenant**: a business on the merchant portal owning an app with the
`video_conference` service, whose live keys mint service tokens, TURN credentials and
per-merchant room names. Those keys live only in `meetsvc`; this app holds nothing
privileged. It sends a member's Communal JWT and gets back a room token, an SFU address and
ICE servers it did not choose.

`PLAN.md` has the full linkage. The portal's own browser client (`freepass/livekit-fe`) is the
reference implementation for room lifecycle, lobby admission and the in-call surface — read it
before rewriting a flow in Dart.

## Building it

**`BASE_URL` is not optional and there is no default.** A build without it compiles, installs
and launches, and then does nothing at all: `AppConfig.requireBaseUrl()` throws, and until
W94 that throw was above `runApp` — no splash, no error, just the launch window for as long as
anyone was willing to hold the phone. It now reaches a screen that says so, which is a good
deal better than silence and still not a build anybody wants.

```sh
# on a device, against the local stack. 8989 is local-gateway.
flutter run \
  --dart-define=APP_ENV=development \
  --dart-define=BASE_URL=http://$(hostname -I | awk '{print $1}'):8989

# an APK for a handset that is not on this wifi
flutter build apk --release \
  --dart-define=APP_ENV=development \
  --dart-define=BASE_URL=http://185.113.249.61:8989
```

The dev address has to be the **host's** LAN IP, and this machine's roams — `hostname -I`
rather than a number typed once and pasted after. `127.0.0.1` is the phone, not the laptop.
A release build on this box takes around 45 minutes; a debug one launches in about a third of
the time on the device but blocks its main thread for ~2.6s of JIT on the way in, so do not
judge a launch by it.

## Status

Chat and the meeting are built and on a handset; 1:1 calls, recording and scheduling are not.
`PLAN.md` is the design; W81, W91 and W94 in the platform's `OUTSTANDING.md` track the state
row by row. No media session has been exercised between two devices yet — that needs a
meetsvc deployed from `46fc36d`, and nothing has deployed meetsvc anywhere.
