#!/usr/bin/env bash
# restart-docker-desktop.sh
#
# Restart Docker Desktop and wait for WSL2 integration to become active in
# the given distro.
#
# Background: Docker Desktop loses WSL2 integration when the binfmt_misc
# WSLInterop entry is cleared — which happens as a side effect of
# `apt-get remove docker-ce` in any WSL2 distro (docker-ce post-remove scripts
# clear all binfmt_misc entries, and because binfmt_misc is a shared kernel
# resource across all WSL2 distros on the host, this affects every distro
# simultaneously). wsl-fix-interop restores the binfmt_misc entry, but Docker
# Desktop does not automatically re-inject its /usr/bin/docker symlink into
# the desktop distros after recovery. A Docker Desktop restart forces it to
# re-scan its configured distros and re-inject the integration binaries.
#
# Usage: bash restart-docker-desktop.sh <distro-name>
# Exit:  0  integration confirmed working in <distro-name>
#        1  timed out or unexpected error

set -o pipefail
set -o nounset

DISTRO="${1:?Usage: $0 <distro-name>}"

TIMEOUT_STOP=120      # seconds to wait for Docker Desktop to report stopped
TIMEOUT_START=180     # seconds to wait for Docker Desktop to report running
TIMEOUT_INTEGRATION=300  # seconds to wait for docker ps to work inside distro
# Note: after a Docker Desktop restart, running distros don't immediately get
# the /mnt/wsl/docker-desktop mount re-injected. Docker Desktop propagates it
# to already-running distros, but this can take several minutes.

wait_for_docker_desktop_status() {
    local description="$1"
    local pattern="$2"
    local timeout_sec="$3"
    local elapsed=0
    while true; do
        local status
        status=$(docker desktop status 2>&1 || true)
        if echo "$status" | grep -qi "$pattern"; then
            echo "restart-docker-desktop: $description (${elapsed}s elapsed)"
            return 0
        fi
        if [ "$elapsed" -ge "$timeout_sec" ]; then
            echo "restart-docker-desktop: ERROR: timed out after ${timeout_sec}s waiting for: $description"
            echo "restart-docker-desktop: last 'docker desktop status' output: $status"
            return 1
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
}

# When stopped, `docker desktop status` prints an error (no table), e.g.:
#   "Could not retrieve status. Is Docker Desktop running?"
# When running, it prints a table with "Status  running".
# When starting/stopping, the table shows "Status  starting" etc.
# Match carefully to avoid treating "starting" as "running".

# If Docker Desktop is already stopped (e.g. left down by a previous failed restart),
# skip the stop step and go straight to starting it.
if ! docker ps >/dev/null 2>&1; then
    echo "restart-docker-desktop: Docker Desktop already stopped — skipping stop step."
else
    echo "restart-docker-desktop: stopping Docker Desktop (WSL2 integration lost in $DISTRO)..."
    docker desktop stop || true
    wait_for_docker_desktop_status "Docker Desktop stopped" "Could not retrieve status" "$TIMEOUT_STOP" || exit 1
fi

echo "restart-docker-desktop: starting Docker Desktop..."
# Use Start-Process so Docker Desktop.exe is detached from the current
# Buildkite job's Windows Job Object. If we use 'docker desktop start'
# directly, Docker Desktop.exe becomes a child of this process and is
# killed by the Job Object when the Buildkite job ends — leaving Docker
# Desktop stopped for the next job. Start-Process with -PassThru starts
# it in a new process group outside the current Job Object.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
  'Start-Process -FilePath "$env:PROGRAMFILES\Docker\Docker\Docker Desktop.exe" -PassThru | Out-Null' 2>/dev/null \
  || docker desktop start || true

wait_for_docker_desktop_status "Docker Desktop running" "Status[[:space:]]*running" "$TIMEOUT_START" || exit 1

# Wait for both: WSL2 integration in the distro AND Windows-side docker ps.
# The WSL2 socket (/var/run/docker.sock inside the distro) and the Windows
# named pipe (dockerDesktopLinuxEngine) become ready at different times.
# sanetestbot.sh uses the Windows-side docker ps; if we only verify the WSL2
# side here, the next job's sanetestbot will still see Docker Desktop as
# unresponsive and trigger an unnecessary start.
echo "restart-docker-desktop: waiting for WSL2 integration in $DISTRO AND Windows docker ps (up to ${TIMEOUT_INTEGRATION}s)..."
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
