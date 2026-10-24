# Replay — simple feedback on your work

Record your work for up to an hour, or upload a video from Photos or Files. Optionally describe the task, intended result, and a checklist of steps. Choosing or finishing a video starts a review using **Gemini 4 Argon (`gemini-4-argon`)** and returns:

- An honest assessment: on track, needs work, or not enough evidence.
- Problems first: what went wrong, why it matters, and how to fix it.
- Timestamps that jump to the moment where each problem is visible.
- Useful strengths, a check against the intended result, and one clear next step.

There are no activity categories to choose. Replay identifies the task from the footage and your optional description. The example assembly review is clearly labeled and never substitutes for real analysis. Older saved videos and reviews remain readable.

[View the iPhone preview](docs/replay-home.png)

For the Encode London submission, start with the [readiness checklist](docs/submission/readiness.md), [submission draft](docs/submission/submission-draft.md), and [three-minute demo script](docs/submission/live-demo.md). The implementation and automated checks are available; a real event-key rehearsal, named user, and recorded demo still need to be supplied.

## Run the server

Requires **Node.js 22.13+**. Uses Google's official **`@google/genai` 2.31.0** SDK, pinned in the lockfile.

```sh
npm ci
npm run setup
```

Open `.env` and add your Google AI Studio key to `GEMINI_API_KEY`. Setup generates a random `APP_TOKEN`; keep that value for the iPhone connection. The model defaults to `gemini-4-argon`. Your key must have access and sufficient quota/billing for that model.

```sh
npm run doctor
npm start
```

`doctor` checks local configuration without sending a request or spending API credits. It does not prove model access. Restart the server after changing `.env`.

The server listens on port **8787**. With the example configuration it accepts connections on your local network. `GET /health` checks liveness. Other endpoints require `Authorization: Bearer <APP_TOKEN>`. The key is only used by the server, never embedded in the app.

## Run the iPhone app

1. Open **Replay.xcodeproj** in Xcode 15 or later (built with Xcode 26.6).
2. Choose the **Replay** scheme and an iPhone simulator or your connected iPhone. Deployment target: **iOS 17+**.
3. For a physical iPhone, select your development team under **Signing & Capabilities** and use an available bundle identifier.
4. Run the app. In **Settings**, enter the server address and the `.env` file's `APP_TOKEN`, then tap **Save & test connection**.

Use `http://127.0.0.1:8787` in the simulator. On a physical iPhone, use your Mac's LAN address, such as `http://192.168.1.20:8787`; both devices must be on the same network. Allow local network access when prompted. Debug builds permit local HTTP. Release builds keep App Transport Security enabled; use an HTTPS server for distribution.

Optionally describe the work on the home screen and expand **Add a checklist (optional)**, then tap **Upload & get feedback** or **Record a video**. After choosing a video or finishing the recording, Replay saves it and starts the review automatically. There is no second submission form. If the connection is not configured, the video is kept and its page explains what needs setting up; tap **Get feedback** after connecting. Recording and saving videos work before configuring Gemini. A real AI review requires your API key; no live Gemini request has been made as part of setup.

## How feedback is checked

1. Argon inspects the video, task description, and checklist to propose timestamped issues and corrections.
2. A separate Argon interaction receives the same video and re-inspects every proposed issue. It marks each one confirmed, unsupported, or uncertain and rewrites the report.
3. The server requires exactly one decision per candidate and a one-to-one mapping between confirmed candidates and final issues. It checks timestamps and report structure, and builds the actionable fixes and improvement moments from the retained issues. A missing or invalid verification fails the review instead of publishing the first draft.
4. The app shows **Checking the evidence**, then an **Evidence rechecked** summary with the decisions. Tap a problem's timestamp to inspect the footage yourself.

Both passes use `gemini-4-argon`, `thinking_level: "medium"`, `background: true`, and agentic video processing through the official SDK's Interactions API. The second pass is an AI recheck of the same footage, not independent ground truth or a guarantee of correctness. No Managed Agent or companion model is used. The human decides what to change; Replay does not take external actions.

## Recording and long uploads

- Records the rear camera at 720p, targets 2.2 Mbps when supported, uses HEVC when available, and includes microphone audio when permitted. About an hour is roughly 1–1.5 GB, depending on device, audio, and encoding.
- Stops at 60 minutes, 1.95 GB, or low storage, whichever happens first. Keep the app open during recording. Locking the phone, a call, overheating, or another system interruption can end a recording early. Saved movie fragments reduce the risk of losing a long take.
- Checks for at least 2.2 GB of free space before recording. The video is saved locally before review; actual available recording time also depends on battery, temperature, and storage.
- Captures go directly to persistent app storage. Completed takes are moved into the library without a second full-size copy. On launch, Replay attempts to recover playable interrupted recordings; unreadable originals are kept.
- Imports MP4, MOV, or M4V from Photos or Files without loading the entire video into memory. Videos must be no longer than 60 minutes and no larger than 2 GB. Larger imports must be trimmed or exported at a lower resolution first.
- Uploads in 8 MiB chunks. The server's saved byte offset is authoritative, including after a lost response or server restart. Keep Replay open during upload; leaving the app pauses transfer. Tap **Resume upload & review** to continue.
- After upload, the SDK uploads the file to Google's Files API in bounded chunks and runs the two background interactions. The review continues if the app is closed. Reopening the app retrieves progress and the report.
- Local videos and reports persist between app launches. The server queues reviews one at a time, persists jobs on disk, and resumes processing after restart. A completed report stays on the server for 24 hours from session creation; open the app during that time to save it locally. After expiry, the local video can be uploaded again.

## Data and deployment

This is a personal/hackathon app with one shared server connection token, not a multi-user account system. Use a persistent disk for `DATA_DIR`. The server reserves at most 8 GB across unfinished sessions and limits stored sessions to 100. A review has a two-hour processing deadline.

Originals and downloaded reports stay in the iPhone app's private storage until the session is deleted. They are excluded from iCloud device backup. Deleting the app removes them. Imported originals in Photos or Files are unaffected.

After successful analysis, the server removes its video copy and requests deletion of the Gemini file and both interactions. Failed uploads/analysis retain the server video so they can be retried. Sessions expire after 24 hours. Remote cleanup failures are retried every minute; provider outages can delay deletion. Gemini's own data handling terms still apply. The server needs to stay running for cleanup to proceed.

For public distribution, add per-user authentication, quotas, HTTPS hosting, suitable persistent storage, and a privacy policy/App Store disclosure matching your deployment. Do not ship the shared connection token as a public credential. Set `GEMINI_MODEL` on the server to change models; the configured model must support video, background Interactions, agentic processing, and structured output.

Feedback is based on visible/audible evidence. It is not a guarantee that work is correct. Fast motion, occlusion, poor audio, and sampling can limit assessments. The prompt prioritizes mistakes and concrete corrections, never forces a quota of faults, and distinguishes an unrecorded step from a proven omission. It explicitly asks for uncertainty and a `cannot_assess` verdict when needed.

## Verification

```sh
npm test
npm run test:tooling
xcodebuild -project Replay.xcodeproj -scheme Replay \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.0' \
  -derivedDataPath /tmp/Replay-build CODE_SIGNING_ALLOWED=NO test
```

Backend tests cover authentication, resumable uploads, restart recovery, retries, cleanup races, the official SDK request contract, and rejecting incomplete or unsupported review findings. Tooling tests use fake responses and never contact Gemini. Swift tests cover media limits, connection validation, persistence, older-report compatibility, verification metadata, and timestamp formatting. UI tests cover the home screen and optional checklist, saved videos, problem-first example feedback, settings, and simulator camera fallback. Camera capture and a real hour-long recording require a physical iPhone.

Live Gemini analysis and an actual hour-long camera recording still need your API key and a physical device respectively.

GitHub Actions runs the backend and tooling tests on Node 24. Automated tests use injected provider responses; they do not establish real-model accuracy or latency.

Validated on 24 October 2026: **24 backend tests, 9 tooling tests, 8 iOS unit tests, and 3 UI tests passed**, with a targeted rerun after fixing the checklist's accessibility identifier. The unsigned Release build for a physical iPhone also passed. See the [evidence record](docs/submission/readiness.md) for details and outstanding live checks.

## Rehearse with a real video

Use a short, consented clip whose correct and incorrect steps you can check yourself. Put it under the ignored `demo-videos/` directory and start the server. This command sends that clip to Google and consumes API credits:

```sh
npm run rehearse -- --video demo-videos/clip.mp4 --duration 25 \
  --task "Describe the work and intended result" --criteria-file rubric.txt
```

Supply the actual duration in seconds; the CLI does not measure it. The checklist file is optional. A private JSON artifact under `artifacts/` records the actual report, model, verification, and elapsed time. The command fails if verification is missing and reports when the upload/review exceeds the 180-second demo window. Use `npm run rehearse -- --help` for resuming an interrupted run. The clip, reports, credentials, and rehearsal artifacts are excluded from Git.

For the live demonstration, rehearse the same flow in the iPhone app, check the feedback against the footage yourself, then record a three-minute walkthrough. The built-in example is labeled sample content and is not live-model evidence.

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
