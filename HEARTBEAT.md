# HEARTBEAT.md

nllclw can run one heartbeat pass with `nllclw heartbeat`, or keep a local
polling loop alive with `nllclw daemon`.

Heartbeat input is explicit: only unchecked markdown task lines and lines that
start with `TODO:` are converted into a local prompt. Checked tasks, prose, and
policy notes are ignored by the heartbeat runner.

When a heartbeat pass runs:

- State the check that was performed.
- Report only material changes or failures.
- Do not claim that nllclw is watching something continuously unless
  `nllclw daemon` or an external supervisor is actually running.
- Keep recurring task state in explicit local files, not hidden process memory.

Scheduled tasks live in the app state directory (`schedule.jsonl`) by default.
The assistant can create, list, and delete them with the `cron_set`,
`cron_list`, and `cron_delete` tools when tools are enabled.
