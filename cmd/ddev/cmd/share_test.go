package cmd

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"

	exec2 "github.com/ddev/ddev/pkg/exec"
	"github.com/ddev/ddev/pkg/nodeps"
	asrt "github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestShareCmd tests `ddev share`
func TestShareCmd(t *testing.T) {
	if os.Getenv("DDEV_TEST_SHARE_CMD") != "true" {
		t.Skip("Skipping because DDEV_TEST_SHARE_CMD != true")
	}
	if nodeps.IsWindows() {
		t.Skip("Skipping because unreliable on Windows due to DNS lookup failure")
	}
	if os.Getenv("GITHUB_ACTIONS") == "true" {
		t.Skip("Skipping on GitHub actions because no auth can be provided")
	}
	assert := asrt.New(t)

	site := TestSites[0]
	defer site.Chdir()()

	// Configure ddev/ngrok to use json output to stdout
	cmd := exec.Command(DdevBin, "config", "--ngrok-args", "--log stdout --log-format=json")
	err := cmd.Start()
	require.NoError(t, err)
	err = cmd.Wait()
	require.NoError(t, err)

	cmd = exec.Command(DdevBin, "share")
	cmdReader, err := cmd.StdoutPipe()
	require.NoError(t, err)
	scanner := bufio.NewScanner(cmdReader)

	// Make absolutely sure the ngrok process gets killed off, because otherwise
	// the testbot (windows) can remain occupied forever.
	// nolint: errcheck
	t.Cleanup(func() {
		err = pKill(cmd)
		assert.NoError(err)
		_ = cmd.Wait()
		_ = cmdReader.Close()
		_, err = exec.LookPath("killall")
		// Try to kill ngrok any way we can, avoid having two run at same time.
		if err == nil {
			_, _ = exec2.RunHostCommand("killall", "-9", "ngrok")
		}

		if err != nil && !strings.Contains(err.Error(), "process already finished") {
			assert.NoError(err)
		}
	})
	logData := make(map[string]string)

	scanDone := make(chan bool, 1)
	defer close(scanDone)

	// Read through the ngrok json output until we get the url it has opened
	go func() {
		for scanner.Scan() {
			logLine := scanner.Text()

			err := json.Unmarshal([]byte(logLine), &logData)
			if err != nil {
				switch err.(type) {
				case *json.SyntaxError:
					continue
				default:
					t.Errorf("failed unmarshaling %v: %v", logLine, err)
					break
				}
			}
			if logErr, ok := logData["err"]; ok && logErr != "<nil>" {
				if strings.Contains(logErr, "Your account is limited to 1 simultaneous") {
					t.Errorf("Failed because ngrok account in use elsewhere: %s", logErr)
					break
				}
			}
			if _, ok := logData["url"]; ok {
				break
			}
		}
		scanDone <- true
	}()
	err = cmd.Start()
	require.NoError(t, err)
	select {
	case <-scanDone:
		fmt.Printf("Scanning all done at %v\n", time.Now())
	case <-time.After(20 * time.Second):
		t.Fatal("Timed out waiting for reads\n", time.Now())
	}
	// If URL is provided, try to hit it and look for expected response
	if url, ok := logData["url"]; ok {
		resp, err := http.Get(url + site.Safe200URIWithExpectation.URI)
		if err != nil {
			t.Logf("http.Get on url=%s failed, err=%v", url+site.Safe200URIWithExpectation.URI, err)
			err = pKill(cmd)
			assert.NoError(err)
			return
		}
		//nolint: errcheck
		defer resp.Body.Close()
		body, err := io.ReadAll(resp.Body)
		assert.NoError(err)
		assert.Contains(string(body), site.Safe200URIWithExpectation.Expect)
	} else {
		t.Errorf("no URL found: %v", logData)
	}
}

// TestShareCmdCloudflared tests `ddev share` with cloudflared
func TestShareCmdCloudflared(t *testing.T) {
	if os.Getenv("DDEV_TEST_SHARE_CMD") != "true" {
		t.Skip("Skipping because DDEV_TEST_SHARE_CMD != true")
	}
	if nodeps.IsWindows() {
		t.Skip("Skipping because unreliable on Windows")
	}
	if os.Getenv("GITHUB_ACTIONS") == "true" {
		t.Skip("Skipping on GitHub actions")
	}

	// Check if cloudflared is installed
	_, err := exec.LookPath("cloudflared")
	if err != nil {
		t.Skip("Skipping because cloudflared is not installed")
	}

	site := TestSites[0]
	defer site.Chdir()()

	// Ensure project is started
	cmd := exec.Command(DdevBin, "start")
	err = cmd.Run()
	require.NoError(t, err)

	cmd = exec.Command(DdevBin, "share", "--provider=cloudflared")
	var stdoutBuf, stderrBuf strings.Builder
	cmd.Stdout = &stdoutBuf
	cmd.Stderr = &stderrBuf

	t.Cleanup(func() {
		_ = pKill(cmd)
		_ = cmd.Wait()
	})

	err = cmd.Start()
	require.NoError(t, err)

	// Wait longer for cloudflared to start (can take 10+ seconds)
	time.Sleep(15 * time.Second)

	// Kill the share command
	err = pKill(cmd)
	require.NoError(t, err)
	_ = cmd.Wait()

	// Check captured output
	stdoutOutput := stdoutBuf.String()
	stderrOutput := stderrBuf.String()
	t.Logf("Stdout output:\n%s", stdoutOutput)
	t.Logf("Stderr output:\n%s", stderrOutput)

	// Verify URL was displayed
	require.Contains(t, stdoutOutput, "Tunnel URL:")
	require.Contains(t, stdoutOutput, "trycloudflare.com")
}

// TestShareCmdProviderSystem tests the script-based provider system
func TestShareCmdProviderSystem(t *testing.T) {
	if os.Getenv("DDEV_TEST_SHARE_CMD") != "true" {
		t.Skip("Skipping because DDEV_TEST_SHARE_CMD != true")
	}

	site := TestSites[0]
	defer site.Chdir()()

	// Ensure project is started
	cmd := exec.Command(DdevBin, "start")
	err := cmd.Run()
	require.NoError(t, err)

	// Test 1: Create a mock provider and verify URL capture
	t.Run("MockProviderURLCapture", func(t *testing.T) {
		mockScript := `#!/bin/bash
echo "Starting mock tunnel..." >&2
sleep 1
echo "https://mock-test-tunnel.example.com"
sleep 2
`
		mockPath := site.Dir + "/.ddev/share-providers/mock-test.sh"
		err := os.WriteFile(mockPath, []byte(mockScript), 0755)
		require.NoError(t, err)
		t.Cleanup(func() {
			_ = os.Remove(mockPath)
		})

		cmd := exec.Command(DdevBin, "share", "--provider=mock-test")
		var stdoutBuf, stderrBuf strings.Builder
		cmd.Stdout = &stdoutBuf
		cmd.Stderr = &stderrBuf

		err = cmd.Start()
		require.NoError(t, err)

		t.Cleanup(func() {
			_ = pKill(cmd)
			_ = cmd.Wait()
		})

		// Wait for provider to output URL and ddev share to capture/display it
		time.Sleep(3 * time.Second)

		// Kill the share command to end the test
		err = pKill(cmd)
		require.NoError(t, err)
		_ = cmd.Wait()

		// Check captured output
		stdoutOutput := stdoutBuf.String()
		stderrOutput := stderrBuf.String()
		t.Logf("Stdout output:\n%s", stdoutOutput)
		t.Logf("Stderr output:\n%s", stderrOutput)
		// util.Success() writes to stdout, not stderr
		require.Contains(t, stdoutOutput, "Tunnel URL:")
		require.Contains(t, stdoutOutput, "mock-test-tunnel")
	})

	// Test 2: Verify hooks have access to DDEV_SHARE_URL
	t.Run("HookURLAccess", func(t *testing.T) {
		mockScript := `#!/bin/bash
echo "https://hook-test-tunnel.example.com"
sleep 30
`
		mockPath := site.Dir + "/.ddev/share-providers/hook-test.sh"
		err := os.WriteFile(mockPath, []byte(mockScript), 0755)
		require.NoError(t, err)
		t.Cleanup(func() {
			_ = os.Remove(mockPath)
		})

		// Create config.hooks.yaml with pre-share hook that checks DDEV_SHARE_URL
		hooksConfig := `hooks:
  pre-share:
    - exec-host: |
        if [ -n "$DDEV_SHARE_URL" ]; then
          echo "HOOK_SUCCESS: DDEV_SHARE_URL=$DDEV_SHARE_URL" >&2
        else
          echo "HOOK_FAILURE: DDEV_SHARE_URL not set" >&2
        fi
`
		hooksPath := site.Dir + "/.ddev/config.hooks.yaml"
		err = os.WriteFile(hooksPath, []byte(hooksConfig), 0644)
		require.NoError(t, err)
		t.Cleanup(func() {
			_ = os.Remove(hooksPath)
		})

		cmd := exec.Command(DdevBin, "share", "--provider=hook-test")
		stderrReader, err := cmd.StderrPipe()
		require.NoError(t, err)

		t.Cleanup(func() {
			_ = pKill(cmd)
			_ = cmd.Wait()
			_ = stderrReader.Close()
		})

		err = cmd.Start()
		require.NoError(t, err)

		// Check stderr for hook output
		hookSuccess := false
		scanner := bufio.NewScanner(stderrReader)
		go func() {
			for scanner.Scan() {
				line := scanner.Text()
				if strings.Contains(line, "HOOK_SUCCESS") && strings.Contains(line, "hook-test-tunnel") {
					hookSuccess = true
					break
				}
			}
		}()

		// Wait for hook execution
		time.Sleep(3 * time.Second)

		require.True(t, hookSuccess, "Pre-share hook should have access to DDEV_SHARE_URL")
	})

	// Test 3: Provider priority (flag > config > default)
	t.Run("ProviderPriority", func(t *testing.T) {
		// Set config default provider
		cmd := exec.Command(DdevBin, "config", "--share-provider=config-provider")
		err := cmd.Run()
		require.NoError(t, err)

		// Create mock providers and collect paths for cleanup
		var mockPaths []string
		for _, name := range []string{"config-provider", "flag-provider"} {
			mockScript := fmt.Sprintf(`#!/bin/bash
echo "https://%s-tunnel.example.com"
sleep 2
`, name)
			mockPath := site.Dir + "/.ddev/share-providers/" + name + ".sh"
			err = os.WriteFile(mockPath, []byte(mockScript), 0755)
			require.NoError(t, err)
			mockPaths = append(mockPaths, mockPath)
		}

		// Cleanup mock provider files
		t.Cleanup(func() {
			for _, path := range mockPaths {
				_ = os.Remove(path)
			}
		})

		// Test flag overrides config
		cmd = exec.Command(DdevBin, "share", "--provider=flag-provider")
		var stdoutBuf, stderrBuf strings.Builder
		cmd.Stdout = &stdoutBuf
		cmd.Stderr = &stderrBuf

		err = cmd.Start()
		require.NoError(t, err)

		t.Cleanup(func() {
			_ = pKill(cmd)
			_ = cmd.Wait()
			// Reset config
			_ = exec.Command(DdevBin, "config", "--share-provider=").Run()
		})

		// Wait for provider to output URL and ddev share to capture/display it
		time.Sleep(3 * time.Second)

		// Kill the share command to end the test
		err = pKill(cmd)
		require.NoError(t, err)
		_ = cmd.Wait()

		// Check captured output
		stdoutOutput := stdoutBuf.String()
		stderrOutput := stderrBuf.String()
		t.Logf("Stdout output:\n%s", stdoutOutput)
		t.Logf("Stderr output:\n%s", stderrOutput)
		// util.Success() writes to stdout, not stderr
		require.Contains(t, stdoutOutput, "Tunnel URL:")
		require.Contains(t, stdoutOutput, "flag-provider-tunnel")
	})

	// Test 4: Provider not found error handling
	t.Run("ProviderNotFound", func(t *testing.T) {
		cmd := exec.Command(DdevBin, "share", "--provider=nonexistent")
		output, err := cmd.CombinedOutput()
		require.Error(t, err)
		require.Contains(t, string(output), "Failed to find share provider 'nonexistent'")
	})

	// Test 5: Provider script validation (not executable)
	t.Run("ProviderNotExecutable", func(t *testing.T) {
		mockScript := `#!/bin/bash
echo "https://test.example.com"
`
		mockPath := site.Dir + "/.ddev/share-providers/not-executable.sh"
		err := os.WriteFile(mockPath, []byte(mockScript), 0644) // Not executable
		require.NoError(t, err)
		t.Cleanup(func() {
			_ = os.Remove(mockPath)
		})

		cmd := exec.Command(DdevBin, "share", "--provider=not-executable")
		output, err := cmd.CombinedOutput()
		require.Error(t, err)
		require.Contains(t, string(output), "not executable")
	})
}

// pKill kills a started cmd; If windows, it shells out to the
// taskkill command.
func pKill(cmd *exec.Cmd) error {
	var err error
	if cmd == nil {
		return fmt.Errorf("pKill: cmd is nill")
	}
	if nodeps.IsWindows() {
		// Windows has a completely different process model, no SIGCHLD,
		// no killing of subprocesses. I wasn't successful in finding a way
		// to properly kill a process set using golang; rfay 20190622
		kill := exec.Command("TASKKILL", "/T", "/F", "/PID", strconv.Itoa(cmd.Process.Pid))
		kill.Stderr = os.Stderr
		kill.Stdout = os.Stdout
		err = kill.Run()
	} else {
		err = cmd.Process.Kill()
	}
	return err
}
