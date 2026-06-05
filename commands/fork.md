---
description: "Fork at a decision point in the most recent decision log. Usage: /decision-log:fork <decision_number> <context>"
---

The user has invoked `/decision-log:fork $ARGUMENTS`.

Parse `$ARGUMENTS`: the first token is the decision number, the rest is the context/reasoning for forking.

**Step 1: Load the decision log**
Read `/tmp/decision-log.json` (from the most recent analysis). If it doesn't exist, tell the user to run `/decision-log:analyze` first.

**Step 2: Find the fork point**
Look up the decision by number. Extract its full details: what was decided, alternatives, rationale, dependencies, dependents.

**Step 3: Analyze the cascade**
Identify all downstream decisions that depend on the forked decision (directly and transitively via the dependency chains). List what will need to change.

**Step 4: Produce fork instructions**
Generate a clear re-dispatch prompt that can be given to a coding agent. The prompt should:
- Explain the original decision and why it's being reversed
- Include the user's context/reasoning for the fork
- List all downstream decisions that need to be reconsidered
- Reference the specific code files and locations affected
- Be self-contained — the coding agent should be able to act on this without additional context

**Step 5: Present to user**
Show the fork analysis:
- The decision being forked
- The cascade: N downstream decisions affected
- The re-dispatch prompt (formatted as a code block they can use)
- Ask if they want to proceed with the re-dispatch
