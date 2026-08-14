# Casper Setup Guide

This guide covers installing Casper from source on a clean Mac, configuring its API keys and permissions, validating the installation, and rebuilding or packaging the app during development.

For product workflows, features, screenshots, privacy, and architecture, see the [main README](README.md).

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
- Xcode 15+ or Apple command-line tools with Swift 5.9+
- Internet access to PyAI and, for optional features, OpenAI

Casper is a native Swift Package Manager project. It has no third-party Swift package dependencies, database, migration, seed, Docker container, or separately managed service.

### API keys

| Key | Required for |
|---|---|
| PyAI key with `hear:stream` access | Dictate, Ask ChatGPT voice capture, and Note taker transcription |
| OpenAI key | Ask ChatGPT, explicit Rephrase, LLM tone rewriting, and note summaries/action items |

Dictate can use local vocabulary and tone rules without an OpenAI key.

## Clean installation

### 1. Install Apple's development tools

If `swift` is unavailable, install the command-line tools:

```bash
xcode-select --install
```

Finish the macOS installer, then verify the active tools:

```bash
xcode-select -p
swift --version
git --version
```

`swift --version` must report Swift 5.9 or newer. If you use the full Xcode application, select the correct toolchain from **Xcode → Settings → Locations → Command Line Tools**.

### 2. Clone CasperFlow

```bash
git clone https://github.com/arsalan-saaslabs/CasperFlow.git
cd CasperFlow
```

### 3. Build, install, and launch Casper

```bash
./run.sh
```

The supported source workflow launches a packaged application instead of a bare Swift executable. When a build is needed, `run.sh` calls `build-app.sh`, which:

1. runs `swift build -c release`;
2. creates `dist/Casper.app`;
3. ad-hoc signs it with bundle identifier `com.casperflow.app`;
4. replaces `~/Applications/Casper.app`;
5. removes the legacy `~/Applications/CasperFlow.app` path.

After the conditional build, `run.sh` stops an older `CasperFlow` process and launches the installed source build.

Do not use `swift run` for normal interactive testing. Accessibility approval and global shortcuts must attach to the stable packaged app identity.

## Configure API keys

### Recommended: use Casper's settings

1. Open Casper.
2. Select **API Keys** in the sidebar.
3. Enter the PyAI key.
4. Enter an OpenAI key if OpenAI-backed features are needed.
5. Select **Save keys**.

Keys saved in the app remain in local macOS `UserDefaults`. They are not stored in Keychain and are not intentionally written to logs.

### Optional: repository `.env` fallback

For local PyAI development, create an ignored `.env` file:

```bash
cp .env.example .env
```

Set the PyAI value:

```dotenv
PYAI_API_KEY=your_key_here
```

The current source loader does not read `OPENAI_API_KEY` from `.env`. Configure the OpenAI key inside Casper. Never commit `.env` or a real key.

## Grant macOS permissions

Casper's **Permissions** section links to the relevant System Settings pages and can recheck Accessibility status.

### Accessibility

Accessibility is required for global shortcuts, reading a selection, and inserting or pasting text into another application.

Enable the exact app that is running:

- source build: `~/Applications/Casper.app`
- release/DMG installation: `/Applications/Casper.app`

Do not enable Terminal, Cursor, the `dist/Casper.app` build artifact, or an app still mounted inside a DMG when you intend to run the installed copy.

If Casper remains untrusted after a rebuild:

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Remove the stale Casper entry.
3. Add the exact installed `Casper.app` again.
4. Return to Casper's **Permissions** section and select the recheck action.

### Microphone

Microphone permission is required for Dictate, voice-based Ask ChatGPT, microphone notes, and Mic + system notes. macOS requests access the first time Casper starts one of these captures.

### Screen Recording

Screen Recording permission is required only for **System audio** or **Mic + system** notes.

1. Open **Note taker**.
2. Select **System audio** or **Mic + system**.
3. Start Note taker once to trigger the macOS prompt.
4. Grant Screen Recording access.
5. Restart Casper if macOS requests it, then retry the capture.

Casper discards screen video frames and does not save a screen recording. The permission is used to obtain system playback audio through ScreenCaptureKit.

## Verify the installation

### Dictate smoke test

1. Open TextEdit and click inside a writable document.
2. Hold **Control + Option**.
3. Speak a short sentence.
4. Release the shortcut.
5. Confirm the floating HUD appeared and text was inserted into TextEdit.
6. Open Casper's **History** section and confirm the Dictate entry exists.

### Optional OpenAI smoke tests

- Hold **Option + Command**, ask for a short sentence, and confirm the result is pasted.
- Select a short paragraph, press **Control + Command**, and confirm the rewritten selection replaces it.

### Note taker smoke test

1. Open **Note taker**.
2. Choose **Microphone**.
3. Start capture, speak briefly, then stop.
4. Confirm a local note is created.
5. If an OpenAI key is configured, generate note insights.

## Development commands

### Compile only

```bash
# Debug build
swift build

# Optimized release build
swift build -c release
```

These commands compile the executable but do not create or launch the stable app bundle required for complete Accessibility testing.

### Force a packaged rebuild

```bash
./build-app.sh
./run.sh
```

Use this after changing `Package.swift`, build scripts, `Resources/Info.plist`, icons, or other resources. `run.sh` automatically detects newer Swift source files, but it does not use every non-source file to decide whether a rebuild is needed. Running it after `build-app.sh` stops any older process and launches the newly installed bundle.

### Build if needed and launch

```bash
./run.sh
```

This is the normal development command after Swift source changes.

### Validate repository files

```bash
for script in run.sh build-app.sh create-dmg.sh; do bash -n "$script"; done
plutil -lint Resources/Info.plist
swift build -c release
```

The package currently has no automated test target or configured linter. A successful build plus manual Dictate, paste, permission, and Note taker smoke tests are the current validation path.

## Build a DMG

```bash
./create-dmg.sh
```

This command first runs `build-app.sh`, so it also replaces `~/Applications/Casper.app`. It then creates:

- `dist/Casper-<version>.dmg`
- `dist/Casper.dmg` as a convenience symlink

The version comes from `Resources/Info.plist`. The generated app is ad-hoc signed and not notarized; downloaded copies may require right-clicking Casper and selecting **Open**. Public distribution without that step requires a Developer ID and Apple notarization outside the current scripts.

## Local files and network access

### Files created on the Mac

| Data | Location |
|---|---|
| Source installation | `~/Applications/Casper.app` |
| Repository build output | `.build/` and `dist/` |
| History | `~/Library/Application Support/CasperFlow/history.json` |
| Notes | `~/Library/Application Support/CasperFlow/notes.json` |
| Vocabulary | `~/Library/Application Support/CasperFlow/vocabulary.json` |
| Diagnostics | `~/Library/Application Support/CasperFlow/casperflow.log` |
| App preferences and saved API keys | macOS `UserDefaults` |

History, notes, vocabulary, preferences, keys, and logs have no built-in cloud-sync step. Microphone and system audio are processed in memory rather than saved as media files.

### Outbound network access

Allow normal TLS traffic on port 443 to:

- `api.pyai.com` over HTTPS and WSS for health checks and streaming transcription;
- `api.openai.com` over HTTPS for configured OpenAI-backed text actions.

Casper does not invoke a shell or synthesize Return. It inserts plain text into the focused UI element. Terminal applications are not currently blocked, so verify the active target before using a voice action at a terminal prompt.

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
- For package, script, property-list, icon, or resource changes, run `./build-app.sh`, then `./run.sh` to stop any older process and launch the new build.

### Gatekeeper blocks Casper

For the current ad-hoc-signed source or DMG build, right-click `Casper.app`, select **Open**, and confirm the prompt. Launch the installed app rather than a copy inside the mounted disk image.

## Related documentation

- [README](README.md): features, workflows, screenshots, architecture, privacy, and troubleshooting
- [LICENSE](LICENSE): MIT license
