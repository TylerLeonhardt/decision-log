---
description: "Analyze a Copilot CLI session and produce a decision log with adversarial review. Pass a session ID, branch name, or 'latest'."
---

The user has invoked `/decision-log:analyze $ARGUMENTS`.

Your job is to orchestrate the full decision analysis loop:

**Step 1: Extract the session**
Run `${PLUGIN_ROOT}/scripts/extract-session.sh $ARGUMENTS` to find the session. If `$ARGUMENTS` is empty, use `latest`.

**Step 2: Parse the events**
Run `${PLUGIN_ROOT}/scripts/parse-decisions.sh <events_path>` (using the events_path from step 1) to get filtered decision-relevant events. Save output to `/tmp/parsed-events.jsonl`.

**Step 3: Invoke the Decision Analyst**
Use the `decision-log:decision-analyst` agent to analyze the parsed events. The analyst will:
- Read `/tmp/parsed-events.jsonl`
- Identify explicit breadcrumbs and implicit decisions
- Produce `/tmp/decision-log.json`, `/tmp/decision-log.md`

**Step 4: Invoke the Adversary**
Use the `decision-log:adversary` agent to review the decision log and code. The adversary will:
- Read `/tmp/decision-log.json`
- Review the git diff on the branch
- Produce `/tmp/adversary-findings.json`
- If the adversary auto-forks any decisions, the loop repeats from step 3

**Step 5: Generate the HTML artifact**
Run `${PLUGIN_ROOT}/scripts/generate-html.sh` to produce `/tmp/decision-log.html`.

**Step 6: Present results**
- Post the markdown summary from `/tmp/decision-log.md` in chat
- Append the adversary's escalated findings (from `/tmp/adversary-findings.json`) to the message
- Include a brief auto-fork history: "The adversary caught N issues and auto-fixed them before your review: [brief list]"
- Send the HTML artifact to the user using the `send_file` tool with `/tmp/decision-log.html`

**Loop behavior:**
If the adversary produced auto-forks, go back to step 3 and re-run with the updated code. Keep looping until the adversary is satisfied (no more auto-forks) or escalates remaining concerns. Track the round number and report it in the summary.
