# Parallax

A native visionOS client for **Claude** and **Gemini** — and a compare mode that
sends one question to both and puts the answers side by side.

Neither assistant ships a Vision Pro app, so the alternative is a Safari tab.
Parallax is a real window: streaming replies, reasoning kept apart from the
answer, model lists pulled from each provider's own API, and keys that never
leave the device Keychain.

## What it does

- **Streaming chat** with Claude (Messages API) and Gemini (Generative Language
  API), each keeping its own thread of the conversation.
- **Compare mode** — the same prompt goes to both assistants at once and the two
  replies render in their own column, attributed by colour.
- **Reasoning** from either model (Claude's adaptive thinking, Gemini's thought
  parts) in a fold-away block, never mixed into the answer.
- **Model picker fed by the API**, not by a hardcoded list that ages: the app
  asks each provider what the account can actually use.
- **Markdown rendering** with copyable code blocks.
- **English and Brazilian Portuguese**, following the system by default and
  switchable inside the app.
- **Conversations stored on device** as readable JSON; **API keys in the
  Keychain**, sent only to the API they belong to.

## Requirements

- visionOS 26 or later (Apple Vision Pro, or the simulator)
- Xcode 26
- An API key for whichever assistant you want to use —
  [Anthropic Console](https://console.anthropic.com/settings/keys) or
  [Google AI Studio](https://aistudio.google.com/apikey)

## Build

```bash
brew install xcodegen
xcodegen generate
open Parallax.xcodeproj
```

Or from the command line, against the simulator:

```bash
xcodebuild -project Parallax.xcodeproj -scheme Parallax \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro' build
```

One script does build, install, launch and screenshot against a booted (or
freshly created) visionOS simulator:

```bash
scripts/run-simulator.sh
```

Logic tests run on the Mac, no simulator involved:

```bash
swift test
```

To check a translation without changing the system language, force one:

```bash
PARALLAX_LANG=pt xcrun simctl launch --console <device-udid> com.parallax.app
```

## Where things live

| Path | What |
| --- | --- |
| `Sources/Services` | The two REST clients and the shared SSE plumbing |
| `Sources/Store` | Session engine, settings, Keychain, conversation file |
| `Sources/Views` | SwiftUI screens, Markdown rendering, the composer ornament |
| `Sources/Design` | Palette, metrics, motion, the app's mark |
| `Sources/Support` | String catalog (`en`, `pt-BR`) |

## Privacy

Prompts go to the provider whose key is configured, and nowhere else. There is
no analytics, no crash reporter, no account, and no server of ours in the path.

## License

MIT — see [LICENSE](LICENSE).
