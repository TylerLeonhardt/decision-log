---
name: decision-breadcrumbs
description: "Log structured decision breadcrumbs during coding. When this skill is active, the agent annotates its responses with decision markers whenever it makes a non-trivial choice — what was decided, what alternatives existed, why, and confidence level."
---

# Decision Breadcrumbs

You are instrumented with decision logging. As you work, **drop a breadcrumb** every time you make a non-trivial choice. These breadcrumbs create a decision trail that reviewers use to understand *why* the code looks the way it does — not just *what* it does.

## When to drop a breadcrumb

Drop a breadcrumb whenever you make a choice that a reviewer might reasonably question or want to understand. This includes:

- **File/module placement** — where new code lives in the project structure
- **Naming** — choosing names for types, functions, variables, modules
- **Library or dependency selection** — picking one tool over another
- **Abstraction boundaries** — what gets its own module, class, or function
- **Error handling strategy** — throw vs return, granularity of error types
- **Data structure choice** — array vs map, normalized vs denormalized
- **API design** — endpoint shape, method signatures, public surface area
- **Architecture patterns** — composition vs inheritance, sync vs async, push vs pull

**Do NOT breadcrumb** trivial or mechanical choices: indentation style, import ordering, formatting, boilerplate that follows established project patterns with no real alternative.

## Breadcrumb format

Use this exact structure inline in your response, wherever the decision naturally occurs:

```
**🔀 Decision #N** (confidence: high|medium|low)
- **Chose**: What was decided
- **Over**: What alternatives existed
- **Because**: Why this path was chosen
- **Tradeoff**: What was traded away
- **Depends on**: Decision #M (if applicable, otherwise omit)
- **Impact**: How this changes the system
```

## Confidence levels

- **high** — Clear best choice. Strong reasoning, well-established pattern, or project conventions make this obvious.
- **medium** — Reasonable choice but alternatives have real merit. Some uncertainty remains.
- **low** — Coin flip, unfamiliar territory, or missing context to decide well. Flag these clearly so a human can validate.

## Numbering

Start at **#1** and increment sequentially through the session. Never reset. If you reference a prior decision, use its number (e.g., "Depends on: Decision #3").

## Behavior rules

1. **Be lightweight.** Breadcrumbs should take seconds to write, not minutes. Don't slow down coding to write essays.
2. **Drop them inline.** Place the breadcrumb right where the decision happens in your response, not gathered at the end.
3. **Every non-trivial response gets at least one.** If you're writing or modifying code and made a real choice, log it.
4. **Over-log rather than under-log.** The analyst filters later. You capture now.
5. **The Impact field is critical.** This is the "teach me" element — it tells the reviewer how the system changed as a result of this decision. Never leave it vague.
6. **Don't fabricate alternatives.** If there was genuinely only one viable option, say so: `Over: No real alternative — X is the only tool that supports Y`. That's a valid and useful breadcrumb.

## Examples

### Example 1: Abstraction choice

> I need to create instances of different notification senders based on config.
>
> **🔀 Decision #4** (confidence: high)
> - **Chose**: Factory function (`createSender(config)`) returning a `Sender` interface
> - **Over**: Class hierarchy with `SmsSender extends BaseSender`, or a DI container
> - **Because**: Only 3 sender types, no shared state between them, and the project doesn't use a DI framework. A factory function is the simplest thing that works.
> - **Tradeoff**: If senders later need shared lifecycle management (connection pooling, graceful shutdown), a class hierarchy would handle that more naturally.
> - **Impact**: Adds `createSender()` as the single entry point for sender instantiation. New sender types require adding a case to the factory and implementing the `Sender` interface.

### Example 2: Module placement

> **🔀 Decision #7** (confidence: medium)
> - **Chose**: Put the rate limiter in `src/core/rate-limit.ts` as a core module
> - **Over**: Placing it in `src/middleware/` alongside the HTTP middleware, or co-locating it with the API route handlers in `src/routes/`
> - **Because**: The rate limiter is used by both HTTP handlers and the WebSocket gateway, so it doesn't belong to either layer. Core feels right for cross-cutting concerns.
> - **Tradeoff**: `src/core/` is becoming a grab-bag. If more cross-cutting concerns land here, it may need sub-organization.
> - **Impact**: Rate limiting is now available to any layer via `import { rateLimit } from '@/core/rate-limit'`. No coupling to HTTP or WS specifics.

### Example 3: Error handling

> **🔀 Decision #2** (confidence: low)
> - **Chose**: Return `Result<T, ParseError>` union type instead of throwing
> - **Over**: Throwing `ParseError` exceptions and catching at the boundary
> - **Because**: The parser is called in a hot loop during file watching. Exceptions for expected failures (malformed input) felt wrong for control flow. But this project uses throw-style errors everywhere else.
> - **Tradeoff**: This introduces a second error-handling pattern into the codebase. Callers must handle the Result type explicitly, which is inconsistent with the rest of the code.
> - **Depends on**: Decision #1 (choosing to make parsing synchronous)
> - **Impact**: All callers of `parse()` now pattern-match on `result.ok` instead of try/catch. This is the first Result-type usage in the project — sets a precedent that may spread.
