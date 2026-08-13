# CasperFlow

Open-source macOS dictation: hold **Ctrl+Option**, speak, and polished text pastes into the focused app.

Powered by **PyAI Hear** (speech-to-text) with optional **OpenAI** tone rephrasing. MIT licensed.

```
Mic → 16 kHz PCM16 → pre-roll → Hear stream
  → local lexicon + app-aware tone
  → optional OpenAI rewrite (dictate) or ChatGPT compose (Ask)
  → paste at caret (any app)
```

## Requirements

- macOS 14+
- Xcode 15+ / Swift 5.9+
- `PYAI_API_KEY` with `hear:stream` scope
- Optional: `OPENAI_API_KEY` for LLM tone rewrite

## Run

```bash
cp .env.example ../.env   # or export keys in your shell
# edit ../.env with your PYAI_API_KEY

./run.sh
```

This builds the app, installs `~/Applications/CasperFlow.app`, and launches that copy (required for Accessibility / global hotkey).

Always use `./run.sh` or `./build-app.sh` — not `swift run`. Enable **only** the CasperFlow in **~/Applications** (bundle `com.casperflow.app`), not Cursor and not `dist/CasperFlow.app` on the Desktop. Rebuilds keep the same bundle id, so that Accessibility toggle should stay valid.

## App sections

| Section | Purpose |
|---------|---------|
| **Dictation** | Status, hold-to-talk, live transcript |
| **API Keys** | PyAI (required) + OpenAI (optional) |
| **App tones** | Per-app Do nothing / Casual / Professional / Developer / General, plus a global rephrase shortcut |
| **Appearance** | System / Light / Dark |
| **Permissions** | Accessibility + microphone |

## Controls

| Input | Action |
|-------|--------|
| **Ctrl+Option** (hold) | Push-to-talk → paste transcript into focused app |
| **Option+Command** (hold) | Speak a writing request → ChatGPT reply pastes (needs OpenAI key) |
| **Ctrl+Command** (tap, configurable) | Rephrase selected text in the focused app |
| Space / on-screen button | PTT while CasperFlow is focused |

Enable **~/Applications/CasperFlow.app** (`com.casperflow.app`) under System Settings → Privacy & Security → Accessibility — not Cursor, not the Desktop `dist` copy.

## What is included

This repository is the **macOS Swift app only**.

## License

MIT — see [LICENSE](LICENSE).
