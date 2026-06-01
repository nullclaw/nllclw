# TOOLS.md

nllclw tools are optional product capabilities, not hidden runtime dependencies.

## Default Tools

When `NLLCLW_TOOLS=on`, the default binary may expose:

- `get_time`: return Unix time and configured local wall-clock time.
- `get_diagnostics`: report provider/model, memory, tool, rate, and schedule
  status without exposing secrets.
- `web_search`: search the web through a configured `NLLCLW_SEARCH_*` provider.
- `memory_store`: store or update a durable memory fact.
- `memory_recall`: recall one durable memory fact.
- `memory_list`: list durable memory keys.
- `memory_forget`: delete one durable memory fact.
- `create_tool`, `list_user_tools`, `delete_user_tool`: manage persistent
  user-defined macro tools.

## Read Tools

`read_file` and `list_dir` are not advertised unless both conditions are true:

- `NLLCLW_TOOLS=on`
- `NLLCLW_FILE_READ=on`

File tools reject absolute paths, `..` path escapes, common secret paths such as
`.env`, `.nllclw-*`, `.git`, SSH/GPG/AWS dirs, and key material extensions.
Paths must be valid UTF-8, control-free, and at most 512 bytes. Path components
are opened one by one without following symlinks.

## Write Tools

`write_file` and `edit_file` are not advertised unless both conditions are true:

- `NLLCLW_TOOLS=on`
- `NLLCLW_FILE_WRITE=on`

They use the same cwd confinement rules as the read/list tools.

## Scheduler Tools

`cron_set`, `cron_list`, and `cron_delete` are not advertised unless both
conditions are true:

- `NLLCLW_TOOLS=on`
- `NLLCLW_SCHEDULE_TOOLS=on`

## Optional Shell Tool

`shell_exec` is not present in the default binary. It exists only in binaries
built with `-Dshell-tool=true` and is advertised only when `NLLCLW_SHELL=on`.
Its combined stdout/stderr result is capped and must be valid UTF-8 text.

## Tool Use Policy

- Use the smallest tool that answers the request.
- Prefer reading/listing before modifying memory.
- Do not use a tool just to appear active.
- If a tool fails, report the failure plainly and continue only if there is a
  safe fallback.
