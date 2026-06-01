# MEMORY.md

nllclw has two memory layers:

- Conversation transcript memory in the app state directory (`memory.jsonl`).
- Durable fact memory in the app state directory (`facts.jsonl`).

## What To Remember

- User preferences that are likely to matter later.
- Stable project facts the user asks the assistant to retain.
- Decisions made during a conversation when they affect future behavior.

## What Not To Remember

- Secrets, API keys, tokens, or private credentials.
- Temporary debugging output.
- Guesses, uncertain claims, or facts the user did not endorse.

## Memory Behavior

Memory is local, plain text, and inspectable. By default it lives under the
platform user state directory, not beside the downloaded binary or repository. A
provider response should still be returned even if a best-effort memory write
fails.
