# Three-minute demo, without slides

Demonstrate one real person's task using a fresh upload and real Gemini output. Use a short clip whose visible result has already been checked by the person. A 20–45 second clip is a sensible starting point for rehearsal; it is not a latency guarantee.

## Before recording or presenting

1. Finish [readiness.md](readiness.md) and run `npm run doctor`. It makes no network calls and does not prove model access. Configure the API key, then confirm a real run has `gemini-4-argon` access and enough quota for rehearsal and judging. Keep the key off screen.
2. Use the same Mac, iPhone or simulator, network, and server configuration that will be used during judging. A simulator can import a clip; recording with the camera needs a physical iPhone.
3. Choose an owned or permissioned recording of the named user's actual task. Include one visible issue and enough context to assess it. Do not stage an unsafe mistake.
4. Write down the human observation and approximate timestamp before calling the model. Keep the original clip unchanged. Also note anything the video cannot show.
5. Run the rehearsal command below, then rehearse from the actual app. Measure from selecting the video to the final report. Aim to have feedback by about 1:20 in the presentation. A pipeline finishing within 180 seconds still may leave too little time to show the result; use a clip that leaves time for explanation.
6. Close private windows, silence notifications, check the phone's battery, and verify that the video picker can find the clip quickly. Leave the app open during upload.
7. Record a genuine successful rehearsal for the required submission video and as a disclosed backup. Test the sharing link in a signed-out browser. Never label a saved result as a live run.

## Measure a real run

After adding the Gemini key and starting the server, use an owned or permissioned clip. Replace the filename, duration, task, and checklist with the real values:

```sh
npm run doctor
npm run rehearse -- --video demo-videos/clip.mp4 --duration 25 \
  --task "Describe the actual task and intended result" \
  --criteria-file demo-videos/checklist.txt
```

`--duration` must be the clip's actual duration in seconds; the tool does not measure it. The checklist file is optional and contains the checks you want reviewed. The upload and model calls spend API credits. The tool saves the real report, model, stages, verification decisions, and total elapsed time in an ignored `artifacts/rehearsal-<session-id>.json` file.

Exit code 0 means the workflow returned a completed AI recheck within 180 seconds; it does not mean the feedback is correct or that the whole presentation fits in three minutes. Exit code 1 is a setup, server, or model failure. Exit code 2 means the workflow finished too slowly or did not finish within the polling deadline. Compare the feedback with the person's observations in every case.

If a connection drops, rerun with the original arguments plus `--resume artifacts/rehearsal-<session-id>.json`. The video and context must be unchanged. The clock includes time spent paused. Keep raw clips and private reports out of Git; copy only consented, redacted evidence into submission materials if needed.

## Run of show

| Time | On screen | What to say |
| --- | --- | --- |
| 0:00–0:20 | Replay home screen | “This is for **[NAME]**, who **[DOES TASK]**. They need to check **[SPECIFIC THING]**. Today that means **[CURRENT DIFFICULTY]**.” |
| 0:20–0:40 | Task description, optional checklist, then video picker | “Here is their recording. These are the steps they needed to get right.” Choose the real clip and start a fresh review. |
| 0:40–1:20 | Upload, review, and “Checking the evidence” | “Argon reviews the work, then a separate pass checks each proposed problem against the original footage. Every candidate needs a decision and a reason. Only confirmed issues reach the final report.” Show real stages only. |
| 1:20–2:05 | Final report and one timestamp | “The main finding is **[READ THE ACTUAL FINDING]**. Let’s check it.” Tap the timestamp and show the visible evidence. |
| 2:05–2:35 | Suggested fix and “Evidence rechecked” summary | Explain how the finding affects this person's task. Expand the decisions and show how many candidates were retained. If the model disagrees with the human observation, say so. |
| 2:35–2:50 | Limits or uncertainty in the report | “This part cannot be confirmed from the camera angle. Replay should leave it uncertain, not invent a fault.” Use a limitation actually present in the output. |
| 2:50–3:00 | App and repository link ready for questions | “**[NAME]** can now **[CONCRETE NEXT ACTION SUPPORTED BY THE REPORT]**. The code and reproduction steps are in the repository.” |

The times are a rehearsal plan. If the pipeline has not returned a report by the point needed to finish, show the real state and explain the delay. A saved report or recording can be shown only after saying when it was produced. If timing is unreliable, shorten the genuine clip and rehearse again before submission.

## Two-minute Q&A

**Why Gemini 4 Argon?**

“The useful part is reasoning about the order and outcome of actions in video, then revisiting the evidence for a claim. We use Argon with agentic video processing and a second review pass. We have not run a comparison that proves another model cannot do it.”

**What is the verification loop?**

“The first pass proposes findings. A separate interaction checks every candidate against the original video and marks it confirmed, unsupported, or uncertain. Code requires one decision per candidate and permits only confirmed candidates in the final issues. Fixes and problem timestamps are rebuilt from those issues. The model can still be wrong, so the person can inspect the footage and compare it with their own observation.”

**Is that an objective correctness guarantee?**

“No. Structural checks are deterministic, but visual judgments remain uncertain. They also do not establish the truth of every sentence in the report. Replay asks the model to report insufficient evidence where needed. It is feedback for a person to review, not certification.”

**Who actually needs this?**

“**[NAME]** uses it for **[TASK]**. Their current difficulty is **[REAL DETAIL]**. In our test, **[OBSERVED RESULT, NOT AN INVENTED SAVING OR TESTIMONIAL]**.”

**Can it review an hour in three minutes?**

“The app supports recording and uploading up to an hour. Our measured demo uses **[LENGTH]** and took **[TIME]**. We have not established a three-minute turnaround for an hour-long recording.”

**Which models and agents are used?**

“`gemini-4-argon` performs both passes through `@google/genai` 2.31.0 and the Interactions API. We use medium thinking, background execution, and agentic video processing. We do not use Managed Agents, Live API, or image-generation companions in this build.”

**What happens to the footage?**

“The user chooses the video. It is uploaded to our review server and Google for analysis. The app keeps its local copy and report. After a successful review, the server removes its video and requests deletion of the Google file and interactions. Failed cleanup is retried. The precise behavior and limits are documented in the repository.”

**What remains before a public release?**

“Individual accounts and quotas, hosted HTTPS service, and evaluation with more of our intended users. The shared token setup is for this personal demo.”

## Submission recording

Record the same product flow, with narration, in at most three minutes. Show the real user problem, fresh input, actual processing, result, and timestamp playback. Keep credentials and unrelated private information out of the recording. If the video is edited, preserve an honest account of processing time and disclose cuts or time compression. Submit the video URL and be ready to perform the flow live.
