# CasperFlow

Open-source macOS dictation: hold **Ctrl+Option**, speak, and polished text pastes into the focused app.

Powered by **PyAI Hear** (speech-to-text) with optional **OpenAI** tone rephrasing. MIT licensed.

```
Mic → 16 kHz PCM16 → pre-roll → Hear stream
  → local lexicon + app-aware tone
  → optional OpenAI rewrite
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

This builds `dist/CasperFlow.app` and launches it (required for Accessibility / global hotkey).

## App sections

| Section | Purpose |
|---------|---------|
| **Dictation** | Status, hold-to-talk, live transcript |
| **API Keys** | PyAI (required) + OpenAI (optional) |
| **App tones** | Per-app Casual / Professional / Developer / General |
| **Appearance** | System / Light / Dark |
| **Permissions** | Accessibility + microphone |

## Controls

| Input | Action |
|-------|--------|
| **Ctrl+Option** (hold) | Push-to-talk → paste into focused app |
| Space / on-screen button | PTT while CasperFlow is focused |

Enable **CasperFlow.app** (`com.casperflow.app`) under System Settings → Privacy & Security → Accessibility — not Cursor.

## What is included

This repository is the **macOS Swift app only**.

## License

MIT — see [LICENSE](LICENSE).
