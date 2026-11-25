# G2rayXCodeLeafy

Xray transport research, a server control panel, and an Android VLESS client.

## Intended Use

This is a personal network hobby project for developing and testing a
**Codespaces-based VPN/proxy tunnel** and its Android client. It is not intended
to be used as a full-time VPN, a commercial VPN service, or a public subscription
service. Codespaces remains the intended experimental environment; a VPS
migration is not the goal of this project.

Experiments should be user-initiated, tied to an actual development or testing
task, and stopped when that task finishes. Examples include reproducing an idle
connection failure, comparing XHTTP and WebSocket behavior, or verifying upload
integrity. This describes intended use, not a claim that the current code
enforces a test-session time limit or that GitHub has approved the workload.
Occasional use alone does not establish that a particular session meets
GitHub's development/testing requirements.

## Compatibility Status

**The Codespaces VPN implementation is enabled. There is no blanket Codespaces
startup block.** The temporary provider-wide refusal was withdrawn to preserve
the existing proxy-tunnel workflow.

- The normal start, generation and recovery paths are available. Existing UUIDs,
  VLESS links, XHTTP/WebSocket transports, native fixes and Android profiles are
  preserved.
- Starting an existing Codespace runs the saved tunnel's headless resume path.
  A new workspace with no config still needs initial config generation; no
  credentials are invented or silently replaced.
- The devcontainer registers ports 443 and 8443 with their original public
  visibility. Startup/recovery can reassert those VPN ports using the existing
  authenticated GitHub CLI path. Ordinary clients need that reachable entrance;
  private-only forwarding would not preserve their old behavior. No new
  catch-all forwarding override changes the original custom-port behavior.
- The original authenticated Worker wake works with the existing
  `CODESPACE_NAME`, `GITHUB_TOKEN` and `WAKE_SECRET` bindings. No new purpose flag is
  required. Direct GitHub wake in the unchanged Android app is also preserved.
- Local recovery and the supervisor remain available while the Codespace is
  running. No artificial session-expiry timer was added that could terminate
  an upload, video or AI stream.
- Synthetic anti-idle traffic and scheduled quota revival remain retired.
  Normal transport keepalive, health checks and recovery are different and
  remain available.

These are local source changes, not proof of today's live server or phone
behavior. Nothing has been pushed, pulled, deployed or installed during this
review. Existing installations are unchanged until an explicitly approved
rollout.

## Hosting Boundary

This is intended for genuine project development and testing, not a full-time
VPN service. GitHub's [Codespaces terms](https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features#codespaces)
restrict production-facing applications and activity unrelated to project
development/testing. Hobby intent, occasional use and a successful connection
do not by themselves establish provider approval.

Do not rotate accounts to extend free VPN hosting or work around suspension.
Resolve account restrictions through [GitHub Support](https://docs.github.com/en/site-policy/acceptable-use-policies/github-appeal-and-reinstatement).
The local code does not bypass account, quota, billing, retention or access
restrictions and cannot guarantee that an account will not be suspended.
The screenshot does not establish which activity caused the existing suspension.

Codespaces remains the intended experimental environment. No VPS migration is
part of these changes. A Cloudflare domain or tunnel does not change the origin
provider's rules. The panel is also **not a turnkey VPS deployment tool**.

## Starting A Hobby Session

### New Account And Codespace Checklist

- [ ] Confirm you are signed in to the intended GitHub account in the browser
  and CLI (`gh api user --jq .login`), and verify the repository owner.
- [ ] In [GitHub Codespaces settings](https://github.com/settings/codespaces),
  enter **89 minutes** under **Default idle timeout** and click **Save**.
  Do this once on each authorized account, before creating its first workspace.
  The setting applies only to new Codespaces; it is not a retrofit for existing
  ones. GitHub counts idle running time toward usage.
- [ ] When creating via CLI, also pass `--idle-timeout 89m` explicitly:
  `gh codespace create --repo OWNER/G2rayXCodeLeafy --branch main --idle-timeout 89m`.
  Verify the actual value with
  `gh codespace view -c CODESPACE_NAME --json idleTimeoutMinutes`. An owner
  policy can impose a shorter timeout; do not treat the request as verification.
- [ ] On first run, generate a config once. On existing workspaces, reuse the
  saved config and UUID. Check the engine and route in Diagnostics; keep links
  and bundles private. Configure authenticated on-demand wake only if needed.
- [ ] Test the selected profile on the client, then stop the workspace when
  the experiment is finished.

The panel shows this checklist at first run and under
**15) Recovery / Waker Setup > 5) Setup Checklist**. That menu reads the
workspace timeout when GitHub CLI access permits it; it does not read or change
your account default. `bash ./g2ray.sh --setup-checklist` prints the instructions
offline without starting anything.

Use only an account/workspace you are legitimately permitted to access.

1. Open the Codespace development workspace and run the panel with
   `bash ./g2ray.sh`. On a new workspace, choose `1) Generate Config & Start`.
2. For an existing config, the original `--start`, `--silent-start` and
   `--recover-now` paths remain available. An authenticated on-demand wake can
   start the Codespace and its saved tunnel without requiring a panel visit.
3. Use your existing imported links. Regeneration is not required merely
   because the temporary blanket startup guard was removed.
4. Stop the Codespace when your experiment is finished. Provider idle stopping
   and quotas still apply; synthetic anti-sleep and quota-revival Cron are off.

The panel's recovery card lets you copy these recovery commands without exposing
the saved wake secret. The original recovery and diagnostics tools are retained.

The offline `--hosting-policy` JSON reports local behavior, not GitHub approval.
Offline benchmarks and isolated test fixtures remain available. There is no
claim of a provider-approved safe duration, uninterrupted hosting, instant
media, or guaranteed reinstatement.

The checks below verify local behavior and config compatibility. Only GitHub
can confirm why an account was restricted or whether it can be reinstated.

## Local Verification

Run from the repository root, using Bash and Node.js:

```bash
bash -n ./g2ray.sh
bash -n ./scripts/post-start.sh
bash ./tests/hosting_policy_tests.sh
bash ./tests/g2ray_static_tests.sh
bash ./tests/g2ray_behavior_tests.sh
node ./tests/worker_behavior_tests.mjs
npm --prefix ./worker/codespace-waker run check
bash ./g2ray.sh bench --json
```

The explicit `bash ./g2ray.sh bench --json --mock` form runs isolated mocked performance budget checks.

For the standalone Go HTTP/2 diagnostics on Windows, use PowerShell 7 and the
already installed Go and native GCC toolchain:

```powershell
pwsh -NoProfile -File ./scripts/test-go-diagnostics.ps1
pwsh -NoProfile -File ./tests/go_diagnostics_runner_tests.ps1
```

The first command runs the real race-enabled, loopback-only Go tests. It places
the selected compiler's directory first in the test process's PATH to prevent
unrelated DLLs from breaking GCC helpers. It restores the caller's environment
and directory, disables toolchain/dependency downloads, and does not change
system PATH or DLLs. Optional `-GoPath` and `-CompilerPath` select existing native
executables. The second command tests the runner's failure and restoration
contracts with isolated mocks. Neither command builds or tests Android.

Tests use isolated fixtures and mocks, not a persistent public proxy. The full
behavior suite includes Linux process/deadline semantics; Git Bash on Windows
does not certify those Linux cases. Native source builds, CI, mocked checks,
phone tests and deployed behavior are separate kinds of evidence.

## Android Client

Open [`g2ray_app`](g2ray_app/README.md) in Android Studio. Its build guide records
the pinned native dependencies and required AAR. SDK-local settings, signing
keys, large build outputs and credentials are not published.

The app's original configurations and transport settings remain intact. An old
installed app may still contain direct GitHub wake credentials and automatic
account failover. Local server/Worker changes do not remotely disable those
features: do not use them to continue a suspended or quota-circumventing hosting
setup. No Android build, installation or device acceptance is implied by this
local policy revision.

The [device acceptance matrix](g2ray_app/PRODUCTION_TEST_MATRIX.md) distinguishes
tested scenarios from open gates. Instant video, zero loss, indefinite uptime,
undetectability and superiority over every commercial VPN are not guaranteed.

## Cloudflare Worker Waker

The [Worker guide](worker/codespace-waker/README.md) covers authenticated
status/history and authenticated on-demand workspace starts. The
`GET /wake` page is public; its actions require authorization. No scheduled
event starts or polls a workspace, regardless of legacy Cron configuration.
Remove old Cloudflare Cron Triggers rather than relying on unused triggers.

An existing deployment must be updated separately after review. Editing this
checkout does not deploy a Worker, alter Cloudflare settings or contact a
Codespace.

Its Health dashboard remains a diagnostic, not the data-plane tunnel itself.
The Windows helper `scripts/reopen-codespace.ps1` retains its original arguments;
no new mandatory opt-in argument is needed for an explicit reopen request.
A provider's Default idle timeout should be respected, not defeated by
synthetic traffic. Recovery cannot restore a suspended GitHub account.

## Private Local Exports

This project intentionally does not publish a raw GitHub subscription URL.
Generated VLESS links and bundles contain access credentials and remain
gitignored. Keep `configs-to-copy-for-mobile.txt`, local subscription files,
`configs-meta.json`, `g2ray-codespace-bundle.json`, `data/` and `logs/`
private. The panel can save high-resolution QR PNG files under `data/qr/`.

The current `g2ray-codespace-bundle.json` uses schema 2 and preserves complete
VLESS links, including explicitly exported XHTTP `extra` settings. Select the
matching Codespace entry in the Android app before importing it. The separately
named `g2ray-codespace-bundle.legacy.json` intentionally removes `extra` for older
clients; do not use that legacy format to preserve tuning in this app. Neither
bundle supplies a GitHub token, Worker URL or wake key.

Existing links depend on retaining the same Codespace name/domain and UUID.
Stopping a workspace does not itself require new configs. If GitHub offers
**Keep codespace**, use it to preserve that workspace through a stopped period;
retention/deletion and billing remain GitHub's responsibility. Deleting and
recreating a Codespace changes its identity and does not preserve its old links.

Legacy server settings such as `G2RAY_QR_MODE`,
`G2RAY_EXTRA_FALLBACK_IPS`, `G2RAY_ROUTE_WAIT_SEC` and
`Option 49) Toggle Latency Focus Mode` do not authorize Codespaces hosting.
Exported links retain `insecure=0&allowInsecure=0`; disabling certificate
verification is not a performance or account-safety fix.

## Legacy Server Reference

These are references for preserved code and isolated fixtures, not instructions
to enable production use on Codespaces. Transport defaults are unchanged.

- `G2RAY_TCP_FAST_OPEN`: retained opt-in origin TCP Fast Open control; disabled by default after the measured origin-stall investigation.
- `19) Toggle WebSocket Fallback` persists its setting across sessions. `20) Cloudflare WS Front` manages an existing front hostname; a domain alone neither supplies origin Host/SNI routing nor changes provider terms. For each experiment, rank supported transports on the actual client network.
- `Route Candidates` retains bounded health samples, not a measurement of the phone's entire path. `G2RAY_MAX_FALLBACK_LINKS` caps exports. Default: `30`; up to 30 usable IP fallback configs plus the domain config, never a promise of 30 independent fast paths.
- `G2RAY_ROUTE_MONITOR_MAX_CANDIDATES`: Default: `40`, hard-capped at `64`. `G2RAY_DNS_CACHE_TTL_SEC` and `G2RAY_WIDE_DNS_DISCOVERY` control cached, bounded candidate discovery. `G2RAY_LAST_GOOD_ROUTE_MAX_AGE_SEC` expires stale route preferences.
- Local quota estimates are diagnostics, not permission to extend an allowance or rotate accounts. GitHub billing is authoritative; GB-month is storage quota, not traffic quota.

## Maintained Core

The maintained image builds pinned Xray 26.10.21 with the tested final-byte,
reader-close and per-session handshake corrections. Its build script, source
patches, Go version and native receipts remain pinned. The image keeps the
checksum-verified official binary for controlled rollback. None of the transport
defaults, Android native patches or user configurations are retuned by this
hosting-policy change.

## License

[MIT](LICENSE). Provider terms and applicable laws still apply.
