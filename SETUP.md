# Casper Setup Guide

This guide installs Casper from the GitHub repo and checks that it works.

You are finished when you can **hold Control + Option, speak a sentence, and see that sentence appear in TextEdit**. That one test proves the app is built, the PyAI key is saved, and macOS permissions are correct.

Start after Git and Swift are already installed. The first `./run.sh` can take 1–3 minutes to compile; later launches are seconds.

| Step | You do |
|---|---|
| 1 | Clone the repo |
| 2 | Run `./run.sh` and wait for Casper to open |
| 3 | Allow Casper in System Settings (it is not notarized) |
| 4 | Save the PyAI key in **API Keys** |
| 5 | Enable Accessibility, then dictate into TextEdit |

Product features, screenshots, privacy, and architecture live in the [README](README.md).

## Contents

- [Prerequisites](#prerequisites)
- [Clean installation](#clean-installation)
- [Configure API keys](#configure-api-keys)
- [Grant macOS permissions](#grant-macos-permissions)
- [Verify the installation](#verify-the-installation)
- [Development commands](#development-commands)
- [Build a DMG](#build-a-dmg)
- [Local files and network access](#local-files-and-network-access)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### System requirements

- macOS 14 Sonoma or later
- Git
- Xcode 15+ **or** Apple command-line tools with Swift 5.9+
- Network access to `api.pyai.com` (HTTPS and WSS)

Casper is a native Swift Package Manager app. There is no Docker, database, seed, or extra service to start.

Check tools:

```bash
xcode-select -p
swift --version
git --version
```

`swift --version` must show **5.9 or newer**. If `swift` is missing:

```bash
xcode-select --install
```

Finish the macOS installer, then re-run the checks. If full Xcode is installed, set the toolchain in **Xcode → Settings → Locations → Command Line Tools**.

### API keys

| Key | Required for first run? | Used for |
|---|---|---|
| PyAI key with `hear:stream` access | **Yes** | Dictate, Ask ChatGPT voice capture, and Note taker transcription |
| OpenAI key | No | Ask ChatGPT, Rephrase, LLM tone rewriting, and note summaries |

Have the PyAI key ready before you start. OpenAI can wait. Dictate still works with local vocabulary and tone rules if no OpenAI key is set.

## Clean installation

### 1. Clone CasperFlow

```bash
git clone https://github.com/arsalan-saaslabs/CasperFlow.git
cd CasperFlow
```

Stay in this folder for every later command.

### 2. Build, install, and launch Casper

```bash
./run.sh
```

The first run can take 1–3 minutes. What this does:

1. Builds a release binary if the app is missing or Swift sources changed.
2. Packages `dist/Casper.app` and ad-hoc signs it as `com.casperflow.app`.
3. Installs it to `~/Applications/Casper.app` (and removes any old `~/Applications/CasperFlow.app`).
4. Stops a previous `CasperFlow` process.
5. Opens the **installed** app, not the copy in `dist/`.

What you should see:

- Terminal: `Launched /Users/<you>/Applications/Casper.app`
- Casper window or menu-bar ghost icon

Do **not** use `swift run`. Accessibility and global shortcuts must attach to the packaged app identity.

If Casper does not appear, look in **Finder → Go → Go to Folder… → `~/Applications`**. Open `Casper.app` from there.

### 3. Allow Casper to open

The source and DMG builds are ad-hoc signed, not Apple-notarized. macOS may block the first launch with “Apple cannot check it for malicious software.”

Allow this one app (do not switch the Mac to allow apps from anywhere):

1. Open **System Settings → Privacy & Security**.
2. Scroll to the **Security** section at the bottom.
3. Find the message that Casper was blocked because it is not from an identified developer.
4. Select **Open Anyway**.
5. Confirm with Touch ID or your Mac password, then select **Open**.

If that banner is gone, in Finder go to `~/Applications`, **Control-click** `Casper.app`, choose **Open**, and confirm.

### 4. Save the PyAI key

Save the key **inside Casper**, not in Terminal:

1. If the main window is hidden, click the Casper icon in the menu bar and choose **Open Casper**.
2. In the left sidebar, select **API Keys**.
3. Paste the PyAI key into the **PyAI** field (subtitle: “Required for Hear speech-to-text”). Leave **OpenAI** empty unless you already need Ask ChatGPT, Rephrase, or note insights.
4. Select **Save keys**. You should see a short saved confirmation on that screen.

That in-app **API Keys** page is the place the running app reads. Keys stay in local macOS `UserDefaults` on this Mac. They are not stored in Keychain and are not written to logs on purpose.

## Configure API keys

### Recommended: use Casper's settings

Save the key in the app UI. That is the location Casper reads while it is running.

1. If the main window is hidden, click the Casper icon in the menu bar and choose **Open Casper**.
2. Left sidebar → **API Keys**.
3. Paste into the **PyAI** field. Do not paste it into **OpenAI**.
4. Select **Save keys** and wait for the saved confirmation.

Leave **OpenAI** empty unless you already need Ask ChatGPT, Rephrase, or note insights.

Do not put the key in Terminal, chat, or a committed file. Optional `.env` fallback is below and is only for local PyAI development.

### Optional: repository `.env` fallback

Keys in the app are preferred. For a file-based PyAI fallback:

```bash
cp .env.example .env
```

Set only:

```dotenv
PYAI_API_KEY=
```

Put the real value in `.env` on your machine. Never commit `.env` or a live key.

The app does **not** read `OPENAI_API_KEY` from `.env`. Save OpenAI inside Casper. In-app PyAI wins over environment and `.env`.

## Grant macOS permissions

Casper's **Permissions** section links to the relevant System Settings pages and can recheck Accessibility status.

### Accessibility

Accessibility is required for the shortcut and for inserting text into another app.

1. In Casper, open **Permissions**.
2. Use the link to **System Settings → Privacy & Security → Accessibility**.
3. Enable **Casper** from the exact app that is running:
   - source build: `~/Applications/Casper.app`
   - release/DMG installation: `/Applications/Casper.app`
4. Come back to **Permissions** and recheck if the status is still untrusted.

Do **not** enable Terminal, Cursor, `dist/Casper.app`, or a copy still sitting in a mounted DMG.

If Casper remains untrusted after a rebuild:

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Remove the stale Casper entry.
3. Add the exact installed `Casper.app` again.
4. Return to **Permissions** and recheck.

### Microphone

Microphone is required for Dictate, voice-based Ask ChatGPT, microphone notes, and Mic + system notes. macOS asks the first time Casper starts one of these captures. Allow it.

### Screen Recording

Screen Recording is required only for **System audio** or **Mic + system** notes. Casper discards video frames; the permission is how macOS exposes playback audio.

1. Open **Note taker**.
2. Choose **System audio** or **Mic + system**.
3. Start once to trigger the prompt.
4. Grant Screen Recording.
5. Restart Casper if macOS asks, then retry.

## Verify the installation

### Dictate smoke test

1. Open **TextEdit**, create a document, click in the body.
2. Hold **Control + Option**.
3. Speak one short sentence.
4. Release.
5. Confirm the floating HUD appeared and the sentence landed in TextEdit.
6. Open Casper **History** and confirm a Dictate entry exists.

Default shortcuts (change them later in settings if you want):

| Action | Shortcut |
|---|---|
| Dictate | Control + Option |
| Ask ChatGPT | Option + Command |
| Rephrase selection | Control + Command |

Setup succeeded when all of these are true:

- Casper is running from `~/Applications/Casper.app`
- PyAI key is saved
- Accessibility is on for that exact app
- Holding **Control + Option** pastes into TextEdit
- History shows the Dictate entry

Stop here unless you need OpenAI, system-audio notes, or packaging.

### Optional OpenAI smoke tests

In **API Keys**, save an OpenAI key, then:

- Hold **Option + Command**, ask for a short sentence, and confirm it pastes.
- Select a short paragraph, press **Control + Command**, and confirm it is replaced.

Ask / Rephrase input is capped at 2,000 characters. Note insights are capped at 24,000 characters.

### Note taker smoke test

1. Open **Note taker** → **Microphone**.
2. Start, speak briefly, stop.
3. Confirm a local note appears.
4. Generate insights only if an OpenAI key is saved.

## Development commands

### Compile only

```bash
# Debug build
swift build

# Optimized release build
swift build -c release
```

These commands compile the executable but do not create or launch the app bundle required for Accessibility testing.

### Force a packaged rebuild

```bash
./build-app.sh
./run.sh
```

Use this after changing `Package.swift`, build scripts, `Resources/Info.plist`, icons, or other non-Swift resources. `run.sh` does not treat those files as “needs rebuild.”

### Build if needed and launch

```bash
./run.sh
```

This is the normal command after Swift source changes. It rebuilds when sources are newer than the installed binary, then relaunches `~/Applications/Casper.app`.

### Validate repository files

```bash
for script in run.sh build-app.sh create-dmg.sh; do bash -n "$script"; done
plutil -lint Resources/Info.plist
swift build -c release
```

There is no test target or linter yet. A green build plus the Dictate smoke test is the current check.

## Build a DMG

```bash
./create-dmg.sh
```

This runs `build-app.sh` first, so it also replaces `~/Applications/Casper.app`. Output:

- `dist/Casper-<version>.dmg` (version from `Resources/Info.plist`)
- `dist/Casper.dmg` symlink

The app is ad-hoc signed, not notarized. Downloaded copies may need **right-click → Open**. Developer ID + notarization is outside these scripts.

End users drag Casper into `/Applications` and launch **that** copy, not the one inside the disk image.

## Local files and network access

### Files created on the Mac

| Data | Location |
|---|---|
| Source install | `~/Applications/Casper.app` |
| Release / DMG install | `/Applications/Casper.app` |
| Build artifacts | `.build/` and `dist/` |
| History | `~/Library/Application Support/CasperFlow/history.json` |
| Notes | `~/Library/Application Support/CasperFlow/notes.json` |
| Vocabulary | `~/Library/Application Support/CasperFlow/vocabulary.json` |
| Diagnostics | `~/Library/Application Support/CasperFlow/casperflow.log` |
| Preferences and saved API keys | macOS `UserDefaults` |

Nothing above is cloud-synced. Microphone and system audio stay in memory; they are not saved as media files.

### Outbound network access

Allow TLS on port 443 to:

- `api.pyai.com` — HTTPS and WSS for health checks and streaming transcription
- `api.openai.com` — HTTPS, only when OpenAI features are configured

Casper inserts plain text at the caret. It does not press Return. Terminals are not blocked — check the focused app before dictating at a prompt.

## Troubleshooting

### `swift` is missing or too old

- Run `xcode-select --install` and finish the installer.
- Verify `swift --version` reports Swift 5.9+.
- If full Xcode is installed, select the correct command-line tools in Xcode settings.

### Global shortcuts or paste do not work

- Confirm the exact installed Casper app is enabled under Accessibility.
- Do not approve Terminal, Cursor, `dist/Casper.app`, or the mounted DMG instead.
- Focus a writable text field before Dictate, Ask, Rephrase, or History paste.
- Remove and re-add the Accessibility entry if the toggle looks enabled but Casper still reports it is untrusted.

### PyAI Hear is unavailable

- Confirm the PyAI key is present and has `hear:stream` access.
- Confirm the network can reach `api.pyai.com` over HTTPS/WSS.
- Correct the issue, then use **Restart** in Casper's error banner or menu bar.

### Ask, Rephrase, tone rewriting, or note insights fail

- Save a valid OpenAI key in Casper's **API Keys** section.
- Confirm the network can reach `api.openai.com`.
- Keep Ask and selection/tone rewrite input at or below 2,000 characters.
- Keep note-insight transcripts at or below 24,000 characters.
- Dictate continues with local tone rules if OpenAI rewriting is unavailable.

### System-audio notes are empty

- Start a system-audio capture once to trigger Screen Recording permission.
- Enable Casper under **System Settings → Privacy & Security → Screen Recording**.
- Restart Casper after changing the permission, then retry.

### A code or resource change does not appear

- For Swift source changes, rerun `./run.sh`.
- For package, script, property-list, icon, or resource changes, run `./build-app.sh`, then `./run.sh`.

### Gatekeeper blocks Casper

The build is not notarized. Allow this one app:

1. **System Settings → Privacy & Security** → scroll to **Security**.
2. Select **Open Anyway** next to the Casper blocked message.
3. Confirm with Touch ID or password, then **Open**.

If the banner is gone: Finder → `~/Applications` → Control-click `Casper.app` → **Open**. Launch the installed app, not a copy inside a mounted DMG.

## Related documentation

- [README](README.md) — features, workflows, screenshots, architecture, privacy
- [LICENSE](LICENSE) — MIT
