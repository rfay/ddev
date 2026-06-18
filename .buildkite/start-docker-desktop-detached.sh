#!/usr/bin/env bash
# start-docker-desktop-detached.sh
#
# Launch Docker Desktop so it SURVIVES Buildkite Windows Job Object teardown,
# leaving it running for the next job on the same runner.
#
# Background: Buildkite runs each job inside a Windows Job Object. When the job
# ends, every process in that object is killed — including any Docker Desktop
# started during the job. 'docker desktop start'/'restart' and PowerShell
# Start-Process all launch "Docker Desktop.exe" inside the job object (none of
# them break away from it), so the next job finds Docker Desktop stopped. This
# was confirmed on the tb-win11 runners: the EXIT trap reported "running at
# exit" yet the next job's sanetestbot.sh found Docker Desktop not running.
#
# The Task Scheduler service runs tasks OUTSIDE the job object, so a Docker
# Desktop launched via a scheduled task survives job teardown. Docker Desktop is
# single-instance, so we stop the job-bound instance first, then start a fresh
# one through the task.
#
# Best-effort: always exits 0 so it is safe to call from a trap. If the detached
# launch fails, the next job's sanetestbot.sh still starts Docker Desktop.

set -o nounset

# Only relaunch if Docker Desktop is currently running (i.e. this job used it).
# A pure docker-ce job that never started Docker Desktop should not spin it up.
if ! docker desktop status 2>&1 | grep -qi "Status[[:space:]]*running"; then
    echo "start-dd-detached: Docker Desktop not running at exit; nothing to detach."
    exit 0
fi

# Stop the job-bound instance so the detached launch starts a NEW process rather
# than no-opping on the existing (single-instance) one. CAROOT concerns
# (issue #8485) do not apply here — the test is already finished.
echo "start-dd-detached: stopping job-bound Docker Desktop before detached relaunch..."
docker desktop stop >/dev/null 2>&1 || true
for _ in {1..12}; do
    docker desktop status 2>&1 | grep -qi "Status[[:space:]]*running" || break
    sleep 5
done

# Launch Docker Desktop via a one-time scheduled task running as the current
# interactive user. The Task Scheduler service owns the process, so it is not a
# member of the Buildkite job object and survives teardown. -Force overwrites any
# prior definition so tasks do not accumulate. MSYS_NO_PATHCONV avoids git-bash
# mangling the backslash paths inside the PowerShell command.
echo "start-dd-detached: launching Docker Desktop via Task Scheduler (outside the job object)..."
MSYS_NO_PATHCONV=1 powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '
$ErrorActionPreference = "Continue"
$taskName = "DDEVStartDockerDesktopDetached"
$exe = Join-Path $env:PROGRAMFILES "Docker\Docker\Docker Desktop.exe"
if (-not (Test-Path $exe)) {
    Write-Output "start-dd-detached: Docker Desktop.exe not found at $exe"
    exit 0
}
try {
    $action = New-ScheduledTaskAction -Execute $exe
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Write-Output "start-dd-detached: scheduled task $taskName started; Docker Desktop will survive job teardown"
} catch {
    Write-Output "start-dd-detached: WARNING: scheduled-task launch failed: $_"
}
' 2>&1 || echo "start-dd-detached: WARNING: detached launch failed; next job's sanetestbot.sh will start Docker Desktop"

# Show the launched process so we can confirm it exists (and, in the next job's
# logs, whether it actually survived teardown).
echo "start-dd-detached: Docker Desktop processes just after detached launch:"
MSYS_NO_PATHCONV=1 tasklist.exe //FI "IMAGENAME eq Docker Desktop.exe" //FO CSV //NH 2>/dev/null | grep -i "docker" | sed 's/^/  /' || echo "  (none yet — may still be starting)"

exit 0
