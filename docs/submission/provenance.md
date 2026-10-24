# Build provenance and model use

This file records what the team can support with evidence. Complete the remaining fields before submission.

## Repository history

Repository: [Amirlaj/Encode-London-Hackathon-2026](https://github.com/Amirlaj/Encode-London-Hackathon-2026).

The repository history inspected during preparation contains these recorded timestamps:

| Commit | Recorded author and committer time | Subject |
| --- | --- | --- |
| `b34f3d5` | `2026-10-24T16:59:50+03:00` | Initial commit |
| `99f6595` | `2026-10-24T22:28:57+01:00` | everything is added |
| `b54bb32` | `2026-10-24T22:36:34+01:00` | updated |

These timestamps place the recorded commits on 24 October 2026. Commit timestamps alone do not establish when every line was written. The team must confirm the official kickoff time and the origin of the demonstrated code. Preserve the history and disclose any starter code or pre-existing assets.

- Official kickoff date, time, and timezone: **[CONFIRM WITH ORGANISERS]**
- Team confirmation that demonstrated application code was written after kickoff: **[PENDING]**
- Pre-existing code, templates, or assets used: **[LIST, OR CONFIRM NONE BEYOND DECLARED LIBRARIES/FRAMEWORKS]**
- Final submitted commit SHA: **[ADD AFTER FINAL PUSH]**

AI coding assistance was used to create and revise Replay. Do not describe the project as written without AI assistance. The application is built with Apple's SwiftUI and AVFoundation frameworks, a Node.js server, and the Google Gen AI SDK. The SDK dependency is pinned in the package files.

## Model-use statement

| Component | Exact model / API | Purpose |
| --- | --- | --- |
| Initial review | `gemini-4-argon`, Interactions API | Identify the work, inspect the recording, and propose evidence-backed issues and fixes |
| Evidence reinspection | `gemini-4-argon`, Interactions API | Revisit the original video against the candidate findings and decide which are supported |
| Video storage for inference | Gemini Files API | Supply the uploaded video to the review workflow |
| App and deterministic checks | Local Swift/Node.js code | Record/import, resume uploads, validate report structure and timestamps, and display/play back evidence |

SDK package and installed version: **`@google/genai` 2.31.0**. `package.json`, `package-lock.json`, and the locally installed package agree on that version.

The implemented configuration uses `thinking_level: "medium"`, `background: true`, agentic video processing, and a 16,384-token output cap for each interaction. The initial review and evidence recheck are separate interactions against the same uploaded video. The candidate report and both interaction IDs are persisted for recovery. No Managed Agent, companion model, Live API, image-generation model, or on-device model is claimed. Background execution here supports asynchronous processing; the project does not use long output generation beyond 65,536 tokens.

## What verification means here

The model's second pass reviews the first pass's candidate findings against the original footage. It assigns confirmed, unsupported, or uncertain to every candidate, with a reason, and produces a revised report. Both passes may share the same model's limitations. This is not an objective safety inspection or certification.

The deterministic checks require exactly one decision for every candidate, a one-to-one mapping between confirmed candidates and final issues, and valid mappings for negative checklist assessments. Suggested fixes and problem moments are rebuilt from the confirmed issues. Required issue details and timestamp bounds are also checked. This enforces the structure and consistency of the result; it cannot independently establish that a visual judgment is true or rule out unsupported prose in every report section.

The final report records the model, completion time, candidate/confirmed/removed counts, and individual decisions. The iPhone shows those in an expandable audit summary. A separate human annotation of the demo clip supplies the comparison for whether the feedback is useful and correct. Keep the outcome of that comparison, including disagreements, in [readiness.md](readiness.md).

## Rehearsal evidence

`npm run doctor` checks local configuration and whether private files are ignored by Git. It makes no network requests. At preparation time, the missing Gemini key was its only failed check. That check does not establish model access or remaining credits.

`npm run rehearse` sends a chosen real clip to the running server, waits through both passes, and writes actual stage timing, the report, and verification details to an ignored file in `artifacts/`. It uses no mock fallback. Its 180-second success threshold measures the workflow, not the full presentation or the correctness of its feedback. The CLI requires the caller to provide the actual clip duration. See [live-demo.md](live-demo.md) for the command and interpretation.

## Claims that need live evidence

At preparation time, no live Gemini run, measured turnaround, or finished demo video had been established. Do not convert automated test results or the illustrative in-app report into claims about live AI performance.

The app supports up to an hour of recording/upload, subject to device and file limits. Full-hour recording reliability and model accuracy over an hour require physical-device and real-input testing. The three-minute demo should use a shorter measured input. Do not claim full-hour feedback in three minutes without evidence.

Argon is the chosen reasoning and video model. The project does not yet establish that an alternative model could not implement the same workflow, nor that the application fills the entire context window or uses long output generation. Explain the actual use of video reasoning and reinspection instead of claiming an untested exclusive capability.

## Source of the challenge requirements

The requirements used for these materials came from the organiser brief supplied by the user: [Build with Gemini 4 Argon: Autonomous Agents & Multimodal Applications](https://docs.google.com/document/d/1yaZoI6mscyw7QB3vEBOmzWLyTqt2O6AH7cj6BzF4M0g/view). Confirm the final rules and eligibility with the organisers if the brief changes.
