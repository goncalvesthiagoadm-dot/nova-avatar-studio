#!/usr/bin/env bash
# Run a short, isolated NOVA voice trial without touching other applications.
# No Hermes, dashboards, Nginx, tokens, swap settings, Docker pruning or reboots.
set -Eeuo pipefail
umask 077
BASE=/opt/nova-studio
PROJECT=nova-studio
FAIL() { echo "NOVA VOICE TEST BLOCKED: $*" >&2; exit 1; }
[[ "${EUID}" -eq 0 ]] || FAIL "Run with sudo"
for cmd in git docker awk df vmstat curl; do
  command -v "$cmd" >/dev/null 2>&1 || FAIL "Missing dependency $cmd"
done
docker info >/dev/null 2>&1 || FAIL "Docker is unavailable"
docker compose version >/dev/null 2>&1 || FAIL "Docker Compose v2 is missing"
[[ -d "$BASE/.git" && ! -L "$BASE" ]] || FAIL "Expected safe NOVA checkout is absent"
[[ "$(git -C "$BASE" remote get-url origin)" == "https://github.com/goncalvesthiagoadm-dot/nova-avatar-studio.git" ]] || FAIL "Unexpected repository"
[[ "$(git -C "$BASE" branch --show-current)" == main ]] || FAIL "NOVA not on main"
[[ -z "$(git -C "$BASE" status --porcelain --untracked-files=no)" ]] || FAIL "Local changes detected"
if docker ps --format '{{.Names}}' | grep -Eq '(^|-)kokoro(-lite|-tts)(-|$)'; then
  FAIL "A voice engine is already running; no second worker will be started"
fi
mem_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
disk_kb=$(df -Pk /opt | awk 'NR==2 {print $4}')
echo "Memory available: ${mem_kb:-0} KiB"
echo "Free disk: ${disk_kb:-0} KiB"
[[ "${mem_kb:-0}" -ge 1950000 ]] || FAIL "Available memory below 1.9 GiB; aborting without starting voice"
[[ "${disk_kb:-0}" -ge 4000000 ]] || FAIL "Free disk below 4 GB"
echo "Checking CPU and swap activity for 3 seconds..."
vmstat 1 4 | tail -n 3 | awk '
  { if (($7 + $8) > 256 || $15 < 25) bad=1; count++ }
  END { if (count != 3 || bad) exit 1 }
' || FAIL "Active swap or very high CPU load; aborting"
echo "Safety checks passed. Fetching NOVA code (no other service changes)..."
git -C "$BASE" fetch origin main
git -C "$BASE" merge --ff-only FETCH_HEAD || FAIL "NOVA checkout could not be fast-forwarded"
cd "$BASE"
docker compose -p "$PROJECT" --profile voice-lite config -q
# Require an available, already tested prebuilt image; NEVER compile on VPS.
echo "Downloading prebuilt voice image. No build on Hostinger."
docker compose -p "$PROJECT" --profile voice-lite pull kokoro-lite ||
  FAIL "Cannot pull image: confirm GHCR package is public; no voice worker started"
existing=$(docker compose -p "$PROJECT" --profile voice-lite ps -a -q kokoro-lite)
[[ -z "$existing" ]] || FAIL "NOVA Lite container already exists. Review it before a new trial."
launched=0
cleanup() {
  code=$?
  trap - EXIT
  if [[ "$launched" == 1 ]]; then
    docker compose -p "$PROJECT" --profile voice-lite stop -t 10 kokoro-lite >/dev/null 2>&1 || true
    docker compose -p "$PROJECT" --profile voice-lite rm -fs kokoro-lite >/dev/null 2>&1 || true
    echo "NOVA Lite trial container stopped and removed; other services untouched."
  fi
  exit "$code"
}
trap cleanup EXIT
[[ "$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)" -ge 1950000 ]] ||
  FAIL "RAM fell below threshold after image download"
echo "Starting ONLY kokoro-lite (1 GiB RAM / 1 CPU limit)..."
launched=1
docker compose -p "$PROJECT" --profile voice-lite up -d --no-build --no-deps kokoro-lite
cid=$(docker compose -p "$PROJECT" --profile voice-lite ps -q kokoro-lite)
[[ -n "$cid" ]] || FAIL "Voice container did not start"
ready=0
for attempt in $(seq 1 45); do
  if docker exec "$cid" python -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8880/health",timeout=2)' >/dev/null 2>&1; then
    ready=1; break
  fi
  if [[ "$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null || echo false)" != true ]]; then
    FAIL "Voice container exited during startup"
  fi
  sleep 3
done
[[ "$ready" == 1 ]] || FAIL "Voice worker failed health check"
echo "Generating a short demo WAV only inside the isolated worker..."
docker exec "$cid" python - <<'PY'
import io, json, urllib.request, wave
payload=json.dumps({"model":"kokoro","input":"Olá, eu sou a NOVA Studio.",
                    "voice":"pf_dora","response_format":"wav","speed":1}).encode()
req=urllib.request.Request("http://127.0.0.1:8880/v1/audio/speech",
                            data=payload,headers={"Content-Type":"application/json"})
with urllib.request.urlopen(req,timeout=120) as response:
    audio=response.read(8*1024*1024)
with wave.open(io.BytesIO(audio),"rb") as f:
    duration=f.getnframes()/f.getframerate()
    assert 0.5 < duration < 60 and f.getsampwidth()==2
    print("NOVA voice WAV:", round(duration,2),"seconds;",len(audio),"bytes")
PY
echo "Live worker usage:"
docker stats --no-stream --format '{{.Name}}: {{.MemUsage}} | {{.CPUPerc}}' "$cid" || true
echo "Available memory after trial:"
awk '/^MemAvailable:/ {printf "MemAvailable: %.1f GiB\n", $2/1048576}' /proc/meminfo
echo "TRIAL COMPLETE: worker will be stopped automatically. NOVA Studio remains online."
