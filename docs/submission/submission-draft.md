# Replay — feedback you can check against your work

**Submission draft.** Replace the bracketed fields and complete the live checks in [readiness.md](readiness.md) before submitting. The implementation and model-use statements below must match the final demonstrated build.

## Submission fields

| Field | Value |
| --- | --- |
| Project name | Replay |
| Track | Pathway 2: The Real World, Hard Tech & Multimodal Creation |
| Repository | https://github.com/Amirlaj/Encode-London-Hackathon-2026 |
| Demo video | **[ADD A JUDGE-ACCESSIBLE 3-MINUTE VIDEO URL]** |
| Team members | **[ADD NAMES]** |
| Real user | **[FIRST NAME, ROLE OR SITUATION]** |
| Task demonstrated | **[ONE SPECIFIC TASK THAT PERSON ACTUALLY DOES]** |
| Tested application commit | `bd3635c7a6b81abcb1d9e3a82468e51f9b5841c1` — already pushed; update if code changes after rehearsal |

## One sentence

Replay helps **[USER]** spot mistakes in **[TASK]** by reviewing a video, checking the evidence again, and showing the exact moment and a practical fix.

## The problem

**[USER]** needs to know whether **[SPECIFIC TASK OR STEP]** was done correctly. Their current approach is **[HOW THEY CHECK TODAY]**. The difficulty is **[A REAL OBSERVED PROBLEM: FOR EXAMPLE, REVIEWING A LONG RECORDING OR NOT KNOWING WHICH STEP CAUSED A BAD RESULT]**.

Replay gives them feedback tied to their own footage. The general app accepts different tasks; this demo follows one person's actual use case.

## What we built

Replay is a native iPhone app. The user can describe the task and add a checklist, then record or upload a video. The app returns problems first: what happened, why it matters, and how to fix it. Tapping a timestamp opens the relevant part of the recording.

The server asks Gemini 4 Argon to review the work, then starts a separate interaction to reinspect the original footage against the candidate findings. Each candidate must receive one decision: confirmed, unsupported, or uncertain, with a reason. Only confirmed candidates can become final issues. Code checks that mapping, rebuilds suggested fixes and problem moments from the retained issues, and rejects invalid timestamps or incomplete reports. The app shows “Checking the evidence” while this runs and an expandable “Evidence rechecked” summary when it completes.

The user chooses which footage to submit and remains responsible for deciding what to do with the feedback. Replay does not act on equipment or external accounts.

## How we use Gemini

**Model used:** `gemini-4-argon` for both the initial video review and the evidence reinspection pass. The server uses the official Google Gen AI JavaScript SDK, `@google/genai` **2.31.0**, and the Interactions API, with `thinking_level: "medium"`, `background: true`, and agentic video processing. It saves the first report and both interaction IDs so interrupted work can resume. The submission does not claim use of Managed Agents or companion models.

We chose Argon for a workflow that reasons about sequences of actions and checks a finding against the original footage. A single screenshot often misses the order of steps or the state before and after an action. Agentic video processing lets the model revisit relevant parts of a recording while producing a structured explanation.

The app supports videos up to an hour. The live demo uses **[MEASURED DEMO CLIP LENGTH]** so the judges can see a fresh upload, review, and result within three minutes. We do not claim to have proved that another model could not build this workflow, or that a full hour can be reviewed within the demo time limit.

## What we verified

Automated checks cover resumable uploads, restart recovery, authentication, invalid reports, timestamp bounds, and iPhone navigation and persistence. All 44 checks passed: 24 backend, 9 tooling, 8 iOS unit, and 3 iOS UI tests. The iOS result combines a full run with a successful targeted rerun after fixing the checklist test's accessibility selector. The backend includes offline transport and cancellation checks against the installed SDK. None of these results are live Google calls. The second model pass checks candidate findings against the footage; it is not an independent guarantee of correctness. The code checks issue mappings and report structure, not the truth of every sentence.

The repository includes `npm run doctor` for local configuration checks and `npm run rehearse` to upload a real clip, wait for both model passes, and save the report and elapsed time. The rehearsal tool has no mock fallback. It has not yet supplied a live result for this submission.

For the live evidence, **[USER]** reviewed **[CLIP NAME]** before submission and recorded **[THE VISIBLE ISSUE / EXPECTED RESULT]**. A fresh Argon run took **[END-TO-END TIME, INCLUDING UPLOAD]**. It **[STATE WHAT THE RUN ACTUALLY FOUND AND WHETHER IT AGREED WITH THE HUMAN OBSERVATION]**. Record any false positives or missed issues rather than omitting them.

## Limits and next step

Replay can miss details in fast motion, poor audio, or obscured footage. An unrecorded step is not proof that someone skipped it. If the video cannot support a conclusion, the useful answer is to ask for better evidence.

The current server is designed for a personal or hackathon demo with a shared connection token. Before offering it publicly, we would add individual accounts and quotas, then evaluate it with more recordings from the intended users.

## Build provenance

The repository's recorded commits begin on 24 October 2026. **[CONFIRM THE OFFICIAL KICKOFF TIME AND THAT THE DEMONSTRATED APPLICATION CODE WAS WRITTEN AFTER IT.]** AI coding assistance was used. See [provenance.md](provenance.md) for the evidence and disclosures to retain.
