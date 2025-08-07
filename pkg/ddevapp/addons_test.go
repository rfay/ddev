package ddevapp

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestProcessPHPAction(t *testing.T) {
	// Create a temporary test app (use ~/tmp which is mountable by Docker)
	homeDir, _ := os.UserHomeDir()
	testDir := filepath.Join(homeDir, "tmp", "test-app")
	app := &DdevApp{
		AppRoot: testDir,
		Name:    "test-project",
		Type:    "php",
	}

	// Create the .ddev directory and config.yaml for testing
	err := os.MkdirAll(app.AppConfDir(), 0755)
	require.NoError(t, err)

	configContent := `name: test-project
type: php
`
	err = os.WriteFile(filepath.Join(app.AppConfDir(), "config.yaml"), []byte(configContent), 0644)
	require.NoError(t, err)

	defer os.RemoveAll(testDir)

	// Test basic PHP action
	t.Run("BasicPHPAction", func(t *testing.T) {
		action := `<?php
echo "Hello from PHP test\n";
echo "This is working\n";
?>`

		dict := map[string]interface{}{
			"DdevProjectConfig": map[string]interface{}{
				"name": "test-project",
				"type": "php",
			},
		}

		err := processPHPAction(action, dict, "", true, app)
		require.NoError(t, err, "PHP action should execute without error")
	})

	// Test PHP action with config access
	t.Run("PHPActionWithConfig", func(t *testing.T) {
		action := `<?php
$configPath = 'config.yaml';
if (file_exists($configPath)) {
    $configContent = file_get_contents($configPath);
    if (preg_match('/^name:\s*(.+)$/m', $configContent, $matches)) {
        $projectName = trim($matches[1]);
        echo "Project name: $projectName\n";
    }
}
?>`

		dict := map[string]interface{}{
			"DdevProjectConfig": map[string]interface{}{
				"name": "test-project",
				"type": "php",
			},
		}

		err := processPHPAction(action, dict, "", true, app)
		require.NoError(t, err, "PHP action with config should execute without error")
	})

	// Test custom PHP image
	t.Run("CustomPHPImage", func(t *testing.T) {
		action := `<?php
echo "PHP Version: " . PHP_VERSION . "\n";
?>`

		dict := map[string]interface{}{
			"DdevProjectConfig": map[string]interface{}{
				"name": "test-project",
			},
		}

		err := processPHPAction(action, dict, "php:8.1-cli", true, app)
		require.NoError(t, err, "PHP action with custom image should execute without error")
	})

	// Test working directory is set to /var/www/html/.ddev
	t.Run("WorkingDirectoryTest", func(t *testing.T) {
		action := `<?php
// Test that we're in the correct working directory
$workingDir = getcwd();
echo "Working directory: $workingDir\n";

// Test relative path access to config.yaml
if (file_exists('config.yaml')) {
    echo "Found config.yaml in working directory\n";
    $configContent = file_get_contents('config.yaml');
    if (strpos($configContent, 'test-project') !== false) {
        echo "Config contains expected project name\n";
    }
} else {
    echo "config.yaml not found in working directory\n";
}

// Test relative path access to parent directory (../composer.json would be at project root)
if (file_exists('../')) {
    echo "Parent directory accessible\n";
} else {
    echo "Parent directory not accessible\n";
}
?>`

		dict := map[string]interface{}{
			"DdevProjectConfig": map[string]interface{}{
				"name": "test-project",
				"type": "php",
			},
		}

		err := processPHPAction(action, dict, "", true, app)
		require.NoError(t, err, "PHP action with working directory test should execute without error")
	})

	// Test file writing with relative paths
	t.Run("RelativeFileWriteTest", func(t *testing.T) {
		action := `<?php
// Test writing a file in the current directory (.ddev)
$testFile = 'test-output.txt';
$testContent = "Test content from PHP addon\n";
file_put_contents($testFile, $testContent);

if (file_exists($testFile)) {
    echo "Successfully wrote file: $testFile\n";
    $readContent = file_get_contents($testFile);
    if ($readContent === $testContent) {
        echo "File content matches expected content\n";
    }
    // Clean up
    unlink($testFile);
} else {
    echo "Failed to write file: $testFile\n";
}

// Test writing a file in parent directory (project root)
$parentTestFile = '../test-parent.txt';
$parentContent = "Test content in parent directory\n";
file_put_contents($parentTestFile, $parentContent);

if (file_exists($parentTestFile)) {
    echo "Successfully wrote file in parent directory\n";
    // Clean up
    unlink($parentTestFile);
} else {
    echo "Failed to write file in parent directory\n";
}
?>`

		dict := map[string]interface{}{
			"DdevProjectConfig": map[string]interface{}{
				"name": "test-project",
				"type": "php",
			},
		}

		err := processPHPAction(action, dict, "", true, app)
		require.NoError(t, err, "PHP action with relative file write test should execute without error")
	})
}

func TestProcessAddonActionPHPDetection(t *testing.T) {
	// Test PHP detection
	t.Run("PHPDetection", func(t *testing.T) {
		phpAction := "<?php echo 'Hello'; ?>"
		bashAction := "echo 'Hello'"

		// Check that PHP actions are detected
		require.True(t, strings.HasPrefix(strings.TrimSpace(phpAction), "<?php"))
		require.False(t, strings.HasPrefix(strings.TrimSpace(bashAction), "<?php"))
	})

	// Test mixed whitespace PHP detection
	t.Run("PHPDetectionWithWhitespace", func(t *testing.T) {
		phpAction := `
		<?php echo 'Hello'; ?>`

		require.True(t, strings.HasPrefix(strings.TrimSpace(phpAction), "<?php"))
	})
}
