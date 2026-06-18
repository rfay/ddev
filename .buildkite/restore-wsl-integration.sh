#!/usr/bin/env bash
# restore-wsl-integration.sh <distro>
#
# Re-inject Docker Desktop's WSL2 integration into <distro> WITHOUT restarting
# Docker Desktop, by running Docker Desktop's OWN per-distro proxy binary — the
# exact mechanism Docker Desktop uses internally, and the command behind the
# GUI's "Restart the WSL integration" button.
#
# WHY THIS EXISTS
# ---------------
# When a distro loses Docker Desktop integration (e.g. /usr/bin/docker was
# deleted, Resource Saver stopped the docker-desktop WSL distros, or a WSL
# update broke the per-distro agent), our only previously known repair was a
# full `docker desktop restart`. That is slow (~30-120s) and, under Buildkite's
# Windows Job Object, leaves Docker Desktop bound to the job (killed at job
# teardown). This script repairs integration without touching Docker Desktop's
# run state at all, so it is both faster and avoids the Job-Object problem.
#
# HOW DOCKER DESKTOP'S WSL INTEGRATION ACTUALLY WORKS (mechanism)
# ---------------------------------------------------------------
# Docker Desktop does NOT copy files from the Windows side into each distro.
# Instead, on every distro start it runs a single ELF binary that it mounts into
# the special `docker-desktop` WSL distro, exposed at:
#     /mnt/wsl/docker-desktop/docker-desktop-user-distro
# It invokes that binary as root, via wsl.exe, with the `proxy` subcommand:
#     wsl.exe -d <distro> -u root -e \
#       /mnt/wsl/docker-desktop/docker-desktop-user-distro proxy \
#       --distro-name <distro> --docker-desktop-root /mnt/wsl/docker-desktop
# The `proxy` subcommand is what creates the integration symlinks and starts the
# per-distro agent / docker.sock relay:
#     /usr/bin/docker          -> /mnt/wsl/docker-desktop/cli-tools/usr/bin/docker
#     /usr/bin/docker-compose  -> .../cli-tools/usr/local/lib/docker/cli-plugins/docker-compose
#     /usr/bin/docker-buildx, hub-tool, compose-bridge, docker-index -> cli-tools tree
#     /usr/bin/docker-credential-desktop.exe -> /Docker/host/bin/...
#   plus the agent registered over \\.\pipe\dockerWSLCrossDistroService.
# This is why merely re-creating the /usr/bin/docker symlink by hand was not
# enough (it skips the compose/buildx plugins, credential helper, agent, and
# socket relay) — running `proxy` sets up all of it the way Docker Desktop does.
#
# The `proxy` process is LONG-RUNNING (it IS the per-distro agent), so we launch
# it detached and then verify that `docker ps` works inside the distro.
#
# PRECONDITIONS
# - Docker Desktop must already be running, so /mnt/wsl/docker-desktop is mounted
#   and the proxy binary is present. (This script does not start Docker Desktop.)
# - After a Docker Desktop update the proxy binary can briefly be a 0-byte stub
#   until integration is enabled once; we detect that and bail to the caller.
#
# SOURCES (this technique is undocumented by Docker; pieced together from issues)
# - docker/for-win#12926 — running `docker-desktop-user-distro proxy` by hand
#   restores integration: https://github.com/docker/for-win/issues/12926
# - docker/for-win#14850 — exact /usr/bin symlink list:
#   https://github.com/docker/for-win/issues/14850
# - docker/for-win#13088, #13764 — Resource Saver stops the docker-desktop
#   distros / manual-symlink limits / GUI toggle re-injects:
#   https://github.com/docker/for-win/issues/13088
#   https://github.com/docker/for-win/issues/13764
# - docker/desktop-feedback#357 — the GUI "Restart the WSL integration" button
#   runs this proxy command: https://github.com/docker/desktop-feedback/issues/357
# - Docker Desktop CLI reference (shows there is NO `docker desktop` subcommand
#   for this): https://docs.docker.com/reference/cli/docker/desktop/
#
# Usage: bash restore-wsl-integration.sh <distro-name>
# Exit:  0  integration confirmed (docker ps works inside <distro>)
#        1  could not restore — caller should fall back to a full DD restart

set -o nounset
set -o pipefail

# Disable git-bash POSIX->Windows path conversion: every path here is a Linux
# path destined for inside the distro, not a Windows path.
export MSYS_NO_PATHCONV=1

DISTRO="${1:?Usage: $0 <distro-name>}"
PROXY="/mnt/wsl/docker-desktop/docker-desktop-user-distro"
DD_ROOT="/mnt/wsl/docker-desktop"
PROXY_LOG="/tmp/ddev-wsl-integration-proxy.log"

echo "restore-wsl-integration: attempting proxy re-inject for $DISTRO (no Docker Desktop restart)..."

# Verify the proxy binary is present and a real executable (not a post-update
# 0-byte stub). If it is missing/empty, integration cannot be repaired this way.
state=$(wsl.exe -d "$DISTRO" -u root -- bash -c "
    if [ ! -e '$PROXY' ]; then echo MISSING;
    elif [ ! -s '$PROXY' ]; then echo EMPTY_STUB;
    elif [ ! -x '$PROXY' ]; then echo NOT_EXECUTABLE;
    else echo OK; fi" 2>&1 | tr -d '\r')
echo "restore-wsl-integration: proxy binary ($PROXY) state: $state"
if [ "$state" != "OK" ]; then
    echo "restore-wsl-integration: proxy binary not usable; cannot re-inject without a full restart."
    exit 1
fi

# Launch the proxy detached (setsid + nohup + closed stdin) so it sets up the
# integration and keeps running as the per-distro agent after wsl.exe returns.
echo "restore-wsl-integration: launching '$PROXY proxy' detached in $DISTRO..."
wsl.exe -d "$DISTRO" -u root -- bash -c "
    setsid nohup '$PROXY' proxy --distro-name '$DISTRO' --docker-desktop-root '$DD_ROOT' \
        >'$PROXY_LOG' 2>&1 </dev/null &
    echo \"restore-wsl-integration: proxy launched, pid \$!\"" 2>&1 | tr -d '\r' || true

# Poll for working integration. The proxy needs a moment to create the symlinks
# and bring up the socket relay.
for i in 1 2 3 4 5 6 7 8; do
    if wsl.exe -d "$DISTRO" -- docker ps >/dev/null 2>&1; then
        echo "restore-wsl-integration: SUCCESS — docker ps works in $DISTRO after proxy re-inject (attempt $i, no restart)"
        exit 0
    fi
    echo "restore-wsl-integration: docker ps not yet working in $DISTRO (attempt $i/8)..."
    sleep 5
done

echo "restore-wsl-integration: proxy re-inject did not restore integration in $DISTRO."
echo "restore-wsl-integration: proxy log tail:"
wsl.exe -d "$DISTRO" -u root -- bash -c "tail -n 30 '$PROXY_LOG' 2>/dev/null" 2>&1 | tr -d '\r' | sed 's/^/    /' || true
echo "restore-wsl-integration: caller should fall back to a full Docker Desktop restart."
exit 1
