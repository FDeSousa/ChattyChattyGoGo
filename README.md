# ChattyChatty GoGo

A private chat client for your own **OpenCode Go** subscription. SwiftUI, iOS 26+, no third-party
SDKs, no analytics, no account — just you, your key and the models you already pay for.

```
opencode.ai  ←  your API key (keychain)  ←  ChattyChatty GoGo  ←  on-device chat history
```

## What it does

- **Multiple chats** with auto-titles, rename, delete and date grouping.
- **Local history** in SwiftData, plus **search across every chat** (titles and message bodies,
  case- and accent-insensitive).
- **Only the models your account may use.** The gateway is asked which models are enabled for
  your key, so models switched off in the OpenCode console (or blocked by your privacy settings)
  are hidden from the picker and are never picked automatically.
- **Every Go model** is listed with a short description of what it is good at, what a request
  costs, and how long the provider keeps the request.
- **Streaming answers** with a stop button, markdown rendering, copyable code blocks and a
  collapsible "Thinking" section when a model exposes its reasoning.
- **Cost and timing** for every reply: how long it took, how many tokens went in and out, how
  many came from the prompt cache, and what that consumed of your monthly allowance. Per chat
  under *Usage & cost*, and as a total in Settings.
- **Attachments**: images from your photo library and documents (PDF, text, code, CSV, JSON).
  Documents are turned into text so every model can read them; images are sent to the models
  that can look at them.
- **Thinking level** (Off / Balanced / Deep) for models that support a reasoning budget.
- **Auto** — a daily rotating pick from a curated pool of strong, non-contributor-tier models,
  restricted to the ones your account has enabled.
- **Usage** view showing the rolling / weekly / monthly allowance straight from the OpenCode API.
- **Privacy**: the API key lives in the iOS keychain, chats never leave the device, and an optional
  Face ID lock hides everything when you leave the app.
- **Export** all chats to JSON at any time.

## What the models can and cannot do

The Go lineup is text models. Concretely:

| | |
| --- | --- |
| **Text in, text out** | Yes — that is what every model does. |
| **Code blocks** | Yes. Fenced blocks are syntax highlighted for 61 languages (with automatic detection for anything else), in a monospaced card with a copy button. |
| **Images out** | No. None of the Go models generate images, so the app never tries to render one. |
| **Images in** | Only the models marked with a photo icon (Grok 4.7, GPT 6/5.6 Luna, Claude Haiku 5.5, Gemini 4 Argon) can look at a picture. The rest are text only, and the app warns you before sending. |
| **Documents in** | Yes. PDFs are read with PDFKit and everything else is read as text, so all models can use them. |
| **Audio in** | No. These chat endpoints have no audio input. |
| **Video in** | No. Same reason — video is not part of these chat APIs. |

## Requirements

- Xcode 27.1 (iOS 27.1 SDK) — the project targets **iOS 26.0** and up.
- An OpenCode Go subscription. Get a key at <https://opencode.ai/auth>.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## Getting started

```bash
brew install xcodegen        # only needed once
xcodegen generate            # writes ChattyChattyGoGo.xcodeproj
open ChattyChattyGoGo.xcodeproj
```

In Xcode: select the `ChattyChattyGoGo` scheme, pick your iPhone, and run. The app asks for your
OpenCode Go key on first launch, tests the connection, and then lets you pick a model.

To run on the device, set your team in *Signing & Capabilities* (the bundle id is
`pt.com.desousa.filipe.ChattyChattyGoGo`; change it in `project.yml` if you want a different one).

Command line build:

```bash
xcodebuild -project ChattyChattyGoGo.xcodeproj -scheme ChattyChattyGoGo \
  -destination 'generic/platform=iOS' build
```

## Layout

```
project.yml                      XcodeGen project definition
ChattyChattyGoGo/
  App/                           App entry, root routing, content layout
  Data/                          SwiftData models (Conversation, Message, Attachment)
  Models/                        Wire types, model catalogue, pricing, context window
  Services/                      Networking, keychain, backup, attachments, biometrics
  ViewModels/                    Chat, chat list and search logic
  Views/                         Chat list, chat, settings, onboarding, shared components
ChattyChattyGoGoTests/            Unit tests (run from Xcode)
ChattyChattyGoGoUITests/          Walkthrough test that screenshots each screen
Tools/
  MakeAppIcon.swift              Generates the 1024pt app icon
  LogicCheck/                    Standalone SwiftPM harness for the pure logic
```

## Dependencies

One: [HighlightSwift](https://github.com/appstefan/HighlightSwift), which highlights code
blocks with highlight.js running in JavaScriptCore — no web view, and the theme follows
dark mode. It covers 61 languages directly, and any other fence tag is passed through to
highlight.js or detected automatically.

Everything else is Apple frameworks. The zero-dependency property was traded away for this
one on purpose: hand-rolling a highlighter that covers many languages is not a small task,
and code blocks are what this app shows most.

## Context window

Each model has a context limit, taken from the figures OpenCode publishes where it publishes
them (`100K` for Claude Haiku, `200K` for Grok 4.7, `272K` for the GPT models, `1M` for Gemini)
and a conservative `64K` default where it does not. Requests keep the newest messages that fit
and say how many older ones were left out, so a long chat degrades gracefully instead of
failing with an upstream error.

## Backup

*Export all chats* writes a JSON file. *Import chats* reads it back, offering to add to what
is here (skipping chats that already exist by id) or replace everything. Timestamps are stored
with fractional seconds so message order survives the round trip.

## How it talks to OpenCode

The Go gateway exposes each model through one provider dialect. The app knows the mapping for the
current lineup and, if a model is served differently than expected, it automatically retries the
other dialects until one works:

| Family | Endpoint |
| --- | --- |
| OpenAI chat completions | `https://opencode.ai/inference/go/openai/v1/chat/completions` |
| OpenAI responses | `https://opencode.ai/inference/go/openai/v1/responses` |
| Anthropic messages | `https://opencode.ai/inference/go/anthropic/v1/messages` |
| Google Gemini | `https://opencode.ai/inference/go/google/v1beta/models/<model>:streamGenerateContent` |
| OpenAI chat completions, pay-as-you-go | `https://opencode.ai/inference/openai/v1/chat/completions` |
| Anthropic messages, pay-as-you-go | `https://opencode.ai/inference/anthropic/v1/messages` |
| Google Gemini, pay-as-you-go | `https://opencode.ai/inference/google/v1beta/models/<model>:streamGenerateContent` |
| System One (Jev) | `https://opencode.ai/inference/systemone/v1/systemone` |

Go models live under `/inference/go/…`; the same dialects are served one level up
(`/inference/…`) for pay-as-you-go models. The picker marks which billing a model belongs
to: Go rows carry no badge, rows reached through the pay-as-you-go balance are marked
**ZEN**, and dropped models are marked **RETIRED**.

### Go and the pay-as-you-go balance

The catalogue distinguishes three ways a model can be reached:

- **Go** — the flat subscription. A request consumes part of the monthly allowance.
- **Pay-as-you-go (Zen)** — on the Console balance, using the same API key. A handful of
  models that were removed from the Go lineup can still be bought by the request there,
  and Jev (below) is only served this way. When such a model is no longer enabled on the
  account, the picker explains that turning on *Extra Usage* in the console lets Go fall
  back to that balance.
- **Retired** — removed from both lists (or deprecated like the Argon contributor tier),
  shown only so an old default model id still resolves with an honest explanation.

The usage view shows the pay-as-you-go balance when the usage endpoint happens to report
one. OpenCode does not document a balance field, so the line appears only when such a
number is actually present in the response.

### Jev trials

[Jev](https://docs.typesafe.ai/) is a *System One* decision model by TypeSafe, served by
OpenCode's pay-as-you-go endpoint: instead of prose it answers **typed questions** about a
**state** — yes/no probability (`noul`), pick-one (`choice`) and rubric score — with values,
confidence and full probability distributions your code can use directly. It is **not part
of the Go subscription**.

Settings → *Jev trials* runs it interactively:

- Each trial holds a subject (the state) and a set of editable questions; per type you can
  edit the instructions, the options and what each option covers, or the rubric levels.
- Press **Run** and one request asks Jev everything at once. Every run is stored: each
  answer with its value, confidence and probability distribution, plus the duration, the
  token counts, the charge (reported by the gateway, else the published rate) and how the
  request was billed (`balance` / `free`).
- Earlier runs keep the question wording they were asked with, so results stay comparable
  across edits. Two ids are offered: `jev-1.13-free` (free for a limited time) and
  `jev-1.13` ($0.042 per million input tokens, output free).

Jev never appears as a chat model — selecting it in a conversation is blocked with a pointer
to the trials instead.

### Models the gateway refuses

A model can be listed but still rejected — region restrictions, privacy settings, or data-sharing
rules on the account. When that happens the app remembers it, stops offering it, and stores why,
using the gateway's own wording (for example a free model rejected with *"Free models may train on
request data. Allow free endpoints in your workspace's Privacy settings to use them."*). The picker
shows such models greyed out under "Not enabled", with that explanation on the row, and free or
contributor-tier models carry a note about the privacy trade-off even before anything fails. The
"Re-check models the gateway has refused" button in the picker clears that memory, for when the
account settings change.

### The model list

`GET /inference/go/v1/models` requires your key and returns **only the models your account may
use**. The app calls it on launch (and from *Settings → Refresh model list*) and uses it as the
source of truth for the picker, so a model that is switched off cannot be chosen by accident. The
"Auto" pick is restricted to enabled models too.

### Client requirements

The gateway only serves third-party clients that behave like a coding agent. It rejects anything
else with `HTTP 400 MissingSessionID`, so every request carries:

| Header | Value |
| --- | --- |
| `x-opencode-session` | A stable per-conversation id in OpenCode's format: `ses_` + 64 hex characters. Stored on the conversation, so every turn stays on the same upstream and keeps the prompt cache warm. |
| `x-opencode-session-id`, `X-Session-Id`, `x-session-affinity` | The same value, as OpenCode itself sends them. |
| `x-opencode-client` | `chattychatty-gogo` |
| `User-Agent` | `chattychatty-gogo/1.0 (iOS)` — a client specific name, not an SDK name. |

Requests that are not tied to a conversation (the model list and the usage view) use a stable
install level id instead.

If a model refuses to answer because of an optional parameter (for example `reasoning_effort` on a
model that does not accept it), the request is retried without it automatically. You can also pin a
model to a specific API style in *Settings → Model → API style*.

## Previews

Every view has an inline `#Preview` at the bottom of its file, laid out for the
**iPhone 17 Pro Max (440 × 956 pt)**. Open any file and hit ⌥⌘P to see it, or use the canvas
device picker to check other sizes.

| Preview | File |
| --- | --- |
| Chat list (with and without a key) | `Views/ChatList/ChatListView.swift` |
| Chat, empty chat, chat instructions | `Views/Chat/ChatView.swift` |
| Message bubbles, typing indicator | `Views/Chat/MessageBubble.swift` |
| Composer | `Views/Chat/ComposerBar.swift` |
| Markdown, code block, empty state | `Views/Components/` |
| Model picker, model row, API style | `Views/Settings/ModelPickerView.swift` |
| Settings, usage, API key | `Views/Settings/` |
| Onboarding, lock screen | `Views/Onboarding/` |
| Content, chat row | `App/`, `Views/ChatList/` |

Preview data lives in `Views/Components/PreviewSupport.swift` and is stored in an **in-memory**
SwiftData container, so opening a preview never touches the real conversations or the keychain.

## Tests

There are three layers, all runnable without a real network:

| Suite | What it covers | How to run |
| --- | --- | --- |
| `Tools/LogicCheck` | Stream parsing, model resolution, markdown, search, titles | `cd Tools/LogicCheck && swift test` (macOS, no simulator needed) |
| `ChattyChattyGoGoTests` | The same logic plus SwiftData storage, keychain, and a render test that mounts every previewed screen in a real window | ⌘U in Xcode, or `xcodebuild test` |
| `ChattyChattyGoGoUITests` | Drives the app through onboarding → chat list → settings → model picker → new chat, screenshotting each step | `xcodebuild test -only-testing:ChattyChattyGoGoUITests` |

The networking tests use a mock `URLProtocol`, so they never touch the network. The UI test
launches the app with `-uiTestResetState`, which clears preferences and the keychain first so
each run starts from a clean slate.

## Cost and usage

Go is a flat subscription, so the app does not show a bill — it shows how much of your monthly
allowance a request consumed. The token counts come from the provider's own usage report (parsed
out of the stream for all four dialects), and the price per token comes from the published Go
price list in `Models/ModelPricing.swift`.

## Privacy notes

- The API key is stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` in the keychain.
- Conversations are stored in the app's SwiftData container on the device only. Nothing is uploaded
  anywhere except `opencode.ai`, and only the messages of the chat you are actively sending.
- The model list shows each provider's retention policy, taken from OpenCode's privacy table.
  Most models discard the request; Grok, GPT and Claude Haiku keep it for 30 days; the
  contributor-tier models (Muse Spark, Gemini 4 Argon) may use it for training and are marked as
  such. They are excluded from the "Auto" pool for that reason.
