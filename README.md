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

## Status

Planned, not yet built. `PLAN.md` is the current state; W81 in the platform's
`OUTSTANDING.md` tracks it.
