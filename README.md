# Casper

Speak, and text appears in whatever app you are using.

Casper is a free, open-source macOS dictation app. Hold a shortcut, talk, and polished text pastes at the caret — Slack, Mail, Chrome, Cursor, anywhere. Speech-to-text is **PyAI Hear**. Optional **OpenAI** rewrites tone, answers spoken questions, and summarizes notes.

MIT licensed. Version **0.2.4**.

![Casper Dictation screen](docs/screenshots/casper-ui-dictation.png)

![Listening overlay while dictating into Gmail](docs/screenshots/casper-overlay-gmail.png)

## What you can do

- **Dictate** into the focused app. A small overlay shows live transcription.
- **Ask ChatGPT** out loud; the reply pastes at the caret (needs an OpenAI key).
- **Rephrase** selected text in any app.
- **Note taker** for meetings and videos: microphone, system audio, or both. Summarize when you are done (OpenAI).
- **History** of pastes you can save, drag into another app, or paste again.
- **Vocabulary** so names and jargon come out the way you want (for example Hear writes “denim”, you paste “DNM”).
- **App tones** — Casual in Slack, Professional in Mail, Developer in Cursor, or paste exactly as spoken.

A waveform icon stays in the menu bar. From there you can pause hotkeys, open the window, or quit.

## Requirements

- macOS 14 or later
- A **PyAI** API key with `hear:stream` (required for speech-to-text)
- An **OpenAI** API key (optional: tone rewrite, Ask ChatGPT, note summaries)

To build from source you also need Xcode 15+ / Swift 5.9+.

## Install

Download the latest `Casper-*.dmg` from [Releases](https://github.com/arsalan-saaslabs/CasperFlow/releases).

1. Open the disk image and drag **Casper** into **Applications**.
2. Launch it from Applications — not from the disk image.
3. If macOS blocks the app, right-click → **Open**.
4. Grant **Microphone** and **Accessibility**. For Note taker on YouTube or other playback, also grant **Screen Recording** (audio only; the screen is not saved).
5. In the app, open **API Keys** and save your PyAI key. OpenAI is optional.

You do not need to clone the repo or run scripts.

## First-run permissions

Global shortcuts and paste need **Accessibility** on the real app:

- Enable **Casper** from **~/Applications** (bundle id `com.casperflow.app`).
- Do not enable Cursor, Terminal, or a copy under `dist/`.

The **Permissions** section in the app can open System Settings and reveal `Casper.app` in Finder.

Keys are stored on this Mac only and are not written to logs.

## Shortcuts

Change any of these in **Shortcuts**. Dictate and Ask can be **hold to talk** or **press to start / press to stop**.

| Default | Action |
|---------|--------|
| **Ctrl + Option** | Dictate — paste into the focused app |
| **Option + Command** | Ask ChatGPT — paste the reply |
| **Ctrl + Command** | Rephrase the current selection |
| **Ctrl + Shift + H** | Show or hide the history overlay |
| **Ctrl + Shift + N** | Start or stop Note taker |
| **Ctrl + Shift + O** | Command overlay (actions + tone chips) |
| Space or **Hold to talk** | Dictate while the Casper window is focused |

## Inside the app

| Section | What it is for |
|---------|----------------|
| **Dictation** | Live transcript, hold-to-talk, level meter |
| **Note taker** | Record mic and/or system audio; save and summarize notes |
| **API Keys** | PyAI (required) and OpenAI (optional) |
| **Shortcuts** | Talk style and every global hotkey |
| **History** | Task log — save, drag, or paste |
| **Vocabulary** | Heard → preferred spelling |
| **App tones** | Per-app Do nothing / Casual / Professional / Developer / General |
| **Appearance** | System, Light, or Dark |
| **Permissions** | Accessibility, microphone, Screen Recording |
| **Diagnostics** | Local logs (secrets stripped) — copy, reveal, or send |

Default tones: Slack casual, Mail professional, Cursor and VS Code developer, browsers and notes general. Turn rephrasing off if you only want lexicon cleanup.

## How speech becomes text

1. Your mic (or system audio for notes) is captured as 16 kHz PCM.
2. A short pre-roll is sent so the first words are not cut off.
3. **PyAI Hear** streams partials into the overlay, then a final transcript.
4. Vocabulary and optional tone polish run locally. With an OpenAI key, dictation can be rewritten to match the frontmost app (except **Do nothing**).
5. Text pastes at the caret — except Note taker, which stays in Casper.

## Run from source

```bash
./run.sh
```

That builds the app, installs `~/Applications/Casper.app`, and launches it. Accessibility and global hotkeys only work on that packaged app — not `swift run`.

Then open **API Keys** and save your PyAI key. A `.env` file is not required.

Always use `./run.sh` or `./build-app.sh`. Rebuilds keep the same bundle id, so the Accessibility toggle should stay valid.

### Build a DMG

```bash
./create-dmg.sh
```

Output: `dist/Casper-0.2.4.dmg` (version comes from `Resources/Info.plist`).

## This repository

This repo is the **macOS Swift app only** (`com.casperflow.app`). Speech-to-text is the hosted PyAI Hear API.

## License

MIT — see [LICENSE](LICENSE).
