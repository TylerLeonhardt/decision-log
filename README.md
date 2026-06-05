# decision-log

An open-plugins plugin that brings structured decision review to AI coding sessions.

Instead of reviewing every line of code, review the **decisions** that shaped it. An adversarial agent catches bugs and weak reasoning before you see anything — you only review what needs human judgment.

## Components

- **Decision Breadcrumbs Skill** — Injected into coding agents to log decision points as they work
- **Decision Analyst Agent** — Reads session history and synthesizes a structured decision log
- **Adversary Agent** — Reviews decisions + code, auto-forks fixable issues, escalates the rest
- **`/analyze` command** — Trigger analysis of any Copilot CLI session
- **`/fork` command** — Fork at a decision point with new context

## Install

Install as an open-plugin in any compatible tool.
