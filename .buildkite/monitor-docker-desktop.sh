#!/usr/bin/env bash
# monitor-docker-desktop.sh
#
# Continuously shows Docker Desktop health on the Windows host.
# Run from Git Bash on the test machine:
#   bash .buildkite/monitor-docker-desktop.sh
#   bash .buildkite/monitor-docker-desktop.sh ddev-test-ubuntu-desktop  # custom distro

DISTRO="${1:-ddev-test-ubuntu-desktop}"

while true; do
    echo "=== $(date '+%H:%M:%S') ==="

    echo -n "docker desktop status: "
    docker desktop status 2>&1 | grep -E "Status|Could not" | head -1 || echo "(error)"

    echo -n "docker ps (host):      "
    if docker ps --format "table {{.Names}}" 2>/dev/null | grep -v NAMES | head -3 | tr '\n' ' '; then
        echo "(ok)"
    else
        echo "(FAILED)"
    fi

    echo -n "wsl $DISTRO docker ps: "
    if wsl.exe -d "$DISTRO" -- docker ps --format "table {{.Names}}" 2>/dev/null | grep -v NAMES | head -3 | tr '\n' ' '; then
        echo "(ok)"
    else
        echo "(FAILED)"
    fi

    echo ""
    sleep 5
done
