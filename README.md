# Replay — a simple iPhone video coach

Record a practice or task for up to an hour, or import a video from Photos or Files. Tell Replay what you want to improve and what a good result looks like. It uploads the video and uses **Gemini 4 Argon (`gemini-4-argon`)** to return:

- An honest assessment: on track, needs work, or not enough evidence.
- What went well and what to change.
- Timestamped observations that jump to the matching moment in your video.
- A check against your criteria and one focused next practice.

Tennis, workouts, presentations, and other tasks are supported. The example review is clearly labeled and never substitutes for real analysis.

[View the iPhone preview](docs/replay-home.png)

## Run the server

Requires **Node.js 22.13+**. No npm packages are needed.

```sh
npm run setup
```

Open `.env` and add your Google AI Studio key to `GEMINI_API_KEY`. Setup generates a random `APP_TOKEN`; keep that value for the iPhone connection. The model defaults to `gemini-4-argon`. Your key must have access and sufficient quota/billing for that model.

```sh
npm start
```

The server listens on port **8787**. With the example configuration it accepts connections on your local network. `GET /health` checks liveness. Other endpoints require `Authorization: Bearer <APP_TOKEN>`. The key is only used by the server, never embedded in the app.

## Run the iPhone app

1. Open **Replay.xcodeproj** in Xcode 15 or later (built with Xcode 26.6).
2. Choose the **Replay** scheme and an iPhone simulator or your connected iPhone. Deployment target: **iOS 17+**.
3. For a physical iPhone, select your development team under **Signing & Capabilities** and use an available bundle identifier.
4. Run the app. In **Settings**, enter the server address and the `.env` file's `APP_TOKEN`, then tap **Save & test connection**.

Use `http://127.0.0.1:8787` in the simulator. On a physical iPhone, use your Mac's LAN address, such as `http://192.168.1.20:8787`; both devices must be on the same network. Allow local network access when prompted. Debug builds permit local HTTP. Release builds keep App Transport Security enabled; use an HTTPS server for distribution.

Choose an activity, record or import, add your goal, then tap **Upload & get feedback**. Recording and saving videos work before configuring Gemini. A real AI review requires your API key; no live Gemini request has been made as part of setup.

## Recording and long uploads

- Records the rear camera at 720p, targets 2.2 Mbps when supported, uses HEVC when available, and includes microphone audio when permitted. About an hour is roughly 1–1.5 GB, depending on device, audio, and encoding.
- Stops at 60 minutes, 1.95 GB, or low storage, whichever happens first. Keep the app open during recording. Locking the phone, a call, overheating, or another system interruption can end a recording early. Saved movie fragments reduce the risk of losing a long take.
- Checks for at least 2.2 GB of free space before recording. The video is saved locally before review; actual available recording time also depends on battery, temperature, and storage.
- Captures go directly to persistent app storage. Completed takes are moved into the library without a second full-size copy. On launch, Replay attempts to recover playable interrupted recordings; unreadable originals are kept.
- Imports MP4, MOV, or M4V from Photos or Files without loading the entire video into memory. Videos must be no longer than 60 minutes and no larger than 2 GB. Larger imports must be trimmed or exported at a lower resolution first.
- Uploads in 8 MiB chunks. The server's saved byte offset is authoritative, including after a lost response or server restart. Keep Replay open during upload; leaving the app pauses transfer. Tap **Resume upload & review** to continue.
- After upload, the server streams the file to Google's Files API and runs a background Interactions API request with agentic video processing. The review continues if the app is closed. Reopening the app retrieves progress and the report.
- Local videos and reports persist between app launches. The server queues reviews one at a time, persists jobs on disk, and resumes processing after restart. A completed report stays on the server for 24 hours from session creation; open the app during that time to save it locally. After expiry, the local video can be uploaded again.

## Data and deployment

This is a personal/hackathon app with one shared server connection token, not a multi-user account system. Use a persistent disk for `DATA_DIR`. The server reserves at most 8 GB across unfinished sessions and limits stored sessions to 100. A review has a two-hour processing deadline.

Originals and downloaded reports stay in the iPhone app's private storage until the session is deleted. They are excluded from iCloud device backup. Deleting the app removes them. Imported originals in Photos or Files are unaffected.

After successful analysis, the server removes its video copy and requests deletion of the Gemini file and interaction. Failed uploads/analysis retain the server video so they can be retried. Sessions expire after 24 hours. Remote cleanup failures are retried every minute; provider outages can delay deletion. Gemini's own data handling terms still apply. The server needs to stay running for cleanup to proceed.

For public distribution, add per-user authentication, quotas, HTTPS hosting, suitable persistent storage, and a privacy policy/App Store disclosure matching your deployment. Do not ship the shared connection token as a public credential. Set `GEMINI_MODEL` on the server to change models; the configured model must support video, background Interactions, agentic processing, and structured output.

Feedback is based on visible/audible evidence. It is not a guarantee that work is correct. Fast motion, occlusion, poor audio, and sampling can limit tennis or other technique assessments. The prompt explicitly asks for uncertainty and a `cannot_assess` verdict when needed.

## Verification

```sh
npm test
xcodebuild -project Replay.xcodeproj -scheme Replay \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.0' \
  -derivedDataPath /tmp/Replay-build CODE_SIGNING_ALLOWED=NO test
```

Backend tests cover authentication, upload boundaries, resumable chunks, duplicate chunk protection, restart recovery, retry after failure, cleanup, report validation, and the Gemini request contract. Swift tests cover media limits, connection validation, persistence, and timestamp formatting. UI tests cover activity selection, sessions, the example report, settings, and simulator camera fallback. Simulator camera capture and a real hour-long device recording require a physical iPhone.

Verified on 24 October 2026: **11 backend tests, 6 iOS unit tests, and 3 UI tests passed**. The simulator Debug build and unsigned physical-iPhone Release build succeeded. Live Gemini analysis and an actual hour-long camera recording still need your API key and a physical device respectively.

The Xcode project and icon are checked in. To regenerate them after changing the file list:

```sh
python3 scripts/generate-project.py
swift -module-cache-path /tmp/replay-swift-module-cache scripts/generate-icon.swift
```

## API references

- [Gemini 4 Argon](https://ai.google.dev/gemini-api/docs/models/gemini-4-argon/)
- [Video understanding and agentic processing](https://ai.google.dev/gemini-api/docs/video-understanding)
- [Files API](https://ai.google.dev/gemini-api/docs/files)
- [Interactions API](https://ai.google.dev/gemini-api/docs/interactions-overview)
- [Structured output](https://ai.google.dev/gemini-api/docs/structured-output)

Verified against Google's documentation on 24 October 2026.
