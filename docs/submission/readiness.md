# Submission readiness

The project is prepared for a Pathway 2 demonstration. It is not ready to be represented as a verified live submission until the open items below are completed. The official SDK, two-pass workflow, audit UI, checklist input, and rehearsal tools are implemented. The Gemini key is still missing; no live model run or demo video has been established. This checklist follows the [organiser brief supplied with the project request](https://docs.google.com/document/d/1yaZoI6mscyw7QB3vEBOmzWLyTqt2O6AH7cj6BzF4M0g/view).

## Judging evidence

| Criterion | What Replay can show | Evidence still needed |
| --- | --- | --- |
| Working live demo — 50% | Native iPhone app, real video upload, Argon review, evidence reinspection, timestamp playback, deterministic response checks | A real API key and a measured fresh run, including both passes, that fits the three-minute presentation |
| Problem and usefulness — 25% | One person's recording turned into specific feedback and a practical correction | The person's name, actual task, current difficulty, and honest feedback on a real result |
| Originality and need for Argon — 15% | Reasoning over a sequence of actions, agentic video analysis, and a second pass against the original footage | Show the actual verification trace; explain the design without claiming an unmeasured model advantage or exclusive capability |
| Clear pitch — 10% | A simple upload-to-feedback flow with one visible issue | Rehearse the [run of show](live-demo.md) with the real clip and finish within three minutes |

## Required submission items

- [x] The prepared application code is pushed to the public [GitHub repository](https://github.com/Amirlaj/Encode-London-Hackathon-2026) at `bd3635c7a6b81abcb1d9e3a82468e51f9b5841c1`. Update the submission reference if the code changes after rehearsal.
- [ ] A judge-accessible three-minute demo video URL is added to [submission-draft.md](submission-draft.md).
- [ ] The team can demonstrate the app live with a real input.
- [ ] The submission names the exact Gemini model and explains its use.
- [ ] Every bracketed field in the draft is filled with a verified fact.
- [ ] The official submission form, deadline, timezone, and team details are confirmed.
- [ ] The team confirms that all demonstrated application code was written after the official kickoff. See [provenance.md](provenance.md).

## Product and technical checks

- [x] The final implementation uses the official Google Gen AI SDK: `@google/genai` 2.31.0, pinned in `package.json` and `package-lock.json` and installed locally.
- [x] The implementation has two background Argon interactions and persists the candidate report plus both interaction IDs. The server checks one decision per candidate and rejects final issues without a confirmed mapping.
- [x] The app includes an optional checklist, a “Checking the evidence” stage, and an expandable “Evidence rechecked” summary with decisions.
- [x] `npm run doctor` and `npm run rehearse` are available. The rehearsal uploads real footage and saves real results and timing without a mock fallback.
- [ ] A fresh report completes the initial review and the evidence reinspection pass. The final report contains only the findings the verification pass retains.
- [ ] A real run displays its verification status in the app and the saved report can be reopened.
- [x] Invalid reports, out-of-range timestamps, API failures, and interrupted uploads are covered by passing backend tests.
- [x] The final test commands and results are recorded below. Automated test doubles are not described as live Gemini results.
- [ ] A real key is configured on the server, has `gemini-4-argon` access, and has enough quota. The latest local doctor check reports the missing key as its only failure; a passing doctor does not check live access.
- [ ] Secrets are absent from tracked files and the recording.
- [ ] The iPhone or simulator can connect to the server in the actual presentation setup.
- [ ] The demo clip has been uploaded from the app, reviewed by Gemini, and compared with human observations.
- [ ] Timestamp playback opens the relevant part of that real clip.
- [ ] A fresh end-to-end run is timed, including upload and both model passes. Its duration is written below.
- [ ] The presenter understands the limits: an unrecorded step is not a proven omission; a second model pass is not independent proof of correctness.

## Evidence record

Fill this from an actual run. Do not copy values from a mocked test or the built-in example report.

| Evidence | Result |
| --- | --- |
| Tested application commit | [`bd3635c7a6b81abcb1d9e3a82468e51f9b5841c1`](https://github.com/Amirlaj/Encode-London-Hackathon-2026/commit/bd3635c7a6b81abcb1d9e3a82468e51f9b5841c1); pushed to public `main` |
| Exact SDK package and version | `@google/genai` 2.31.0, pinned and installed |
| Device, OS, server, network | **[PENDING]** |
| Real user and task | **[PENDING USER CONFIRMATION]** |
| Clip name and duration | **[PENDING REAL CLIP]** |
| Human's expected issue and timestamp | **[PENDING HUMAN CHECK]** |
| Human's uncertainty / unobservable details | **[PENDING HUMAN CHECK]** |
| Gemini model | `gemini-4-argon` |
| Fresh run start and finish | **[PENDING LIVE RUN]** |
| Upload-to-final-report time | **[PENDING MEASUREMENT]** |
| Initial candidates / retained findings | **[PENDING LIVE RUN]** |
| Agreement, misses, false positives | **[PENDING HUMAN COMPARISON]** |
| Backend tests | `npm test` — 24 passing tests, including installed-SDK transport and cancellation checks; no live Google calls |
| Tooling tests | `npm run test:tooling` — 9 passing tests; no Google calls |
| iOS tests | 8 unit tests and 3 UI tests passed across a full run and a targeted rerun after correcting the checklist UI selector |
| Aggregate automated checks | 44 passed; no live model access, feedback accuracy, or elapsed-time claim follows from this result |
| GitHub Actions | [Checks run 40135677863](https://github.com/Amirlaj/Encode-London-Hackathon-2026/actions/runs/40135677863) passed on the tested application commit: Node 24 install, backend tests, tooling tests |
| Physical iPhone build | Unsigned Release build passed on 24 October 2026; not installed on a physical device. An existing CameraManager Sendable warning remains. |
| Repository credential check | 47 candidate files scanned before publication; no local connection token, configured key, or Google key-pattern matches. Recording still needs checking when made. |
| Demo video URL, checked signed out | **[PENDING RECORDING]** |

The iOS full run passed 8 unit and 2 UI tests; the remaining checklist test initially failed because its accessibility identifier did not reach the child field. After the selector fix, `ReplayUITests/ReplayUITests/testGeneralHomeAndSavedVideos` passed in a targeted rerun. The local result bundles are `/tmp/Replay-build/Logs/Test/Test-Replay-2026.10.24_10-41-35-+0100.xcresult` and `/tmp/Replay-build/Logs/Test/Test-Replay-2026.10.24_10-43-57-+0100.xcresult`. These paths are local evidence, not files included in the submission repository.

## Needed from the team

1. Name the real user and choose one task they actually need help reviewing. The app can stay general-purpose; the demonstration needs a concrete problem.
2. Put the hackathon Gemini key in the local server configuration, run `npm run doctor`, and restart the server. Do not send the key in chat or commit it.
3. Supply a suitable recording the team is allowed to upload, and have a person identify the visible issue and uncertainty before the model run.
4. Run `npm run rehearse -- --help`, measure a real workflow, and compare the saved report with the human observations. Rehearse it again from the app on the presentation setup, then record the three-minute demo and share its link.
5. Confirm the kickoff eligibility, final team names, submission portal, and deadline. The prepared code is already pushed; submit the repository and video links once the remaining facts and live checks are complete.
