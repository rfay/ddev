#!/usr/bin/env bash
# restart-docker-desktop.sh
#
# Restart Docker Desktop and wait for WSL2 integration to become active in
# the given distro.
#
# Background: Docker Desktop loses WSL2 integration when things like
# apt-get remove docker-ce-cli remove /usr/bin/docker, or when WSLInterop
# is cleared from binfmt_misc. A Docker Desktop restart forces it to
# re-inject its integration binaries into configured distros.
#
# IMPORTANT: Avoid 'docker desktop stop' followed by 'docker desktop start'.
# During the stop window, /mnt/c/ (CAROOT) becomes briefly inaccessible to
# WSL2 processes. DDEV's readCAROOT() silently returns "" in this window,
# causing DDEV to generate a new CA not trusted by Windows — TLS failures
# (see https://github.com/ddev/ddev/issues/8485).
#
# We also must NOT use 'docker desktop restart' or 'docker desktop start'
# directly: those launch Docker Desktop.exe as a child of the Buildkite
# Windows Job Object, so Docker Desktop is killed when the job ends — leaving
# the next job to find it stopped. Instead we stop via the CLI (atomic, no
# stale frontend) and relaunch the frontend with PowerShell Start-Process so it
# detaches from the job object and survives job teardown (same approach as
# sanetestbot.sh).
#
# Usage: bash restart-docker-desktop.sh <distro-name>
# Exit:  0  integration confirmed working in <distro-name>
#        1  timed out or unexpected error

set -o pipefail
set -o nounset

DISTRO="${1:?Usage: $0 <distro-name>}"

TIMEOUT_START=180     # seconds to wait for Docker Desktop to report running
TIMEOUT_INTEGRATION=120  # seconds to wait for docker ps to work inside distro

wait_for_docker_desktop_running() {
    local elapsed=0
    while true; do
        local status
        status=$(docker desktop status 2>&1 || true)
        if echo "$status" | grep -qi "Status[[:space:]]*running"; then
            echo "restart-docker-desktop: Docker Desktop running (${elapsed}s elapsed)"
            return 0
        fi
        if [ "$elapsed" -ge "$TIMEOUT_START" ]; then
            echo "restart-docker-desktop: ERROR: timed out after ${TIMEOUT_START}s waiting for running"
            echo "restart-docker-desktop: last status: $status"
            return 1
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
}

# Stop Docker Desktop, then relaunch the frontend DETACHED from the Buildkite
# Windows Job Object. 'docker desktop restart'/'start' launch Docker Desktop.exe
# as a child of the job object, so it is killed when the job ends — leaving the
# next job to find Docker Desktop stopped. Start-Process detaches it so it
# survives job teardown (same approach as sanetestbot.sh).
#
# The CAROOT-inaccessible window (issue https://github.com/ddev/ddev/issues/8485)
# is not a concern here: this function returns only after full WSL2 integration
# is confirmed below, and the installer runs only after that — so no DDEV
# process reads CAROOT during the stop/start window.
echo "restart-docker-desktop: stopping Docker Desktop..."
docker desktop stop >/dev/null 2>&1 || true

stop_elapsed=0
while docker desktop status 2>&1 | grep -qi "Status[[:space:]]*running"; do
    if [ "$stop_elapsed" -ge 60 ]; then
        echo "restart-docker-desktop: WARNING: still reports running after ${stop_elapsed}s; relaunching anyway"
        break
    fi
    sleep 5
    stop_elapsed=$((stop_elapsed + 5))
done

echo "restart-docker-desktop: starting Docker Desktop (detached) to restore WSL2 integration in $DISTRO..."
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
  'Start-Process -FilePath "$env:PROGRAMFILES\Docker\Docker\Docker Desktop.exe" -PassThru | Out-Null' 2>/dev/null \
  || docker desktop start || true

wait_for_docker_desktop_running || exit 1

# Wait for both WSL2 integration in the distro AND Windows-side docker ps.
echo "restart-docker-desktop: waiting for WSL2 integration in $DISTRO (up to ${TIMEOUT_INTEGRATION}s)..."
elapsed=0
while true; do
    wsl_ok=false
    win_ok=false
    wsl.exe -d "$DISTRO" -- docker ps >/dev/null 2>&1 && wsl_ok=true
    docker ps >/dev/null 2>&1 && win_ok=true
    if [ "$wsl_ok" = "true" ] && [ "$win_ok" = "true" ]; then
        echo "restart-docker-desktop: WSL2 integration confirmed in $DISTRO and Windows docker ps OK (${elapsed}s elapsed)"
        exit 0
    fi
    if [ "$elapsed" -ge "$TIMEOUT_INTEGRATION" ]; then
        echo "restart-docker-desktop: ERROR: timed out after ${TIMEOUT_INTEGRATION}s (wsl_ok=$wsl_ok win_ok=$win_ok)"
        exit 1
    fi
    echo "restart-docker-desktop: waiting... wsl_ok=$wsl_ok win_ok=$win_ok (${elapsed}s)"
    sleep 10
    elapsed=$((elapsed + 10))
done
