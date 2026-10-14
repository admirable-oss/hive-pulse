#!/bin/sh
set -eu

hive=${HIVE_BIN:-hive}
data=${HIVE_PLUGIN_DATA:?HIVE_PLUGIN_DATA is required}
interval=${HIVE_PULSE_INTERVAL:-15}
ttl=${HIVE_PULSE_TTL:-45}
history_file=$data/activity.jsonl
max_history=${HIVE_PULSE_HISTORY_LINES:-500}

mkdir -p "$data"

now() {

	date -u '+%Y-%m-%dT%H:%M:%SZ'
}

agents_json() {

	"$hive" --json agent list --all 2>/dev/null || printf '%s\n' '{"agents":[]}'
}

write_event() {

	timestamp=$1
	event_type=$2
	message=$3
	printf '%s\n' "$timestamp" "$event_type" "$message" |
		jq -Rsc 'split("\n") | {time: .[0], type: .[1], message: .[2]}' >>"$history_file"
	if [ -f "$history_file" ]; then
		tail -n "$max_history" "$history_file" >"$history_file.tmp"
		mv "$history_file.tmp" "$history_file"
	fi
}

notify() {

	message=$1
	case "${HIVE_PULSE_NOTIFICATIONS:-terminal}" in
		none) ;;
		terminal) printf '\aHive Pulse: %s\n' "$message" >&2 ;;
		*) printf '%s\n' "Hive Pulse: $message" >&2 ;;
	esac
}

refresh() {

	json=$(agents_json)
	all_agents=$(printf '%s' "$json" | jq -c '.agents // []')
	total=$(printf '%s' "$all_agents" | jq 'length')
	working=$(printf '%s' "$all_agents" | jq '[.[] | select(.state == "working")] | length')
	blocked=$(printf '%s' "$all_agents" | jq '[.[] | select(.state == "blocked")] | length')
	done=$(printf '%s' "$all_agents" | jq '[.[] | select(.state == "done")] | length')
	idle=$(printf '%s' "$all_agents" | jq '[.[] | select(.state == "idle" or .state == "unknown" or .state == "exited")] | length')
	summary="🐝 $total · $working working · $blocked needs input · $done completed · $idle idle"

	active_envs=$(printf '%s' "$all_agents" | jq -r '.[].environment_id' | sort -u)
	known_envs=$({ "$hive" env list --template '{{range .}}{{.id}}{{"\n"}}{{end}}' 2>/dev/null || true; printf '%s\n' "$active_envs"; } | sed '/^$/d' | sort -u)
	for env in $known_envs; do
		env_agents=$(printf '%s' "$all_agents" | jq --arg env "$env" '[.[] | select(.environment_id == $env)]')
		env_total=$(printf '%s' "$env_agents" | jq 'length')
		[ "$env_total" -gt 0 ] || continue
		env_working=$(printf '%s' "$env_agents" | jq '[.[] | select(.state == "working")] | length')
		env_blocked=$(printf '%s' "$env_agents" | jq '[.[] | select(.state == "blocked")] | length')
		env_done=$(printf '%s' "$env_agents" | jq '[.[] | select(.state == "done")] | length')
		env_idle=$(printf '%s' "$env_agents" | jq '[.[] | select(.state == "idle" or .state == "unknown" or .state == "exited")] | length')
		env_summary="🐝 $env_total · $env_working working · $env_blocked needs input · $env_done completed · $env_idle idle"
		"$hive" env report-metadata "$env" --token "pulse=$env_summary" --ttl "${ttl}s" >/dev/null 2>&1 || true
	done

	printf '%s\n' "$summary"
}

event() {

	context=${HIVE_PLUGIN_CONTEXT:?HIVE_PLUGIN_CONTEXT is required}
	timestamp=$(now)
	event_type=$(jq -r '.event.type // "event"' "$context")
	message=$(jq -r '
		.event.data as $d |
		if .event.type == "agent.state" then
			(($d.name // $d.kind // $d.id // "agent") + " → " + ($d.state // "unknown"))
		elif .event.type == "process.exited" then
			(($d.id // "process") + " exited")
		elif .event.type == "process.started" then
			(($d.id // "process") + " started")
		elif .event.type == "process.recovered" then
			(($d.id // "process") + " recovered")
		else "event" end
	' "$context")
	write_event "$timestamp" "$event_type" "$message"
	case "$event_type:$message" in
		agent.state:*" → blocked") notify "$message" ;;
		agent.state:*" → done") notify "$message" ;;
		process.exited:*) notify "$message" ;;
	esac
	refresh >/dev/null
}

case "${1:-once}" in
	watch)
		while :; do
			refresh >/dev/null
			sleep "$interval"
		done
		;;
	once)
		refresh
		;;
	event)
		event
		;;
	history)
		if [ -f "$history_file" ]; then
			jq -r '"\(.time)  \(.type)  \(.message)"' "$history_file" | tail -n 50
		else
			printf '%s\n' 'No Pulse activity recorded yet.'
		fi
		;;
	*)
		printf '%s\n' 'usage: hive-pulse.sh watch|once|event|history' >&2
		exit 2
		;;
esac
