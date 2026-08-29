#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3
require_command sqlite3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# 1. Test Antigravity Collector
brain_dir="$TEST_HOME/.gemini/antigravity/brain/session-1/.system_generated/logs"
mkdir -p "$brain_dir"

cat >"$brain_dir/transcript.jsonl" <<'INNER_EOF'
{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","content":"test prompt"}
{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","content":"test response text for 100 tokens"}
INNER_EOF

res_antigravity=$(HOME="$TEST_HOME" "$ROOT/bin/omarchy-agent-usage-antigravity")

[[ $(jq -r '.id' <<<"$res_antigravity") == "antigravity" ]] ||
  fail "Antigravity collector returns id 'antigravity'" "$res_antigravity"
pass "Antigravity collector returns id 'antigravity'"

[[ $(jq -r '.ready' <<<"$res_antigravity") == "true" ]] ||
  fail "Antigravity collector reports ready true" "$res_antigravity"
pass "Antigravity collector reports ready true"

[[ $(jq -r '.hasLocalStats' <<<"$res_antigravity") == "true" ]] ||
  fail "Antigravity collector reports hasLocalStats true" "$res_antigravity"
pass "Antigravity collector reports hasLocalStats true"


# 2. Test OpenCode Collector with production message(id, session_id, time_created, time_updated, data) schema
opencode_dir="$TEST_HOME/.local/share/opencode"
mkdir -p "$opencode_dir"

python3 - "$opencode_dir/opencode.db" <<'PY'
import json, sqlite3, sys, time
from pathlib import Path

db = Path(sys.argv[1])
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL)")
now_ms = int(time.time() * 1000)

def msg(id, role, model, input=0, output=0, reasoning=0, read=0, write=0):
    return (id, "ses_1", now_ms, now_ms, json.dumps({
        "role": role,
        "modelID": model,
        "tokens": {"input": input, "output": output, "reasoning": reasoning, "cache": {"read": read, "write": write}},
        "time": {"created": now_ms}
    }))

conn.executemany("INSERT INTO message VALUES (?, ?, ?, ?, ?)", [
    msg("msg_1", "user", "big-pickle"),
    msg("msg_2", "assistant", "big-pickle", input=100, output=50, reasoning=0, read=0, write=0),
])
conn.commit()
conn.close()
PY

res_opencode=$(HOME="$TEST_HOME" "$ROOT/bin/omarchy-agent-usage-opencode")

[[ $(jq -r '.id' <<<"$res_opencode") == "opencode" ]] ||
  fail "OpenCode collector returns id 'opencode'" "$res_opencode"
pass "OpenCode collector returns id 'opencode'"

[[ $(jq -r '.ready' <<<"$res_opencode") == "true" ]] ||
  fail "OpenCode collector reports ready true" "$res_opencode"
pass "OpenCode collector reports ready true"

[[ $(jq -r '.todayTotalTokens' <<<"$res_opencode") == "150" ]] ||
  fail "OpenCode collector sums tokens from SQLite message table correctly" "$res_opencode"
pass "OpenCode collector sums tokens from SQLite message table correctly"

[[ $(jq -r '.todayPrompts' <<<"$res_opencode") == "1" ]] ||
  fail "OpenCode collector counts user prompts correctly" "$res_opencode"
pass "OpenCode collector counts user prompts correctly"
