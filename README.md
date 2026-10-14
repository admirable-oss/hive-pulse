# Hive Pulse

Hive Pulse is a lightweight observability plugin for Hive. It turns Hive's
structured agent events and state API into a compact workspace signal:

```text
🐝 5 · 2 working · 1 needs input · 1 completed · 1 idle
```

It reports a `pulse` token on each environment in the sidebar, records a
small JSONL activity timeline in the plugin data directory, and emits a
terminal notification when an agent becomes blocked, completes, or exits.

## Install

```sh
hive plugin install hive-pulse
```

For development:

```sh
hive plugin link ./hive-pulse
hive plugin run hive-pulse refresh
hive plugin run hive-pulse history
```

## Configuration

Set these environment variables before starting Hive or in the daemon's
environment:

- `HIVE_PULSE_INTERVAL`: refresh interval in seconds (default `15`)
- `HIVE_PULSE_TTL`: sidebar token lifetime in seconds (default `45`)
- `HIVE_PULSE_NOTIFICATIONS`: `terminal` (default), `none`, or another value for plain stderr notices
- `HIVE_PULSE_HISTORY_LINES`: retained activity records (default `500`)

Pulse prefers Hive's structured `agent.state` events and `agent list` output;
it does not scrape terminal text. Hive remains responsible for agent-specific
state detection, including integration hooks and screen-activity fallback.

## Data

Activity history is stored at `$HIVE_PLUGIN_DATA/activity.jsonl`. It is
workspace-local plugin data and is preserved when the plugin is uninstalled
unless `--delete-data` is used.
