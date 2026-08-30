# Communal Meet — the app's design

`PLAN.md` says what gets built and in what order. This says what it looks like, what it says,
what happens when it fails, and why each of those is the way it is. Every screen below is
specified to the point where two people building different parts of it would produce the same
app.

Wireframes are ASCII, drawn at roughly a phone's proportions. They fix layout, hierarchy and
order — not pixels. The pixels are the tokens in §3, and they are exact.

---

## 1. Who this is for, and on what

A cooperative member in Nigeria, on a mid-range Android phone, on mobile data that drops in
lifts and rural branches. Some of them are the cooperative's officers, and those people hold
meetings; everyone else attends them. A good few members are over fifty and reading the screen
at arm's length.

Three consequences that run through every decision below:

- **The network is assumed to be bad.** Nothing in the app blocks on a request when it can show
  what it already has. A message typed offline is a message sent, and the app says so.
- **Type is large and contrast is real.** Body text is 15pt with generous line height, taps are
  48dp, and no state is communicated by colour alone.
- **Data costs money.** Video defaults to a resolution the SFU can downshift, the app does not
  autoplay anything, and it does not poll while backgrounded.

Two devices, one account: a person may be signed in on a phone and a tablet. Read state is
server-side (`last_read_seq`) precisely so the second device does not show a badge for something
already read.

## 2. The three jobs, and the one promise

| Job | Frequency | Where it lives |
|---|---|---|
| Read and answer messages | many times a day | **Chats** tab |
| Attend or hold a meeting | weekly to monthly | **Cooperatives** tab |
| Call one person | occasionally | **Calls** tab, and the DM header |

The promise the whole product rests on, in the user's words: *the group chats are created by
default for any new cooperative*. In design terms that means **the app never contains a "create
group chat" button, a "join chat" flow, or an empty state that asks a member to set anything
up.** A member who signs in for the first time is already in their cooperative's chat. If the
app ever shows a cooperative with no conversation, that is a bug, not a state to design for —
and the backend keeps that true in three independent places (consumer, read path, sweep).

### 2.1 Where this revises `PLAN.md`

The plan proposed a **Spaces / home** screen — cooperatives first, with recent DMs and calls
beneath. That is the wrong home, and it is worth saying why before the screens assume otherwise.

Opening the app to read a message is the frequent act, by an order of magnitude. A
cooperative-first home puts a container in front of it: tap the cooperative, then tap the chat.
The container adds nothing, because the conversation row already names the cooperative. And a
member of one cooperative — most members — would be looking at a list of one.

So: **a single merged conversation list is the home**, exactly as `GET /conversations` already
returns it, and cooperatives get their own tab where a live meeting can be as loud as it needs to
be. Recent calls move to a third tab because a call history has nowhere else to live and a
"start a call" entry point needs an address.

## 3. Design tokens

The member app uses Sen; the collector app uses Inter. Meet uses **Inter**, with the collector's
palette and shape language verbatim. Meet is an app for *reading* — a chat thread is mostly
small text in long runs — and Inter is a text face at 13–15pt where Sen is a display face. The
purple, the radii, the hairline-border-instead-of-shadow card and the 52dp filled button are
identical to `collector_mobile/lib/core/theme.dart`, so the two apps look like they came from
the same company because they did.

### 3.1 Colour — light surfaces (chrome, lists, chat)

Lifted unchanged from the fleet. `#742CE7` is the action colour on every platform surface.

| Token | Hex | Used for |
|---|---|---|
| `primary` | `#742CE7` | actions, own chat bubble, active tab, links |
| `primaryDark` | `#5A1FBC` | pressed state |
| `primarySoft` | `#F1E9FE` | unread divider, host badge, selected row |
| `success` / `successSoft` | `#14804A` / `#E3F5EB` | live meeting, connected |
| `warning` / `warningSoft` | `#B25E09` / `#FDF3E7` | weak network, queued message |
| `danger` / `dangerSoft` | `#B42318` / `#FDECEA` | leave, decline, failed send |
| `ink` | `#14161A` | primary text |
| `muted` | `#6B7280` | secondary text, timestamps, placeholders |
| `line` | `#E5E7EB` | hairlines, bubble borders |
| `surface` | `#F7F7FB` | scaffold behind cards and bubbles |
| `white` | `#FFFFFF` | cards, app bar, incoming bubble |

### 3.2 Colour — the dark stage (green room, meeting, call)

The media surfaces are near-black in both light and dark mode, and so is the control bar. This
is not a theme; it is a constraint. A bright surround shifts the apparent colour of video next to
it, and a control bar that went white in light mode would put that bright edge back against the
picture. The reference client made the same call for the same reason.

| Token | Hex | Used for |
|---|---|---|
| `stage` | `#0B0B0F` | the ground behind all tiles |
| `tile` | `#16161C` | a participant tile with no video |
| `tileLine` | `#23232B` | tile border, control-bar divider |
| `bar` | `#16161C` | control bar, sheets over the stage |
| `onStage` | `#F5F5F7` | text and icons on the stage |
| `onStageMuted` | `#A1A1AA` | secondary text on the stage |
| `speaking` | `#742CE7` | 2dp ring on the active speaker's tile |
| `live` | `#E5484D` | the recording dot, and only that |

The recording indicator is the one place a red is used for something that is not an error, and it
is the only red on the stage — which is what makes it read as "you are being recorded" without a
label.

### 3.3 Sender colours in group chats

A group chat names its senders, and the name needs a colour to be scannable. Eight hues, all
tested to at least 4.5:1 on white, chosen by `profile_id.hashCode % 8` so a person is the same
colour in every conversation and on every device:

`#B4231F` `#0B6E4F` `#1F5FA8` `#8A4B00` `#6D28D9` `#A21CAF` `#0E7490` `#4D7C0F`

The colour is decoration on top of the name, never instead of it.

### 3.4 Type

Inter, via `google_fonts`. Sizes are logical pixels; the app is built with `flutter_screenutil`
as the collector app is, but **chat body text is not scaled down on small screens** — a smaller
phone gets fewer words per line, not smaller words.

| Style | Size / line | Weight | Used for |
|---|---|---|---|
| `display` | 24 / 32 | 700 | sign-in headline, empty-state headline |
| `title` | 18 / 24 | 700 | app bar title, sheet title |
| `subtitle` | 15 / 20 | 600 | conversation name, participant name |
| `body` | 15 / 22 | 400 | message text, paragraphs |
| `meta` | 13 / 18 | 400 | previews, subtitles, day separators |
| `caption` | 11 / 14 | 500 | timestamps, badges, tile labels |
| `mono` | 15 / 20 | 600 tabular | call and meeting durations |

Durations use tabular figures so a running timer does not jitter its own width.

### 3.5 Space, shape, elevation

- **Spacing scale**: 4, 8, 12, 16, 20, 24, 32. Screen padding 16. List rows 72 tall.
- **Radius**: button and field 12; card 14; message bubble 18, with 4 on the corner nearest the
  sender; bottom sheet 20 on the top corners; chip and avatar 999.
- **Elevation**: none. Separation is a `line` hairline, everywhere, as in the collector app. The
  two exceptions are surfaces that float over video — the admission card and the in-call sheet —
  which use a 24-blur black shadow at 40% because there is no hairline that reads against motion.
- **Bubble max width**: 78% of the viewport.
- **Touch targets**: 48×48 minimum, including icon buttons in the app bar and on the stage.

### 3.6 Motion

Short, and there is not much of it. These run on cheap phones while a video decoder is busy.

| Thing | Duration | Curve |
|---|---|---|
| tap / toggle feedback | 90ms | `easeOut` |
| state change, banner in/out | 150ms | `easeOut` |
| bottom sheet, page transition | 220ms | `easeOutCubic` |
| new message arriving | 120ms fade + 8dp rise | `easeOut` |
| tile joining/leaving the grid | 180ms | `easeOutCubic` |

No animation on first list paint — a staggered list on a slow phone reads as jank, not polish.
Everything above collapses to an instant cut when the platform reports reduce-motion.

### 3.7 Sound and haptics

Sound is quiet, under half a second, and fires during conversation — so the test of a good one is
that nobody asks to turn it off. The grammar is Google Meet's because it is already learned:
**join** is two ascending notes (arrival, resolved); **knock** is one note struck twice
(repetition is what a knock is, and it is unresolved on purpose because someone is waiting).

Unlike the browser client, these are three bundled ~4KB `.ogg` assets rather than synthesised
tones: Flutter has no Web Audio equivalent, and a Dart oscillator would cost more than the files.

| Sound | When | Suppressed when |
|---|---|---|
| `join.ogg` | someone enters the meeting | more than 8 already in, or your mic is hot |
| `knock.ogg` | someone knocks (host only) | never — it is the whole point |
| `ringback.ogg` | your outgoing 1:1 call is ringing | — |

The incoming ring is **not** ours: CallKit and the Android telecom UI own it, so the phone rings
the way that phone rings.

Haptics: a light impact on send, a medium impact on call connect and on leave, a selection click
on the mic/camera toggles. Nothing else.

---

## 4. Navigation

```
Splash (restore session)
├── no session ──▶ Sign in ──▶ Enter PIN ──▶┐
│                        └──▶ Verify code ──┤   (first-time / no PIN yet)
│                                           └──▶ Notification primer ──┐
└── session ───────────────────────────────────────────────────────────┴──▶ Home

Home (bottom navigation, 3 tabs)
├── Chats          ── Thread ── Conversation details ── Participants
│                              └── Green room ──▶ (host: start meeting from a group)
├── Cooperatives   ── Cooperative ── Schedule a meeting (host)
│                              └── Green room ── Waiting room ── Meeting ── Summary
└── Calls          ── Green room (call style) ── Call

Account sheet — from the avatar in the Chats app bar
Incoming call — a full-screen route pushed over anything, from CallKit
```

Bottom navigation, three items, labels always visible (icon-only navigation fails the
arm's-length reader):

```
┌──────────────┬──────────────┬──────────────┐
│  ⬤ Chats  ③  │   Coops      │   Calls      │
└──────────────┴──────────────┴──────────────┘
```

- **Chats** carries a badge: the sum of `unread` across conversations, capped at "99+".
- **Coops** carries a green dot, no number, when any cooperative has a live meeting. A count
  would be noise; the fact that something is on is the whole message.
- **Calls** carries a badge for missed calls since last visit.

Tabs keep their scroll position and their state. Tapping the active tab scrolls to top; tapping
it again at top jumps to the first unread conversation.

**Back**, on Android, always means "up one screen", and from a meeting it means "leave?" — never a
silent exit from a room. From the Home tabs it backgrounds the app.

---

## 5. Component inventory

What gets built once and used everywhere. Names are the widget names.

| Component | Shape |
|---|---|
| `AppScaffold` | app bar + offline banner slot + body, so the banner is never re-implemented |
| `OfflineBanner` | full-width `warningSoft` strip, 36 tall: "No connection. Messages will send when you're back." |
| `ConversationRow` | avatar / name / preview / time / unread pill / mute icon — 72 tall |
| `Avatar` | image, else initials on a hue from the sender palette; sizes 32, 40, 48, 96 |
| `MessageBubble` | body, timestamp, tick, optional sender name, optional quoted reply |
| `SystemLine` | centred `meta` text, no bubble, 8 above and below |
| `DaySeparator` | centred `meta` on a `line` rule |
| `UnreadDivider` | `primarySoft` strip with `primary` label, "12 new messages" |
| `Composer` | multiline field (1–5 lines) + send button; replaced by `PostingBlockedNotice` |
| `TypingIndicator` | three-dot animation plus a name, in the thread header |
| `CoopCard` | cooperative name, members, live/next meeting, primary action |
| `LiveMeetingBanner` | `successSoft`, pulsing dot, "Meeting in progress · 4 people" + Join |
| `HostBadge` | `primarySoft` chip, "Administrator" |
| `ParticipantTile` | video or avatar, name label, mic-off and weak-network glyphs, speaking ring |
| `ControlBar` | dark pill bar of circular 56dp buttons, always over the stage |
| `AdmissionCard` | floating card at the bottom of the host's stage |
| `PermissionNotice` | why-we-need-it card with a "Open settings" action |
| `EmptyState` | glyph, headline, one sentence, at most one action |
| `ErrorState` | same shape, with "Try again" |
| `Skeleton` | three grey bars at 40/70/55% width; used only where content is genuinely coming |

Every empty and error state uses the same two components, so an unhandled case is visibly
unhandled rather than a blank screen.

---

## 6. Screens

Each screen lists **what it is for**, its wireframe, its **states**, its **interactions**, the
**data** behind it (endpoints marked ✅ built or ◻ planned), and its **copy**, verbatim.

### 6.0 Splash

Restores the session and decides where to go. Nothing to see: the mark, centred, on white, with
no spinner for the first 400ms — a spinner that flashes for 200ms reads as a glitch.

- Session valid → Home. Session expired but a refresh token exists → refresh, then Home. No
  session → Sign in. Refresh fails → Sign in, with "Your session expired. Please sign in again."
- Data: `POST /api/v1/refresh-token` ✅, then `GET /api/meet/v1/me` ✅.
- Hard rule: the splash never waits on `/spaces` or `/conversations`. Home renders from cache and
  fills in.

### 6.1 Sign in

One account, the Communal one. A member signs in with the phone number or email they already
use; a cooperative's officer signs in the same way, because hosting rights come from
`coop_administrators`, not from a different login. There is no "sign up" — an account is created
by joining a cooperative, and that happens in the member app.

```
┌────────────────────────────────────────────┐
│                                            │
│   ⬤ Communal Meet                          │
│                                            │
│   Meet your cooperative                    │
│   Conferences and chat with the people      │
│   you save with.                            │
│                                            │
│   Phone number or email                    │
│   ┌────────────────────────────────────┐   │
│   │ 0803 000 0000                      │   │
│   └────────────────────────────────────┘   │
│                                            │
│   ┌────────────────────────────────────┐   │
│   │             Continue               │   │
│   └────────────────────────────────────┘   │
│                                            │
│   Use the same details as the Communal      │
│   app.                                      │
└────────────────────────────────────────────┘
```

- **States**: idle · validating (button shows a 20dp spinner, field locked) · not-found · offline
  (Continue disabled, banner shown).
- **Data**: `POST /api/v1/login-checker` with `user: "member"` ✅ → `next_step` decides the next
  screen: `enter_password` → PIN, `verify_otp` → Verify code.
- **Copy**: headline "Meet your cooperative". Not-found: "We could not find an account with those
  details. Check the number, or use the email you registered with." Offline: "You are offline.
  Connect to sign in."

### 6.2 Enter PIN

Six digits, on a numeric keypad, masked, auto-submitting on the sixth. One PIN across the whole
platform — the same six digits as the member app — so this screen must never imply a new one is
being set.

```
┌────────────────────────────────────────────┐
│  ←                                         │
│   Enter your PIN                           │
│   The 6-digit PIN you use for Communal.     │
│                                            │
│        ●   ●   ●   ○   ○   ○               │
│                                            │
│   Forgot your PIN?                          │
│                                            │
│                        (system keypad)      │
└────────────────────────────────────────────┘
```

- **States**: entering · verifying · wrong (boxes shake 200ms, haptic, digits cleared, attempts
  remaining shown when the server sends one) · locked out (shows when it unlocks) · offline.
- **Data**: `POST /api/v1/login` with `platform: "mobile_app"` ✅ → `{token, refresh_token,
  expires_in}` into `flutter_secure_storage`. Then `POST /api/v1/profile/device-token` ✅ with the
  FCM token, then `GET /api/meet/v1/me` ✅.
- **Forgot PIN** reuses the member app's three calls — the same PIN on the same account, so
  resetting it here resets it there, and the screen says so: "This changes the PIN you use for
  Communal everywhere."
- **Copy**: wrong PIN — "That PIN is not right." plus, when the server says so, "4 tries left
  before your account is locked."

### 6.3 Verify code

For an account that has never set a PIN. Six digits from SMS or email, a resend timer, then
straight into "Create your PIN" — which states plainly that this PIN is the one they will use
everywhere on Communal, because it is.

### 6.4 Notification primer

Shown once, immediately after the first successful sign-in, **before** the OS prompt. The OS
prompt is one-shot: a member who declines it never sees it again, and a member who does not know
what they are declining will decline it. So this screen exists to make the ask legible.

```
┌────────────────────────────────────────────┐
│                  ✉ ⬤                       │
│   Know when your cooperative meets          │
│                                            │
│   We will notify you about:                 │
│   • messages in your cooperative's chat     │
│   • meetings starting                       │
│   • incoming calls                          │
│                                            │
│   ┌────────────────────────────────────┐   │
│   │        Turn on notifications        │   │
│   └────────────────────────────────────┘   │
│              Not now                        │
└────────────────────────────────────────────┘
```

"Not now" is a real choice and costs nothing but pushes; the app works without it, and it is
re-offered from the Account sheet rather than nagged for. Camera and microphone are **not** asked
for here — they are asked in the green room, where the reason is on screen.

### 6.5 Chats — the home

Every conversation, group and private, most recently active first. This is `GET /conversations`
rendered directly; the ordering is the server's.

```
┌────────────────────────────────────────────┐
│  Chats                              ⬤ AE   │
├────────────────────────────────────────────┤
│ ┌──┐ Davoli Suit Coop            09:24  ⬤3 │
│ │DS│ Ebere: Meeting on Saturday, 10am.     │
│ └──┘                                       │
├────────────────────────────────────────────┤
│ ┌──┐ Dayo Adeyemi                 08:51    │
│ │DA│ Seen                          🔇      │
│ └──┘                                       │
├────────────────────────────────────────────┤
│ ┌──┐ Bulk Sheet Coop Ltd          Yesterday│
│ │BS│ Ada joined Bulk Sheet Coop Ltd.       │
│ └──┘                                       │
└────────────────────────────────────────────┘
```

- A **group** row shows the cooperative's name, its avatar as initials on a hue, and the preview
  prefixed with the sender's first name. A **DM** row shows the counterpart's name and avatar, and
  no prefix.
- `unread > 0` → a `primary` pill with the count, and the name and preview go 600 weight. A muted
  conversation shows the pill in `muted` instead and adds a 🔇 glyph: still counted, not shouted.
- Time is "09:24" today, "Yesterday", then "Sat", then "23/08".
- **States**:
  - *first run, nothing cached* — a 5-row skeleton, never a spinner.
  - *loaded* — the list.
  - *no cooperatives* — this is the only genuinely empty case and it is not the app's fault:
    "You are not in a cooperative yet. Join one in the Communal app and its chat will appear
    here." with a "How to join" link. There is no create-a-chat action, by design.
  - *offline with cache* — the cached list, plus the banner; rows are fully interactive.
  - *error with cache* — the cached list and a one-line "Couldn't refresh" with a retry, never a
    full-screen error over content the member can read.
- **Interactions**: tap → Thread. Long-press → a sheet with Mute (8 hours / 1 week / Until I turn
  it back on), Mark as read. Pull to refresh. There is no delete-conversation: a cooperative's
  chat is not the member's to delete, and hiding it would hide the meeting notice with it.
- **Live updates**: `message.new` moves the row to the top, updates the preview, increments the
  pill; `message.read` from another of your own devices clears it. No refetch — the frame carries
  the message.
- **Data**: `GET /api/meet/v1/conversations` ✅ on open and on resume; `/ws` ✅ for the rest.
- The avatar at top right opens the **Account sheet**.

### 6.6 Thread

Where the app is actually used. Same screen for a group and a DM; the differences are the header,
the sender names, and the call buttons.

```
┌────────────────────────────────────────────┐
│  ←  ┌──┐ Davoli Suit Coop            ⋮    │
│     │DS│ 16 members                        │
│     └──┘                                   │
├────────────────────────────────────────────┤
│              ── Yesterday ──                │
│                                            │
│      Davoli Suit Coop is on Communal        │
│      Meet. Everyone who joins this          │
│      cooperative will be here.              │
│                                            │
│ ┌──┐ Ebere Eze                              │
│ │EE│ ┌──────────────────────────┐          │
│ └──┘ │ Meeting on Saturday,     │          │
│      │ 10am.             09:24  │          │
│      └──────────────────────────┘          │
│                                            │
│      ── 3 new messages ──                   │
│                                            │
│              ┌──────────────────────────┐  │
│              │ I will be there.  09:31 ✓ │  │
│              └──────────────────────────┘  │
├────────────────────────────────────────────┤
│ ┌────────────────────────────────┐  ┌────┐ │
│ │ Message                        │  │ ➤  │ │
│ └────────────────────────────────┘  └────┘ │
└────────────────────────────────────────────┘
```

**Header.** Avatar, name, and a subtitle that changes with the truth: for a group, "16 members",
replaced while someone types by "Ebere is typing…" (and "Ebere and 2 others are typing…"); for a
DM, "online" when the socket says so, else "last seen" is *not* shown — we do not have it and
inventing it would be a lie. Tapping the header opens **Conversation details**.

**App bar actions.** DM: a phone and a video icon. Group: a video icon **only if
`can_host`** — a member cannot start a cooperative meeting, and showing them a disabled button
invites "why not me". The `⋮` menu holds Mute, Participants, and (hosts, groups) "Who can post".

**Message rendering.**
- Own messages right, `primary` bubble, white text, timestamp and tick in white at 70%.
- Others' left, white bubble with a `line` border. In a group, the sender's name above the first
  bubble of a run in their palette hue, and their avatar beside the last bubble of the run.
- Runs collapse: consecutive messages from the same sender within 5 minutes drop the repeated
  name and avatar and tighten to 2dp of separation.
- `kind: "system"` → `SystemLine`, centred, no bubble, no avatar.
- `kind: "call_event"` → a `SystemLine` with a glyph: "Missed call from Dayo Adeyemi",
  "Meeting ended · 42 minutes".
- A reply renders a quoted strip inside the bubble — 2dp accent bar, sender name, one line of the
  quoted body, tappable to scroll to the original (which flashes `primarySoft` for 400ms).
- Links are detected and tappable; nothing else is parsed. No markdown — a member typing an
  asterisk means an asterisk.

**Send states, which are the crux of the offline story.**

| State | Shown as | Meaning |
|---|---|---|
| queued | clock glyph, bubble at 60% opacity | in the outbox, not yet accepted |
| sent | single tick | stored; it has a `seq` |
| seen (DM only) | double tick in white | counterpart's `last_read_seq` ≥ this `seq` |
| failed | ⚠ in `danger` and "Tap to retry" beneath | the server refused it |

Group chats show no read receipts at all. Sixteen people's read state is both expensive and
socially loud, and no one asked for it.

**The unread divider** sits at `last_read_seq` as it was when the thread opened, and does *not*
move while the thread is open — a divider that chases the read pointer is a divider that never
marks anything. The thread opens scrolled to it, not to the bottom, whenever there is one.

**Composer.** One line growing to five, then it scrolls. Send is enabled only on non-whitespace.
Sending clears the field immediately and appends the bubble immediately; there is no spinner in a
composer, ever. When `can_post` is false the whole composer is replaced:

> 🔒 Only administrators can post in this chat.

**Paging.** Opens from cache, then `GET /messages?before=<oldest cached seq>` on scroll to within
10 rows of the top. Loading older shows a 24dp spinner as a list header. `after=` is for
catch-up, not for scrolling (§7.2).

**Read pointer.** `POST /read` when the thread is open and at the bottom, debounced 500ms, and
again on leaving. Not on open — a thread opened by a fat finger and closed at once should not
clear a badge.

- **Data**: `GET /conversations/{id}` ✅, `GET /conversations/{id}/messages` ✅,
  `POST /conversations/{id}/messages` ✅, `POST /read` ✅, `POST /typing` ✅ (or the cheaper socket
  frame), `/ws` frames `message.new`, `message.read`, `typing` ✅.
- **Typing** is emitted on the socket, at most once every 3 seconds while typing, and once with
  `typing: false` on stop or send.

### 6.7 Conversation details

```
┌────────────────────────────────────────────┐
│  ←  Conversation                            │
├────────────────────────────────────────────┤
│              ┌────────┐                     │
│              │   DS   │                     │
│              └────────┘                     │
│           Davoli Suit Coop                  │
│        Cooperative group chat · 16          │
│                                            │
│   ┌──────────┐  ┌──────────┐               │
│   │ 🎥 Meet  │  │ 🔇 Mute  │               │
│   └──────────┘  └──────────┘               │
├────────────────────────────────────────────┤
│  Who can post                    Everyone ›│
│  (administrators only)                      │
├────────────────────────────────────────────┤
│  16 members                                 │
│  ⬤ Ebere Eze          Administrator · You  │
│  ⬤ Dayo Adeyemi                            │
│  ⬤ Ada Tester                              │
│  …                                          │
└────────────────────────────────────────────┘
```

- "Who can post" is visible to everyone (it explains a locked composer) but only tappable by an
  administrator, and it says so in the sub-label. Changing it to admins-only warns once: "Members
  will no longer be able to send messages in this chat. You can change this back at any time."
- A participant row tapped by anyone opens: Message (opens or creates the DM), Call, Video call.
  A member's own row does nothing.
- Departed participants are not listed — the backend already omits them — but their old messages
  keep their name, which is why the participant row is closed rather than deleted server-side.
- **Data**: `GET /conversations/{id}/participants` ✅, `POST /mute` ✅, `POST /posting-policy` ✅,
  `POST /conversations/dm` ✅, `GET /presence` ✅.

### 6.8 Cooperatives

The cooperative as a place: who is in it, what is happening in it, and — for an officer — the
button that starts a meeting.

```
┌────────────────────────────────────────────┐
│  Cooperatives                               │
├────────────────────────────────────────────┤
│ ┌────────────────────────────────────────┐ │
│ │ Davoli Suit Coop                       │ │
│ │ 16 members · Administrator             │ │
│ │ ┌────────────────────────────────────┐ │ │
│ │ │ ⬤ Meeting in progress · 4 people   │ │ │
│ │ │                            [Join]  │ │ │
│ │ └────────────────────────────────────┘ │ │
│ │  💬 Open chat        🎥 Start meeting  │ │
│ └────────────────────────────────────────┘ │
│ ┌────────────────────────────────────────┐ │
│ │ Bulk Sheet Coop Ltd                    │ │
│ │ 231 members                            │ │
│ │ 🗓 Annual general meeting · Sat 10:00   │ │
│ │  💬 Open chat                          │ │
│ └────────────────────────────────────────┘ │
└────────────────────────────────────────────┘
```

- One card per cooperative from `GET /spaces` ✅. `can_host` decides whether "Start meeting" and
  the `HostBadge` appear at all.
- `live_meeting` → the green banner, with a dot that pulses on a 2-second cycle (the only
  looping animation in the app). `next_meeting` → a calendar line; within an hour it reads
  "in 40 minutes".
- **231 members** on the second card is worth noticing: above 200 the interactive ceiling is
  exceeded, so a host who taps Start there gets an honest warning rather than a broken meeting —
  "This cooperative has more members than a single meeting can hold (200). Members beyond that
  will not be able to join." Livestream mode is the fix and it is not in v1.
- **States**: skeleton · loaded · *no cooperatives* (same copy as Chats) · offline (cached, Start
  meeting disabled with "You need a connection to start a meeting").
- Live-meeting arrival while the tab is open comes from `meeting.started` / `meeting.ended` ◻ on
  the socket, not from polling.

### 6.9 Schedule a meeting (host)

A sheet, not a screen: title, date, time, "Everyone can join / Ask me to admit each person",
"Record this meeting". Saving posts the meeting ◻ and drops a system line into the group chat so
the cooperative learns about it where it already reads — "Ebere scheduled *Annual general
meeting* for Sat 23 Aug, 10:00." Push at start comes from the backend.

Default lobby: **off** for a cooperative's own group meeting (everyone in the room is already a
verified member of that cooperative, and a lobby would make an officer gatekeep sixteen people
they already know), **on** for anything else.

### 6.10 Green room

The screen before the meeting. See yourself, choose your devices, then join.

```
┌────────────────────────────────────────────┐
│  ✕                          Davoli Suit Coop│
│ ┌────────────────────────────────────────┐ │
│ │                                        │ │
│ │            (your camera)               │ │
│ │                                        │ │
│ │        ┌────┐        ┌────┐            │ │
│ │        │ 🎤 │        │ 📹 │            │ │
│ │        └────┘        └────┘            │ │
│ └────────────────────────────────────────┘ │
│  4 others are here                          │
│                                            │
│  Microphone   Built-in ▾                    │
│  Camera       Front ▾                       │
│                                            │
│  ┌────────────────────────────────────┐    │
│  │             Join now               │    │
│  └────────────────────────────────────┘    │
└────────────────────────────────────────────┘
```

The self-view is the largest thing on screen because looking at it *is* the task, and it sits on
the same near-black stage the meeting uses so that arriving is not a jolt. The mic and camera
toggles are pills **on** the video, because they change what the video shows and belong where the
result is visible; the device pickers stay in the column below, because choosing a microphone
from a list is a form interaction, not a live one.

The button says **"Join now"** or **"Ask to join"**, and which one is the only warning a person
gets that pressing it leads to a wait. While the answer is still unknown it is disabled with a
spinner — guessing is worse than waiting, in both directions.

- **Permissions happen here.** Camera and mic are requested on entry, with the reason visible
  behind the prompt. Denied camera → the video area becomes a `PermissionNotice` ("Communal Meet
  cannot see your camera. You can still join with audio only.") and joining stays available.
  Denied mic → the same, and joining is *still* available, because a listener at an AGM is a
  legitimate participant. Permanently denied → "Open settings".
- **States**: acquiring devices · previewing · camera-denied · mic-denied · no camera on device ·
  joining (button spinner, controls locked) · join failed ("We could not join the meeting. Try
  again." with the reason logged, never shown).
- **Data**: `POST /meetings/{id}/join` ◻ → `{token, livekitUrl, room, iceServers, role}`. The app
  chooses none of those four. Tracks are acquired *before* the join call and handed to the room,
  so a slow join does not stall the preview.

### 6.11 Waiting room

What a knocker sees while a host decides. An illustration, not a self-view.

The green room exists to be looked at; this screen exists to be waited in, and there is nothing
to check — the tracks are prepared and unpublished, and nothing reaches the room until admission.
A live camera on a screen you cannot act on invites people to keep fixing their hair instead of
telling them the truth, which is that a person is deciding and it takes as long as it takes. So
the drawing is the hero and its motion is what says the wait is live. The mic and camera pills
stay, because what you set here is what you join with, and they **mute** rather than stop — the
pending connection owns those tracks, and stopping one would publish a dead track on admission.

An elapsed counter after 30 seconds ("Waiting · 1:12"), and a "Cancel" that gives up cleanly.
Denied → "The host did not let you in." and back to the cooperative, with no retry button; a
retry button on a denial is an invitation to knock again.

### 6.12 Meeting

```
┌────────────────────────────────────────────┐
│  ⬤ REC   Davoli Suit Coop   12:04    ⋮     │
├────────────────────────────────────────────┤
│ ┌────────────────┐ ┌────────────────┐      │
│ │ Ebere Eze  🎤✕ │ │ Dayo Adeyemi   │      │
│ └────────────────┘ └────────────────┘      │
│ ┌────────────────┐ ┌────────────────┐      │
│ │ Ada Tester     │ │ You            │      │
│ └────────────────┘ └────────────────┘      │
│                  ● ○                        │
├────────────────────────────────────────────┤
│   🎤     📹     🖥     💬②    ☎           │
└────────────────────────────────────────────┘
```

**Layout.** `style: "meeting"` gives the paged grid; `style: "call"` gives the full-bleed stage of
§6.14. The grid ports `livekit-fe/src/lib/grid.ts` — largest tile wins, tiles never below 150dp
wide, page size derived from measured size rather than head count — with one deliberate change:
**tiles hold 3:4 in portrait and 16:9 in landscape.** A portrait phone forcing 16:9 tiles leaves
half the screen empty, which is a browser assumption that does not survive the trip to a handset.
Landscape rotates into the reference's exact behaviour.

Paging is horizontal swipe with dots. The local participant is pinned to page 1. The active
speaker is pulled to page 1 if they are not on it — being told who is talking matters more than a
stable grid.

**Control bar.** Mic, camera, screen share (`meeting` style only), chat with an unread badge,
leave in `danger`. Always dark. Host extras live under `⋮`: Participants, Record, Mute everyone,
End meeting for everyone.

**Recording** starts and does not stop. The media manager exposes no egress-stop route, so a
recording ends when the room empties; the button therefore reports "This meeting is being
recorded. It will be saved when the meeting ends" instead of offering a stop that would silently
do nothing. Everyone sees the `REC` dot and gets a one-time system line in the in-call chat, and
the group chat gets one afterwards. Nobody is recorded without being told.

**Admission (host).** A card at the bottom of the stage, above the control bar — not a modal. A
knock arrives mid-sentence, and a dialog that steals focus to announce somebody who is not in the
meeting yet interrupts the meeting. Admit is primary, Deny secondary, **neither is default and
nothing is pre-selected**, because an accidental admit puts an unapproved person into a meeting
that may be recording. "Admit all" appears only when more than one is waiting.

**In-call chat** is a bottom sheet over the stage, and it is *not* the cooperative's chat. It
rides the LiveKit data channel with the same `{"type":"chat","sender","message"}` payload the
browser client uses, so a member on a phone and an officer on a laptop can talk to each other. It
is ephemeral and the sheet says so once, at the top: "Messages here are only for this meeting."
What survives is a single line in the group chat when the meeting ends.

**Weak network.** A `warningSoft` pill under the app bar — "Your connection is unstable" — and per-tile
glyphs from LiveKit's quality events. Reconnecting shows a full-width strip, not a dialog, and the
stage keeps the last frame rather than going black; a black stage reads as "the call dropped".

**Leaving.** The leave button confirms in a sheet, and a host's sheet has two actions: "Leave
meeting" and "End for everyone" — a president who taps leave should not accidentally end the AGM.

**Wakelock** is held for the meeting's duration and released on exit, including on an error exit.

**States**: connecting (stage with a centred spinner and "Joining Davoli Suit Coop…") ·
connected · reconnecting · alone in the room ("Waiting for others to join") · ended by host
("The host ended the meeting") · kicked ("You were removed from the meeting") · failed.

### 6.13 Meeting summary

After leaving: duration, who attended, and — for a host of a recorded meeting — "The recording
will be saved when everyone has left." One action, "Done", and a secondary "Open chat", because
the thing people do after a meeting is talk about it.

### 6.14 Call — 1:1

`style: "call"`: one full-bleed subject with your own camera as a small corner PiP. Nobody is an
equal tile because in a call there is always a subject. With 3–8 in a small group call, a thin
strip of the others sits above the PiP, which is how the phone apps do it.

**Outgoing.** Placed from a DM header or the Calls tab. The screen shows the callee's avatar,
name, "Calling…", `ringback.ogg`, and one red decline. After 45 seconds with no answer: "No
answer", the call is marked missed, and a `call_event` line lands in the DM.

**Incoming.** CallKit on iOS and the telecom UI on Android own the ring; that is what wakes a
locked phone. Accepting hands off to a full-screen route pushed over whatever was on screen.
Declining posts the decline so the caller stops ringing rather than waiting for a timeout.

**Busy.** A member already in a meeting is not rung. The caller is told "Ebere is in a meeting"
and the callee gets a `call_event` line — an unanswerable ring during an AGM is worse than a
missed call.

- **Data**: `POST /calls` ◻, `POST /calls/{id}/accept|decline|end` ◻, socket `call.ring`,
  `call.cancelled`, `call.answered` ◻, and the ring push (data-only, high priority) which is what
  the `push_options` change to `FirebaseService` exists for.

### 6.15 Calls tab

A list of recent calls: direction glyph, name, time, duration, "Missed" in `danger`. Tapping a
row calls back. Empty: "No calls yet. You can call anyone you share a cooperative with." with a
"Find someone" action that opens a searchable list of co-members drawn from the group chats'
participants — there is no directory endpoint and none is needed.

### 6.16 Account sheet

Name, phone, avatar; the cooperatives they are in; Notifications (with a "Turn on" when the OS
permission is off); Change PIN (deep-links to the member app's flow, saying it changes the PIN
everywhere); Sign out, which warns that queued messages will be lost if any are queued, and says
nothing if none are. App version and environment at the bottom, small — it is the first thing
support asks for.

---

## 7. Cross-cutting behaviour

### 7.1 The outbox

A typed message is the member's, not the network's.

1. On send: write to the outbox with a locally generated `client_msg_id` (uuid v4), append the
   bubble as `queued`, clear the composer.
2. Post it. On 201 replace the local row with the server's — the server's `seq` is the truth about
   ordering, and the local row never had one.
3. On network failure: leave it `queued`, retry with backoff (2s, 8s, 30s, then on connectivity
   regained or on app resume).
4. On 4xx: mark `failed` with a tap-to-retry, and keep the text so it is never lost.
5. On restart: the outbox is on disk (`sqflite`), so a killed app still sends what was typed.

Retries reuse the same `client_msg_id` forever. That is the entire reason the field exists: the
server returns the message it already stored rather than a second copy, so a phone that resends
on a flaky connection cannot double-post.

Ordering while offline: queued messages sort after everything with a `seq`, in the order typed.

### 7.2 The socket

- Connect after Home renders, not during splash. `wss://…/api/meet/v1/ws?token=<jwt>` — the token
  goes in the query because a Dart client cannot set a header on an upgrade.
- `{"type":"ready"}` is the signal to **catch up**: for each conversation with cached messages,
  `GET /messages?after=<local max seq>`. This is the one thing that makes an app that was
  backgrounded for an hour correct rather than merely fresh.
- Reconnect with exponential backoff and jitter — 1s, 2s, 4s, 8s, capped at 30s — and reset on a
  successful `ready`. No cap on attempts; `/ws` sits outside the rate limiter for exactly this.
- Foreground/background: disconnect 30 seconds after backgrounding (a socket held open in the
  background is a battery complaint), reconnect immediately on resume, then catch up. Push covers
  the gap.
- Frames the app handles: `ready`, `message.new`, `message.read`, `typing`, `presence`,
  `conversation.updated`, `call.ring`, `call.cancelled`, `call.answered`, `meeting.started`,
  `meeting.ended`, `error`. An unknown `type` is logged and dropped — the server will grow frames
  this build has never heard of.
- A `message.new` for a conversation the app has never seen means a new DM or a new cooperative:
  refetch `/conversations` rather than inventing a row.
- The socket is never trusted for authorisation and never asked to subscribe to anything. It is
  bound to the caller's profile server-side, which is why there is no subscribe frame to send.

### 7.3 Unread, badges and read pointers

One source of truth: `last_read_seq` on the server. The app renders `unread` from
`/conversations`, adjusts optimistically on `message.new` and on its own reads, and never computes
it from local storage — two devices would disagree forever.

The app icon badge is the same sum the Chats tab shows, updated from push payloads on both
platforms.

### 7.4 Push

Two shapes, and they must not be confused.

| Kind | Payload | Behaviour |
|---|---|---|
| chat message | notification + data | posts to the **Messages** channel, grouped per conversation, "Ebere Eze: Meeting on Saturday" for a group, sender-titled for a DM; tapping opens the thread |
| meeting started | notification + data | **Meetings** channel, high priority, tapping opens the green room |
| incoming call | **data-only, high priority** | wakes the app and hands to CallKit; never a notification block, or the phone will not ring |

Android channels: Messages (default importance, sound), Meetings (high), Calls (max, with the
ring sound and full-screen intent). A member can silence Messages without silencing Calls, which
is the whole reason they are separate channels.

A push whose conversation is muted server-side never arrives — the backend intersects mute and
device token before publishing — so the app does no client-side suppression, and cannot get it
wrong.

### 7.5 Permissions, in the order they are asked

1. **Notifications** — after first sign-in, behind the primer of §6.4.
2. **Microphone** — on entering the green room.
3. **Camera** — on entering the green room, after the mic.

Never at launch, never all three at once, and every denial has a working path behind it:
audio-only join, avatar instead of video, in-app-only chat. The only permission whose denial
costs a feature outright is the microphone in a call, and even then listening still works.

### 7.6 Errors, and what they say

- Anything 5xx: "Something went wrong on our side. Please try again." with a retry. The cause goes
  to the log, never to the screen.
- 401 after refresh fails: back to Sign in with "Your session expired. Please sign in again."
- 403 on a conversation: "You no longer have access to this chat." and pop to Chats — this is what
  a member sees the moment they leave a cooperative, and it must not look like a crash.
- 404 on a conversation: the same. The server answers "not found" and "not yours" identically on
  purpose, and the app must not try to be cleverer than that.
- Offline: never an error. A banner, cached content, and a queue.

### 7.7 Accessibility

- Every icon button has a semantics label; the control bar's read "Mute microphone", "Turn off
  camera", "Leave meeting".
- Text scales to 1.3× without clipping: bubbles grow, rows grow, the grid drops one column.
- Contrast, measured rather than assumed: `muted` on `surface` is 4.52:1, `onStageMuted` on
  `stage` is 7.66:1, white on the `primary` bubble is 6.45:1, and the weakest sender hue on white
  is 4.99:1. `muted` is the tightest of them at barely over the 4.5:1 line, which is why it is
  never used for anything a member has to act on.
- Nothing depends on colour alone — the recording dot has the word REC, the missed call has the
  word Missed, the muted row has a glyph.
- The active speaker is a ring *and* a name-label weight change, because a ring alone is invisible
  to a colour-blind eye on a dark tile.

### 7.8 Language

English only in v1, with strings in one file so a Hausa or Yoruba pass is a translation and not a
rewrite. Numbers, dates and durations go through `intl` from the start; hardcoded "10:00" is the
kind of thing that survives to production.

---

## 8. Architecture the screens are built out of

`collector_mobile`'s layout, one level deeper because there are more screens.

```
lib/
  main.dart
  core/
    config.dart        AppConfig + ApiPaths (--dart-define, never a bundled asset)
    theme.dart         AppColors, AppStage, buildAppTheme(), text styles
    grid.dart          gridLayout / tilesPerPage, ported from livekit-fe
    sounds.dart        join / knock / ringback
    format.dart        relative time, duration, initials, sender hue
  data/
    api_client.dart    dio + auth interceptor + refresh + retry
    socket.dart        the /ws client: backoff, lifecycle, frame decoding
    models.dart        Conversation, Message, Space, Meeting, Call, Person
    repository.dart    ChatRepository, MeetRepository, CallRepository
    outbox.dart        sqflite queue, retry policy
    local_cache.dart   conversations + last 200 messages each
    session_store.dart secure storage: tokens, profile
    push.dart          FCM registration, channels, CallKit handoff
  state/
    session_cubit.dart
    connectivity_cubit.dart
    conversations_cubit.dart
    thread_cubit.dart       (one per open thread)
    spaces_cubit.dart
    meeting_cubit.dart      (LiveKit room lifecycle)
    call_cubit.dart
  screens/
    splash, auth/, home_shell, chats_tab, thread, conversation_details,
    coops_tab, schedule_meeting, green_room, waiting_room, meeting,
    meeting_summary, call, calls_tab, account_sheet
  widgets/
    common.dart, conversation_row.dart, message_bubble.dart, composer.dart,
    participant_tile.dart, control_bar.dart, admission_card.dart, states.dart
```

**Dependencies**, beyond the collector app's set: `livekit_client` (with `flutter_webrtc`
transitively), `permission_handler`, `firebase_core`, `firebase_messaging`,
`flutter_callkit_incoming`, `wakelock_plus`, `web_socket_channel`, `sqflite`, `uuid`,
`audioplayers`, `visibility_detector` (to know when a thread is actually on screen before marking
it read).

**Identity**: package `communal_meet`, application id `com.communal.meet`, matching
`com.communal.collector`. Signing reuses the fleet's single unified keystore as **repo-level**
secrets — adding env-scoped `ANDROID_*` silently shadows it.

### 8.1 Endpoint map

| Screen | Calls | Built? |
|---|---|---|
| Sign in | `POST /api/v1/login-checker`, `POST /api/v1/login`, `POST /api/v1/profile/device-token` | ✅ |
| Splash | `POST /api/v1/refresh-token`, `GET /api/meet/v1/me` | ✅ |
| Chats | `GET /conversations` | ✅ |
| Thread | `GET /conversations/{id}`, `GET|POST …/messages`, `POST …/read`, `…/typing` | ✅ |
| Details | `GET …/participants`, `GET …/presence`, `POST …/mute`, `…/posting-policy` | ✅ |
| DM start | `POST /conversations/dm` | ✅ |
| Live | `GET /ws` | ✅ |
| Cooperatives | `GET /spaces` | ✅ |
| Schedule / meet | `GET|POST /meetings`, `POST /meetings/{id}/join|end`, lobby, host controls, recording | ◻ step 4 |
| Calls | `POST /calls`, `POST /calls/{id}/accept|decline|end`, `GET /calls/recent` | ◻ step 7 |

## 9. Assets a designer still has to hand over

Everything above can be built from tokens and Flutter's own icons. These cannot:

1. **The app mark** — launcher icon and the sign-in lockup. The fleet's convention is one
   Communal mark on a white ground, tinted per app (member purple, collector black), so Meet
   needs its tint decided and the foreground exported at 1024². Invented here would be a brand
   decision made by the wrong person.
2. **The waiting-room illustration** — a looping, low-motion drawing, ~240dp tall, legible on
   `#0B0B0F`. Motion is what says the wait is live, so it cannot be a static PNG.
3. **Three sounds** — `join.ogg`, `knock.ogg`, `ringback.ogg`, each under 6KB, mixed quiet.
4. **Empty-state glyph set** — five line drawings (no chats, no cooperatives, no calls, offline,
   error) in one stroke weight.

Until they exist the app builds with Material icons and no illustration, and nothing below §9 is
blocked.

## 10. Deliberately not designed

Named so nobody assumes they were forgotten: message editing and deletion (there is no route, and
"delete for everyone" in a cooperative's record is a governance question, not a UI one),
attachments and voice notes, message search, group chats that are not a cooperative, guest
invitees, in-app recording playback, a call from the lock screen without CallKit, tablet layouts
beyond "the phone layout, wider", and dark mode for the light chrome — the stage is already dark
and a dark chat list is a preference, not a need, in v1.

## 11. Two decisions that are the user's, not mine

Neither blocks building; both change one screen if answered the other way.

- **Whose call is the group meeting's lobby?** §6.9 defaults it **off** for a cooperative's own
  meeting, on the argument that everyone in the room is already a verified member and an officer
  should not have to admit sixteen people they know. A cooperative that wants an AGM gated would
  want the opposite default.
- **May a plain member start a meeting?** §6.8 says no — `can_host` gates it, so only
  administrators see the button. If two members should be able to meet without an officer, that
  is a backend authorisation change as well as a button.
