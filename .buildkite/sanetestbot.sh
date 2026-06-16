#!/usr/bin/env bash

# Check a testbot or test environment to make sure it's likely to be sane.
# We should add to this script whenever a testbot fails and we can figure out why.

MIN_DDEV_VERSION=v1.24.0

set -o errexit
set -o pipefail
set -o nounset

# thanks to https://stackoverflow.com/a/24067243/215713
function version_gt() { test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"; }

DISK_AVAIL=$(df -k . | awk '/[0-9]%/ { gsub(/%/, ""); print $5}')
if [ ${DISK_AVAIL} -ge 95 ] ; then
    echo "Disk usage is ${DISK_AVAIL}% on $(hostname), not usable";
    exit 1;
else
   echo "Disk usage is ${DISK_AVAIL}% on $(hostname).";
fi

# On Windows with Docker Desktop, ensure Docker Desktop is running before the
# docker ps sanity check. Docker Desktop can be left stopped by a previous
# failed restart attempt or a machine reboot. On Linux and macOS Docker runs
# as a daemon and is expected to already be up; this block is Windows-only.
if [ "$(go env GOOS)" = "windows" ]; then
    # Retry docker ps a few times before concluding Docker Desktop is stopped.
    # A transient failure (e.g. Docker Desktop still initializing after a restart
    # by a previous job's restart-docker-desktop.sh) should not trigger a full
    # stop/start cycle.
    docker_ps_ok=false
    for _retry in 1 2 3; do
        if docker ps >/dev/null 2>&1; then
            docker_ps_ok=true
            break
        fi
        echo "docker ps attempt $_retry failed, retrying in 10s..."
        sleep 10
    done

    if [ "$docker_ps_ok" = "false" ]; then
        dd_status=$(docker desktop status 2>&1 || true)
        echo "Docker Desktop not responding after retries (status: $dd_status) — attempting to start it..."
        docker desktop start || true
        elapsed=0
        while ! docker ps >/dev/null 2>&1; do
            status=$(docker desktop status 2>&1 || true)
            echo "Waiting for Docker Desktop to start (${elapsed}s elapsed, status: $status)..."
            if [ "$elapsed" -ge 180 ]; then
                echo "ERROR: Docker Desktop did not start within 180s"
                exit 1
            fi
            sleep 10
            elapsed=$((elapsed + 10))
        done
        echo "Docker Desktop is running."
    fi
fi

# Test to make sure docker is installed and working.
# If it doesn't become ready then we just keep this testbot occupied :)
docker ps >/dev/null
while ! docker ps >/dev/null 2>&1 ; do
    echo "Waiting for docker to be ready $(date)"
    sleep 60
done

# Test that docker can allocate 80 and 443, get ddev/ddev-utilities
docker pull ddev/ddev-utilities >/dev/null
# Try the docker run command twice because of the really annoying mkdir /c: file exists bug
# Apparently https://github.com/docker/for-win/issues/1560
(sleep 1 && (docker run --rm -t -p 80:80 -p 443:443 -p 1081:1081 -p 1082:1082 -v /$HOME:/tmp/junker99 ddev/ddev-utilities ls //tmp/junker99 >/dev/null) || (sleep 1 && docker run --rm -t -p 80:80 -p 443:443 -p 1081:1081 -p 1082:1082 -v /$HOME:/tmp/junker99 ddev/ddev-utilities ls //tmp/junker99 >/dev/null ))

# Check that required commands are available.
for command in git go make mysql ngrok; do
    command -v $command >/dev/null || ( echo "Did not find command installed '$command'" && exit 2 )
done

if [ "$(go env GOOS)" = "windows"  -a "$(git config core.autocrlf)" != "false" ] ; then
 echo "git config core.autocrlf is not set to false on windows"
 exit 3
fi

# On Windows/WSL2: ensure the binfmt_misc WSLInterop entry is registered in each test distro.
#
# Background: WSL2 uses a binfmt_misc entry named "WSLInterop" so that Linux shells can
# transparently invoke Windows .exe binaries. This entry is lost whenever docker-ce is
# removed from a distro — the package's post-remove scripts clear binfmt_misc entries.
# It is also lost when systemd remounts binfmt_misc during boot before wsl.conf [boot]
# command has run. When the entry is absent, any .exe called from within the distro fails
# with "cannot execute binary file: Exec format error".
#
# Consequence for these tests: the PS1 install scripts call `wsl -d <distro> mkcert.exe`
# to add the mkcert CA to the Windows certificate store. If interop is broken, that call
# silently fails, the CA is never trusted by Windows, and every subsequent PowerShell
# HTTPS check fails with an SSL/TLS error — a hard-to-diagnose failure miles from the root cause.
#
# wsl-fix-interop re-registers the entry by writing the magic string to
# /proc/sys/fs/binfmt_misc/register. It is idempotent (exits 0 if already present).
# Requires a one-time installation per distro — see buildkite-testmachine-setup.md.
# See https://github.com/rfay/wsl-fix-interop
if [ "$(go env GOOS)" = "windows" ]; then
    for distro in ddev-test-ubuntu-ce ddev-test-ubuntu-desktop ddev-test-ubuntu2404-ce ddev-test-ubuntu2404-desktop ddev-test-debian-ce ddev-test-debian-desktop; do
        fix_out=$(wsl.exe -d "$distro" bash -c "sudo wsl-fix-interop" 2>&1) \
            && echo "wsl-fix-interop in $distro: $fix_out" \
            || echo "WARNING: wsl-fix-interop failed or not installed in $distro (skipping)"
    done

fi

echo "-- testbot $HOSTNAME seems to be set up OK --"
