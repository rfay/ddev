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

### 1. Container Environment Limitations

**Challenge**: PHP actions execute in containers without access to host `ddev` commands.

**Examples of Unavailable Commands**:

- `ddev debug configyaml` - Cannot access processed config from container
- `ddev dotenv get` - Environment file access is container-restricted  
- Host filesystem operations - Limited to mounted directories

**Solutions**:

```php
// INSTEAD OF: shell_exec('ddev debug configyaml')
$config = yaml_parse_file('/mnt/ddev_config/config.yaml');

// INSTEAD OF: shell_exec('ddev dotenv get .ddev/.env.redis --redis-optimized')
if (file_exists('/var/www/html/.ddev/.env.redis')) {
    $envContent = file_get_contents('/var/www/html/.ddev/.env.redis');
    $isOptimized = strpos($envContent, 'REDIS_OPTIMIZED="true"') !== false;
}

// INSTEAD OF: accessing global config via ddev commands
// Need alternative approach - currently limitation
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

### 4. Configuration Access Patterns

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

### 1. Standard Environment Variables

**Implementation**: Provide the same environment variables that bash actions receive.

```php
// SHOULD BE AVAILABLE (like in bash actions):
$_ENV['DDEV_APPROOT']     // '/var/www/html'  
$_ENV['DDEV_DOCROOT']     // 'web' or configured docroot
$_ENV['DDEV_PROJECT_TYPE'] // 'drupal', 'laravel', etc.
$_ENV['DDEV_SITENAME']    // Project name
$_ENV['DDEV_HOSTNAME']    // Primary hostname

// CURRENT WORKAROUND:
$config = yaml_parse_file('/mnt/ddev_config/config.yaml');
$docroot = $config['docroot'] ?? 'web';
$projectType = $config['type'] ?? 'php';
$siteName = $config['name'] ?? 'default';
```

### 2. Consistent Execution Context

**Implementation**: Execute PHP scripts in a known directory, matching bash behavior.

```bash
# Bash actions execute in: $DDEV_APPROOT/.ddev
# PHP actions should execute in: /var/www/html/.ddev
```

**Benefits**:

- Consistent relative path behavior  
- Matches bash action expectations
- Simplifies file access patterns

```php
// WITH CONSISTENT DIRECTORY:
file_put_contents('docker-compose.redis.yaml', $content);
// Instead of: file_put_contents('/var/www/html/.ddev/docker-compose.redis.yaml', $content);

// Access project files with consistent relative paths
$projectFile = '../composer.json';  // /var/www/html/composer.json
$configFile = 'config.yaml';        // /var/www/html/.ddev/config.yaml
```

### 3. Enhanced Container Context

```php
// NEEDED: Access to processed configuration
$globalConfig = ddev_get_global_config();
$processedConfig = ddev_get_processed_config();

// NEEDED: Runtime environment information  
$containerInfo = ddev_get_container_info();
$hostInfo = ddev_get_host_info();
```

### 4. Configuration Bridge

Mount additional configuration data into PHP containers:

- Processed global configuration
- Runtime environment variables
- Host system information
- Network configuration details

### 5. Debugging Support

```php
// NEEDED: Debug utilities
ddev_debug("Processing optimization config");
ddev_log_info("Created docker-compose file");
```

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
