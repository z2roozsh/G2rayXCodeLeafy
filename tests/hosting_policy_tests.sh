#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/data" "$TMP_ROOT/logs"
export G2RAY_DATA_DIR="$TMP_ROOT/data" G2RAY_LOG_DIR="$TMP_ROOT/logs"
export POLICY_CALLS="$TMP_ROOT/calls" POLICY_SCRIPT="$ROOT_DIR/g2ray.sh"
export CODESPACES=true CODESPACE_NAME=compat-space
: > "$POLICY_CALLS"
for command in gh curl xray tmux; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s $*" >> "$POLICY_CALLS"\nexit 99\n' "$command" > "$TMP_ROOT/bin/$command"
    chmod +x "$TMP_ROOT/bin/$command"
done
export PATH="$TMP_ROOT/bin:$PATH"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

# Missing config must reach normal validation, not a provider-wide refusal.
# All possible external commands above are inert stubs.
if output=$(env -u G2RAY_SOURCE_ONLY bash "$POLICY_SCRIPT" --start 2>&1); then
    fail 'A start without a config unexpectedly succeeded'
else
    [[ "$?" == 1 ]] || fail "The original start command is blocked: $output"
fi
[[ "$output" == *'No config exists yet'* ]] || fail "Start never reached normal validation: $output"
[[ ! -s "$POLICY_CALLS" ]] || fail 'Missing-config startup reached a runtime/network command'
pass 'Codespaces start reaches normal config validation without a provider-wide block'

checklist=$(env -u G2RAY_SOURCE_ONLY bash "$POLICY_SCRIPT" --setup-checklist)
[[ "$checklist" == *'89 minutes'* && "$checklist" == *'--idle-timeout 89m'* &&
   "$checklist" == *'https://github.com/settings/codespaces'* ]] || fail '89-minute setup checklist is incomplete'
[[ ! -s "$POLICY_CALLS" ]] || fail 'Offline checklist made an external call'
grep -Fq -- '--idle-timeout 89m' "$ROOT_DIR/README.md" || fail 'README is missing the explicit creation timeout'
pass 'The setup checklist and README specify 89 minutes without starting a runtime'

(
    export G2RAY_SOURCE_ONLY=1
    source "$POLICY_SCRIPT"
    run_gh() {
        [[ "$*" == "codespace view -c compat-space --json idleTimeoutMinutes --jq .idleTimeoutMinutes // empty" ]] ||
            fail 'Checklist requested an operation other than reading the effective timeout'
        [[ "$fixture_minutes" != error ]] || return 1
        printf '%s\n' "$fixture_minutes"
    }
    fixture_minutes=89
    [[ $(print_codespace_idle_timeout_check) == *'89 minutes (matches checklist)'* ]] || fail '89-minute timeout not recognized'
    fixture_minutes=30
    [[ $(print_codespace_idle_timeout_check) == *'30 minutes (expected 89)'* ]] || fail 'Mismatch not reported'
    for fixture_minutes in error '' null '89.1'; do
        [[ $(print_codespace_idle_timeout_check) == *'unverified'* ]] || fail 'Unavailable timeout reported as known'
    done
)
pass 'Effective setup timeout reports a match, mismatch, or unavailable evidence'

(
    export G2RAY_SOURCE_ONLY=1
    # shellcheck source=../g2ray.sh
    source "$POLICY_SCRIPT"
    MOCK_STATUS=0
    with_runtime_lock() { printf '%s\n' "$1" >> "$POLICY_CALLS"; return "$MOCK_STATUS"; }
    for entry in start_xray generate_config prepare_headless_runtime ensure_runtime_ready force_reconnect; do
        "$entry"
    done
    for expected in _start_xray_impl _generate_config_impl _prepare_headless_runtime_impl _ensure_runtime_ready_impl _force_reconnect_impl; do
        grep -Fxq "$expected" "$POLICY_CALLS" || fail "Codespaces did not dispatch $expected"
    done
    if MOCK_STATUS=37 start_xray; then fail 'Start swallowed the underlying failure'; else
        [[ "$?" == 37 ]] || fail 'Start changed the underlying failure status'
    fi
    _recover_now_impl() { printf 'recovery\n' >> "$POLICY_CALLS"; }
    recover_now
    grep -Fxq recovery "$POLICY_CALLS" || fail 'Recover Now did not dispatch'
)
pass 'Codespaces start, generation and recovery wrappers remain available and preserve real errors'

(
    export G2RAY_SOURCE_ONLY=1
    source "$POLICY_SCRIPT"
    run_gh() { printf '%s\n' "$*" >> "$TMP_ROOT/ports"; }
    enable_ws_fallback_mode
    ensure_codespace_port_public force
    ensure_optional_ws_port_public force
    grep -Fxq 'codespace ports visibility 443:public -c compat-space' "$TMP_ROOT/ports" || fail 'XHTTP publication is blocked'
    grep -Fxq 'codespace ports visibility 8443:public -c compat-space' "$TMP_ROOT/ports" || fail 'WS publication is blocked'
    [[ "$(wc -l < "$TMP_ROOT/ports")" == 2 ]] || fail 'Unexpected extra ports were published'
)
pass 'Configured XHTTP and WebSocket ports can be published by the normal runtime using mocked GitHub calls'

(
    export G2RAY_SOURCE_ONLY=1
    source "$POLICY_SCRIPT"
    XRAY_PORT=9443
    WS_PORT=10443
    enable_ws_fallback_mode
    run_gh() { printf '%s\n' "$*" >> "$TMP_ROOT/custom-ports"; }
    ensure_codespace_port_public force
    ensure_optional_ws_port_public force
    grep -Fxq 'codespace ports visibility 9443:public -c compat-space' "$TMP_ROOT/custom-ports" || fail 'Custom XHTTP port publication changed'
    grep -Fxq 'codespace ports visibility 10443:public -c compat-space' "$TMP_ROOT/custom-ports" || fail 'Custom WS port publication changed'
    [[ "$(wc -l < "$TMP_ROOT/custom-ports")" == 2 ]] || fail 'Unexpected extra custom ports were published'
)
pass 'Custom XHTTP and WebSocket ports retain the original publication path'

mkdir -p "$TMP_ROOT/hook/scripts"
cp "$ROOT_DIR/scripts/post-start.sh" "$TMP_ROOT/hook/scripts/"
export HOOK_ARGS="$TMP_ROOT/hook-args"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$HOOK_ARGS"\nexit "$HOOK_STATUS"\n' > "$TMP_ROOT/hook/g2ray.sh"
if HOOK_STATUS=37 G2RAY_LOG_DIR="$TMP_ROOT/hook/logs" bash "$TMP_ROOT/hook/scripts/post-start.sh"; then
    fail 'Post-start swallowed its resume failure'
else
    [[ "$?" == 37 ]] || fail 'Post-start changed the resume failure code'
fi
grep -Fxq -- '--silent-start' "$HOOK_ARGS" || fail 'Post-start did not invoke the compatible resume path'
grep -Fq 'post_start failed rc=37' "$TMP_ROOT/hook/logs/g2ray.log" || fail 'Post-start omitted the real resume failure'
HOOK_STATUS=0 G2RAY_LOG_DIR="$TMP_ROOT/hook/logs" bash "$TMP_ROOT/hook/scripts/post-start.sh"
grep -Fq 'post_start complete' "$TMP_ROOT/hook/logs/g2ray.log" || fail 'Post-start omitted successful resume'
pass 'Codespace post-start resumes the configured tunnel and preserves success/failure reporting'

: > "$POLICY_CALLS"
(
    export G2RAY_SOURCE_ONLY=1
    source "$POLICY_SCRIPT"
    anti_sleep_enabled && fail 'Synthetic anti-sleep is unexpectedly enabled'
    if enable_anti_sleep; then fail 'Synthetic anti-sleep could be re-enabled'; fi
    [[ ! -e "$DATA_DIR/keepalive.sh" ]] || fail 'A synthetic heartbeat script was created'
) > "$TMP_ROOT/anti-idle.log" 2>&1
[[ ! -s "$POLICY_CALLS" ]] || fail 'Retired anti-sleep invoked an external command'
pass 'Restoring the tunnel does not restore synthetic anti-idle traffic'

env -u G2RAY_SOURCE_ONLY bash "$POLICY_SCRIPT" bench --json --mock > "$TMP_ROOT/mock-bench.json"
[[ ! -s "$POLICY_CALLS" ]] || fail 'Mock benchmark contacted a network/runtime dependency'
pass 'Mock benchmarks remain offline and isolated'

node --input-type=module - "$ROOT_DIR" <<'JS'
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
const root = process.argv[2];
const config = JSON.parse(readFileSync(root + '/.devcontainer/devcontainer.json', 'utf8'));
assert.deepEqual(config.forwardPorts, [443, 8443]);
assert.equal(config.postStartCommand, 'bash ./scripts/post-start.sh');
assert.equal(config.postAttachCommand, 'bash ./g2ray.sh');
assert.equal(config.otherPortsAttributes, undefined);
assert.deepEqual(Object.keys(config.portsAttributes).sort(), ['443', '8443']);
for (const port of Object.values(config.portsAttributes)) {
  assert.equal(port.visibility, 'public');
  assert.equal(port.onAutoForward, 'silent');
}
const result = spawnSync(process.env.BASH || 'bash', [process.env.POLICY_SCRIPT, '--hosting-policy'], {
  encoding: 'utf8', env: { ...process.env, G2RAY_SOURCE_ONLY: '' }
});
assert.equal(result.status, 0, result.stderr);
assert.deepEqual(JSON.parse(result.stdout), {
  codespaces_host: true, runtime_allowed: true, provider_approval_verified: false,
  synthetic_anti_sleep: false, scheduled_quota_revival: false
});
console.log('PASS: Original VPN port visibility and resume/attach hooks are intact; no new catch-all forwarding override or provider-approval claim');
JS
