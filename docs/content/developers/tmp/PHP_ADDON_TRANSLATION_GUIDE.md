# PHP Add-on Translation Guide

This guide documents the process, challenges, and solutions for translating bash-based DDEV add-ons to PHP. Based on the successful translation of ddev-redis from bash to PHP.

## Overview

PHP add-ons offer several advantages over bash:

- Better cross-platform compatibility
- Robust YAML parsing with php-yaml extension
- Cleaner conditional logic and error handling
- No shell scripting platform differences

However, the translation process reveals several challenges that need to be addressed systematically.

## Translation Process

### 1. Maintain Test Compatibility

**Critical**: Keep original tests unchanged to validate functional equivalence.

- Only change repository references in test files (`GITHUB_REPO` variable)
- All test assertions and expectations must remain identical
- Use tests as validation that PHP translation behaves exactly like bash original

### 2. Preserve Install.yaml Structure

Maintain clean, readable install.yaml by compartmentalizing PHP code:

```yaml
# BEFORE: Monolithic PHP code blocks (unreadable)
post_install_actions:
  - |
    <?php
    // 50+ lines of PHP code here
    ?>

# AFTER: Clean, modular approach  
post_install_actions:
  - |
    <?php
    #ddev-description:Install redis settings for Drupal 9+ if applicable
    include '/mnt/ddev_config/redis/scripts/setup-drupal-settings.php';
    ?>
```

Create separate PHP script files for complex logic while keeping simple operations inline.

## Key Challenges and Solutions

### 1. Environment Variable and Context Limitations

**Challenge**: PHP actions lack standard environment variables and consistent execution context.

**Current Issues**:

- No access to standard DDEV environment variables (`DDEV_APPROOT`, `DDEV_DOCROOT`, etc.)
- PHP scripts execute in unpredictable working directories
- Requires absolute paths for all file operations
- Manual config parsing instead of processed configuration access

**Required Solutions**:

```php
// NEEDED: Standard environment variables (like bash actions)
$_ENV['DDEV_APPROOT']     // '/var/www/html'  
$_ENV['DDEV_DOCROOT']     // 'web' or configured docroot
$_ENV['DDEV_PROJECT_TYPE'] // 'drupal', 'laravel', etc.
$_ENV['DDEV_SITENAME']    // Project name
$_ENV['DDEV_HOSTNAME']    // Primary hostname

// NEEDED: Consistent working directory execution
// All PHP actions should execute in: /var/www/html/.ddev
// This enables relative path usage like bash actions

// NEEDED: Access to processed configuration
$processedConfig = ddev_get_processed_config();
$globalConfig = ddev_get_global_config();
```

### 2. Container Environment Limitations

**Challenge**: PHP actions execute in containers without access to host `ddev` commands.

**Examples of Unavailable Commands**:

- `ddev debug configyaml` - Cannot access processed config from container
- `ddev dotenv get` - Environment file access is container-restricted  
- Host filesystem operations - Limited to mounted directories

**Current Workarounds**:

```php
// INSTEAD OF: shell_exec('ddev debug configyaml')
$config = yaml_parse_file('/mnt/ddev_config/config.yaml');

// INSTEAD OF: shell_exec('ddev dotenv get .ddev/.env.redis --redis-optimized')
if (file_exists('/var/www/html/.ddev/.env.redis')) {
    $envContent = file_get_contents('/var/www/html/.ddev/.env.redis');
    $isOptimized = strpos($envContent, 'REDIS_OPTIMIZED="true"') !== false;
}

// INSTEAD OF: accessing global config via ddev commands
// Currently requires manual file parsing
```

### 2. File Path Translation

**Challenge**: Bash actions run on host with direct access, PHP actions run in container.

**Path Mappings**:

```php
// Bash context -> PHP container context
.ddev/config.yaml -> /mnt/ddev_config/config.yaml
.ddev/redis/file.conf -> /mnt/ddev_config/redis/file.conf
./project/file -> /var/www/html/project/file
$DDEV_APPROOT/.ddev/ -> /var/www/html/.ddev/
```

### 3. Environment Variable Handling

**Challenge**: Bash environment variables not directly available.

**Solutions**:

```php
// INSTEAD OF: $DDEV_APPROOT, $DDEV_DOCROOT
$config = yaml_parse_file('/mnt/ddev_config/config.yaml');
$docroot = $config['docroot'] ?? 'web';
$projectName = $config['name'] ?? 'default';

// INSTEAD OF: $DDEV_PROJECT_TYPE  
$projectType = $config['type'] ?? 'php';
```

### 4. Output Control and User Feedback

**Challenge**: PHP actions need proper output control and user interaction handling.

**Current Issues**:

- `#ddev-nodisplay` directive not implemented for PHP actions
- No mechanism to suppress step output when requested
- Error handling and reporting inconsistent with bash actions
- Interactive user input not supported

**Required Solutions**:

```php
// NEEDED: Respect #ddev-nodisplay directive
#ddev-nodisplay:Skip Redis optimization prompts
// This action should run silently without progress output

// NEEDED: Consistent error reporting
if (!$success) {
    ddev_error("Failed to configure Redis: $errorMessage");
    exit(1);
}

// NEEDED: Interactive input handling
$version = ddev_prompt("Enter PHP version to build:", "8.2");
$confirmed = ddev_confirm("Proceed with build?", true);
```

### 5. Configuration Access Patterns

**Challenge**: Complex configuration queries that bash handles with ddev commands.

**Current Limitations**:

```php
// ❌ NOT AVAILABLE: 
// - Global DDEV configuration
// - Processed/computed config values
// - Runtime configuration state
// - Container environment details

// ✅ AVAILABLE:
// - Raw project config.yaml  
// - Project files and directories
// - Environment files (.env.*)
// - Generated configuration files
```

## Best Practices

### 1. Modular Script Organization

Create focused PHP scripts for each responsibility:

```
redis/scripts/
├── setup-drupal-settings.php    # Drupal-specific configuration
├── setup-redis-optimized-config.php    # Optimization handling
└── cleanup-legacy-files.php     # File cleanup operations
```

### 2. Error Handling and Validation

```php
// Always validate file existence and permissions
if (!file_exists($configFile)) {
    echo "Error: Configuration file not found: $configFile\n";
    exit(1);
}

// Check for #ddev-generated before modifying files
if (file_exists($file)) {
    $content = file_get_contents($file);
    if (strpos($content, '#ddev-generated') === false) {
        echo "Warning: File lacks #ddev-generated marker, skipping: $file\n";
        continue;
    }
}
```

### 3. Cross-Platform Compatibility

```php
// Use PHP file functions instead of shell commands
mkdir($directory, 0755, true);  // Instead of: mkdir -p
unlink($file);                  // Instead of: rm -f
copy($source, $dest);           // Instead of: cp
```

### 4. YAML Processing

```php
// Leverage php-yaml for robust parsing
$config = yaml_parse_file('/mnt/ddev_config/config.yaml');

// Generate clean YAML output
$dockerConfig = [
    'services' => [
        'redis' => [
            'image' => 'redis:7',
            'ports' => ['6379:6379']
        ]
    ]
];
file_put_contents('/var/www/html/.ddev/docker-compose.redis.yaml', 
    "#ddev-generated\n" . yaml_emit($dockerConfig));
```

## Translation Checklist

### Pre-Translation Analysis

- [ ] Map all bash environment variables to PHP equivalents
- [ ] Identify `ddev` command usage requiring alternative approaches  
- [ ] List all file operations and their container path mappings
- [ ] Document external dependencies and command requirements

### Implementation

- [ ] Create modular PHP script structure
- [ ] Update project_files list with .php extensions
- [ ] Convert all bash actions to PHP with proper paths
- [ ] Handle environment variables through config parsing
- [ ] Implement proper error handling and validation

### Validation

- [ ] All original tests pass unchanged
- [ ] File operations produce identical results
- [ ] Error messages maintain user-friendly format
- [ ] Performance comparable to bash implementation

### Documentation

- [ ] Document any behavior differences
- [ ] Note limitations compared to bash version
- [ ] Provide troubleshooting guidance
- [ ] Update README with PHP-specific notes

## Identified System Improvements Needed

Based on the translation experience, several enhancements would improve PHP add-on development:

### 0. Version Constraint Challenges

**Challenge**: Development and testing of PHP add-ons is complicated by version constraints.

**Issue**: When testing PHP add-ons with development builds (like `v1.23.5-477-gd1efc5064`), version constraints in `install.yaml` (e.g., `ddev_version_constraint: '>= v1.24.3'`) prevent installation, even when the development build contains the required PHP addon functionality.

**Impact on Development**:

- Cannot test PHP add-ons with development builds without commenting out version constraints
- CI/CD testing requires manual constraint removal  
- Version constraints become a barrier during development rather than a helpful guard

**Potential Solutions**:

- Allow development builds to bypass version constraints with a flag
- Implement more flexible version matching for development builds
- Provide a way to specify "development build compatible" in constraints

### GitHub Actions Testing Challenges

**Challenge**: Testing PHP add-ons requires installing custom DDEV builds that aren't available through standard distribution channels.

**Current Solution**: We implemented a custom build step in `.github/workflows/tests.yml` that:

1. **Dynamically fetches artifacts** from the PHP addon development branch
2. **Downloads the correct binary** using GitHub's nightly.link service
3. **Replaces the standard DDEV** installed by `ddev/github-action-add-on-test@v2`
4. **Handles API failures** with fallback to known working artifact IDs

```yaml
- name: Install PHP addon DDEV binary
  run: |
    # Get latest successful workflow run with artifacts
    RUN_ID=""
    WORKFLOW_RUNS=$(curl -s --fail "https://api.github.com/repos/rfay/ddev/actions/runs?branch=20250806_rfay_php_addon&per_page=5" || echo '{"workflow_runs":[]}')
    
    for run_id in $(echo "$WORKFLOW_RUNS" | jq -r '.workflow_runs[] | select(.conclusion=="success") | .id'); do
      ARTIFACT_COUNT=$(curl -s --fail "https://api.github.com/repos/rfay/ddev/actions/runs/$run_id/artifacts" | jq '.total_count')
      if [ "$ARTIFACT_COUNT" -gt 0 ]; then
        RUN_ID=$run_id
        break
      fi
    done
    
    # Fallback to known working run if API fails
    if [ -z "$RUN_ID" ]; then
      RUN_ID="16806923996"  # Known working build
    fi
    
    # Download and install PHP addon DDEV binary  
    ARTIFACT_ID=$(curl -s --fail "https://api.github.com/repos/rfay/ddev/actions/runs/$RUN_ID/artifacts" | jq -r '.artifacts[] | select(.name=="ddev-linux-amd64") | .id')
    curl -sSL --fail "https://nightly.link/rfay/ddev/actions/artifacts/$ARTIFACT_ID.zip" -o ddev-php-addon.zip
    unzip -q ddev-php-addon.zip
    sudo cp ddev /usr/local/bin/ddev
    sudo chmod +x /usr/local/bin/ddev
```

**Why This Approach**:

- `github-action-add-on-test@v2` only supports `"stable"` or `"HEAD"` versions, not custom builds
- PHP addon functionality requires specific development build with container runtime support
- Dynamic artifact fetching ensures tests use latest compatible build
- Fallback mechanism prevents failures due to GitHub API issues

**Future Options for Improvement**:

1. **Enhanced github-action-add-on-test**: Extend the action to support:
   - Custom binary URLs or artifact references
   - Skip DDEV installation when custom binary provided
   - Direct integration with development branches

2. **Separate Test Step**: Move test execution outside the action:
   - Install custom DDEV in separate step
   - Run bats tests directly without using the action
   - More control over test environment setup

3. **Development Distribution**: Create temporary distribution channel:
   - Publish development builds to test registry
   - Allow version constraints like `>= v1.24.0-dev`
   - Enable seamless testing of experimental features

4. **Docker-based Testing**: Containerize the entire test environment:
   - Build custom DDEV container images with PHP addon support
   - Test add-ons within controlled container environment
   - Eliminate host-level binary installation complexity

**Current Status**: The dynamic artifact approach successfully enables comprehensive testing of PHP add-ons, with all 10 test scenarios consistently using the correct DDEV version (`v1.23.5-478-ga611e2155`) and passing validation.

## Priority Implementation Tasks

### 1. Standard Environment Variables (HIGH PRIORITY)

**Implementation**: Pass the same environment variables to PHP containers that bash actions receive.

**Required Changes**:

- Modify `processPHPAction()` to set environment variables before container execution
- Provide all standard DDEV environment variables

```php
// SHOULD BE AVAILABLE (like in bash actions):
$_ENV['DDEV_APPROOT']     // '/var/www/html'  
$_ENV['DDEV_DOCROOT']     // 'web' or configured docroot
$_ENV['DDEV_PROJECT_TYPE'] // 'drupal', 'laravel', etc.
$_ENV['DDEV_SITENAME']    // Project name
$_ENV['DDEV_HOSTNAME']    // Primary hostname

// ELIMINATES CURRENT WORKAROUND:
// $config = yaml_parse_file('/mnt/ddev_config/config.yaml');
// $docroot = $config['docroot'] ?? 'web';
```

### 2. Consistent Working Directory (HIGH PRIORITY)

**Implementation**: Execute all PHP actions in `/var/www/html/.ddev` directory.

**Required Changes**:

- Set working directory in `processPHPAction()` before script execution
- Match bash action execution context

**Benefits**:

- Enables relative path usage: `file_put_contents('docker-compose.redis.yaml', $content)`
- Matches bash action expectations
- Simplifies file operations

### 3. Processed Configuration Access (MEDIUM PRIORITY)

**Implementation**: Provide resolved configuration data to PHP environment.

**Required Changes**:

- Mount processed config as JSON/YAML files in container
- Create PHP helper functions for config access

```php
// NEEDED: Access to processed configuration
$globalConfig = ddev_get_global_config();
$processedConfig = ddev_get_processed_config();
```

### 4. Output Control Implementation (MEDIUM PRIORITY)

**Implementation**: Support `#ddev-nodisplay` and proper error handling.

**Required Changes**:

- Parse `#ddev-nodisplay` directive in `processPHPAction()`
- Suppress step output when directive is present
- Implement consistent error reporting and exit code handling
- Test failure scenarios match bash action behavior

### 5. Interactive Input Support (LOW PRIORITY)

**Implementation**: Enable user interaction for PHP actions.

**Required Changes**:

- Research existing bash addon examples (ddev-php-patch-build)
- Design PHP-compatible input mechanism
- Consider container environment limitations for interactive prompts

### Impact on Current Translation

These improvements would significantly simplify the Redis PHP translation:

**Before (Current Implementation)**:

```php
// Complex path management
$config = yaml_parse_file('/mnt/ddev_config/config.yaml');
$targetDir = '/var/www/html/' . ($config['docroot'] ?? 'web') . '/sites/default';
$extraDockerFile = '/var/www/html/.ddev/docker-compose.redis_extra.yaml';

// Manual environment variable extraction
$projectType = $config['type'] ?? 'php';
$siteName = $config['name'] ?? 'default';
```

**After (With Proposed Improvements)**:

```php
// Simple environment access (working directory: /var/www/html/.ddev)
$targetDir = '../' . $_ENV['DDEV_DOCROOT'] . '/sites/default';
$extraDockerFile = 'docker-compose.redis_extra.yaml';

// Direct environment variable access
$projectType = $_ENV['DDEV_PROJECT_TYPE'];
$siteName = $_ENV['DDEV_SITENAME'];
```

**Implementation Requirements**:

1. **Environment Variables**: Pass same variables to PHP container as bash actions
2. **Working Directory**: Set PHP script execution directory to `/var/www/html/.ddev`  
3. **Path Consistency**: Ensure relative paths work identically to bash actions

## Migration Strategy

### For Simple Add-ons

1. Convert bash actions to inline PHP
2. Update file paths to container equivalents  
3. Test all scenarios thoroughly

### For Complex Add-ons

1. Break down into modular PHP scripts
2. Map complex bash operations to PHP equivalents
3. Handle environment access limitations
4. Maintain comprehensive test coverage

### For Add-ons with Host Dependencies

1. Evaluate if PHP translation is beneficial
2. Consider hybrid bash/PHP approach
3. Document limitations clearly
4. Provide fallback mechanisms

## Example: ddev-redis Translation Results

**Full Test Suite Results**: ✅ All 8 test scenarios passing

- Default installation
- Drupal 8+ installation  
- Drupal 7 installation (settings skipped)
- Drupal with disabled settings management
- Optimized configuration variants
- Laravel with multiple Redis backends
- Multiple Redis versions (6, 7)
- Valkey backend alternatives

**Performance**: Comparable to bash implementation
**Reliability**: Identical behavior validated through unchanged tests  
**Maintainability**: Improved code organization and error handling

## Conclusion

PHP add-on translation is viable and provides significant benefits for complex configuration processing. However, it requires careful handling of container environment limitations and systematic approach to configuration access.

The most significant challenge is the lack of access to processed DDEV configuration and global settings from within PHP containers. Addressing this limitation would significantly improve the PHP add-on development experience.

For add-ons that primarily handle file operations, YAML processing, and conditional logic, PHP translation offers substantial advantages in maintainability, cross-platform compatibility, and robustness.
