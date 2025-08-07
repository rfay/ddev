# DDEV PHP-based Add-ons Guide

DDEV add-ons now support PHP-based actions alongside traditional bash actions, opening up new possibilities for complex configuration processing, YAML manipulation, and cross-platform compatibility.

## Overview

PHP-based add-ons allow you to write installation and configuration logic in PHP instead of bash. This provides:

- **Better YAML processing** with the built-in php-yaml extension
- **Cross-platform compatibility** (no shell scripting differences)
- **Rich string manipulation** and data processing capabilities
- **Access to DDEV project configuration** through mounted directories
- **Familiar syntax** for developers working with PHP projects

## How PHP Actions Work

DDEV automatically detects PHP actions by looking for scripts that start with `<?php`. When found, these actions are executed in a PHP container with access to:

- Your project's `.ddev` directory mounted at `/mnt/ddev_config/`
- The php-yaml extension for parsing YAML files
- All standard PHP functionality for file manipulation, string processing, etc.

## Basic Syntax Comparison

### Traditional Bash Action

```yaml
pre_install_actions:
  - |
    #ddev-description: Process project configuration
    PROJECT_NAME=$(grep "^name:" .ddev/config.yaml | cut -d: -f2 | tr -d ' ')
    echo "Setting up project: $PROJECT_NAME"
    
    # Create configuration file
    cat > .ddev/my-addon-config.yaml << EOF
    name: $PROJECT_NAME
    type: addon-config
    EOF
```

### Equivalent PHP Action

```yaml
pre_install_actions:
  - |
    <?php
    #ddev-description: Process project configuration
    
    // Read DDEV config with proper YAML parsing
    $config = yaml_parse_file('/mnt/ddev_config/config.yaml');
    $projectName = $config['name'] ?? 'unknown';
    echo "Setting up project: $projectName\n";
    
    // Create configuration file
    $addonConfig = [
        'name' => $projectName,
        'type' => 'addon-config'
    ];
    file_put_contents('/mnt/ddev_config/my-addon-config.yaml', 
        yaml_emit($addonConfig));
    ?>
```

## Key Differences from Bash Actions

### 1. Execution Environment

**Bash Actions:**
- Run directly on the host system
- Have access to all host tools and environment
- Current directory is the project root

**PHP Actions:**
- Run inside a PHP container
- Limited to PHP and basic container tools
- Project `.ddev` directory mounted at `/mnt/ddev_config/`

### 2. File Access

**Bash Actions:**
```bash
# Direct access to .ddev directory
cat .ddev/config.yaml
echo "data" > .ddev/output.txt
```

**PHP Actions:**
```php
<?php
// Access via mounted directory
$config = file_get_contents('/mnt/ddev_config/config.yaml');
file_put_contents('/mnt/ddev_config/output.txt', 'data');
?>
```

### 3. Error Handling

**Bash Actions:**
```bash
#ddev-description: Check if file exists
if [ ! -f ".ddev/config.yaml" ]; then
    echo "Config file not found!"
    exit 1
fi
```

**PHP Actions:**
```php
<?php
#ddev-description: Check if file exists
if (!file_exists('/mnt/ddev_config/config.yaml')) {
    echo "Config file not found!\n";
    exit(1);
}
?>
```

### 4. YAML Processing

**Bash Actions (limited):**
```bash
# Basic grep-based parsing
DB_VERSION=$(grep "database:" -A 2 .ddev/config.yaml | grep "version:" | cut -d: -f2 | tr -d ' ')
```

**PHP Actions (robust):**
```php
<?php
// Full YAML parsing with php-yaml
$config = yaml_parse_file('/mnt/ddev_config/config.yaml');
$dbVersion = $config['database']['version'] ?? 'default';

// Generate complex YAML structures
$newConfig = [
    'services' => [
        'myservice' => [
            'image' => 'nginx:latest',
            'environment' => [
                'DB_VERSION' => $dbVersion
            ]
        ]
    ]
];
file_put_contents('/mnt/ddev_config/docker-compose.myservice.yaml', 
    "#ddev-generated\n" . yaml_emit($newConfig));
?>
```

## Practical Examples

### Example 1: Environment-based Configuration

```yaml
name: conditional-config
image: ddev/ddev-webserver:latest

pre_install_actions:
  - |
    <?php
    #ddev-description: Generate environment-specific configuration
    
    $config = yaml_parse_file('/mnt/ddev_config/config.yaml');
    $projectType = $config['type'] ?? 'php';
    
    // Generate different configs based on project type
    $services = [];
    
    switch($projectType) {
        case 'drupal':
            $services['redis'] = [
                'image' => 'redis:7-alpine',
                'ports' => ['6379:6379']
            ];
            break;
        case 'wordpress':
            $services['memcached'] = [
                'image' => 'memcached:alpine',
                'ports' => ['11211:11211']
            ];
            break;
        default:
            $services['cache'] = [
                'image' => 'nginx:alpine'
            ];
    }
    
    $composeContent = [
        'services' => $services
    ];
    
    file_put_contents('/mnt/ddev_config/docker-compose.conditional.yaml',
        "#ddev-generated\n" . yaml_emit($composeContent));
        
    echo "Generated configuration for $projectType project\n";
    ?>
```

### Example 2: Complex Data Transformation

```yaml
name: data-transformer
image: ddev/ddev-webserver:latest

yaml_read_files:
  platform_config: ".platform.app.yaml"

pre_install_actions:
  - |
    <?php
    #ddev-description: Transform Platform.sh config to DDEV format
    
    // This would be populated by yaml_read_files
    $platformConfig = '/mnt/ddev_config/.platform.app.yaml';
    
    if (file_exists($platformConfig)) {
        $platform = yaml_parse_file($platformConfig);
        
        // Extract PHP version
        $phpVersion = '8.1';
        if (isset($platform['type']) && strpos($platform['type'], 'php:') === 0) {
            $phpVersion = str_replace('php:', '', $platform['type']);
        }
        
        // Transform build commands
        $hooks = [];
        if (isset($platform['hooks']['build'])) {
            $buildCommands = explode("\n", trim($platform['hooks']['build']));
            $hooks['post-start'] = array_map(function($cmd) {
                return ['exec' => trim($cmd)];
            }, $buildCommands);
        }
        
        // Generate DDEV config
        $ddevConfig = [
            'php_version' => $phpVersion,
            'hooks' => $hooks
        ];
        
        file_put_contents('/mnt/ddev_config/config.platform.yaml',
            "#ddev-generated\n" . yaml_emit($ddevConfig));
            
        echo "Transformed Platform.sh config (PHP $phpVersion)\n";
    }
    ?>
```

### Example 3: Mixed Bash and PHP Actions

```yaml
name: mixed-actions-addon

pre_install_actions:
  - |
    #ddev-description: Prepare system dependencies
    echo "Installing system dependencies..."
    # Bash is better for system-level tasks
    
  - |
    <?php
    #ddev-description: Process configuration files  
    // PHP is better for data processing
    $config = yaml_parse_file('/mnt/ddev_config/config.yaml');
    $projectName = $config['name'];
    echo "Processing config for: $projectName\n";
    ?>
    
  - |
    #ddev-description: Set file permissions
    chmod +x .ddev/commands/web/mycommand
    # Back to bash for file system operations
```

## Best Practices

### 1. Use Appropriate Tool for Each Task

- **Use PHP for:** Complex data processing, YAML manipulation, conditional logic
- **Use Bash for:** File permissions, system commands, environment setup

### 2. Proper Description Comments

```php
<?php
#ddev-description: Generate service configuration based on project type
// PHP comment explaining the logic
?>
```

### 3. Error Handling

```php
<?php
if (!file_exists('/mnt/ddev_config/config.yaml')) {
    echo "Error: DDEV config file not found\n";
    exit(1);
}
?>
```

### 4. Clean Output

```php
<?php
#ddev-description: Configure database settings
// Keep output informative but concise
echo "Database configured for project\n";
// Avoid verbose debugging output unless debugging
?>
```

## Available Test Examples

The DDEV repository includes several test add-ons demonstrating PHP functionality:

### Basic PHP Addon
**Location:** `cmd/ddev/cmd/testdata/TestCmdAddonPHP/basic-php-addon/`

Shows fundamental PHP action usage:
- Reading DDEV configuration
- File creation and manipulation
- Mixed PHP and bash actions

### Complex PHP Addon  
**Location:** `cmd/ddev/cmd/testdata/TestCmdAddonPHP/complex-php-addon/`

Demonstrates advanced features:
- YAML file parsing with php-yaml extension
- Complex data structure manipulation
- Docker compose generation

### Mixed Actions Addon
**Location:** `cmd/ddev/cmd/testdata/TestCmdAddonPHP/mixed-addon/`

Shows best practices for combining bash and PHP:
- Sequential bash and PHP actions
- Proper description usage
- Action coordination

### Varnish PHP Addon
**Location:** `cmd/ddev/cmd/testdata/TestCmdAddonPHP/varnish-php-addon/`

Real-world example converting a bash addon to PHP:
- Configuration file processing
- HEREDOC usage for clean YAML generation
- Error handling and validation

### Custom Image Addon
**Location:** `cmd/ddev/cmd/testdata/TestCmdAddonPHP/custom-image-addon/`

Demonstrates using custom PHP images:
- Specifying alternative PHP versions
- Image compatibility testing

## Migration from Bash

When migrating existing bash actions to PHP, consider:

1. **File paths:** Change `.ddev/file` to `/mnt/ddev_config/file`
2. **YAML parsing:** Replace grep/sed with `yaml_parse_file()`
3. **Variables:** Convert `$DDEV_PROJECT` style to reading config files
4. **Output:** Add `\n` to echo statements for proper line breaks

## Limitations

- No direct access to host system (by design)
- Limited to tools available in the PHP container
- File operations restricted to mounted `.ddev` directory
- Cannot execute host-specific commands like `ddev` itself

## Container Image

PHP actions currently use `ddev/ddev-webserver:20250806_rfay_php_addon` which includes:
- PHP with php-yaml extension
- Basic container utilities
- Access to mounted project `.ddev` directory

## Getting Started

1. Start with the [ddev-addon-template](https://github.com/ddev/ddev-addon-template)
2. Replace bash actions with PHP equivalents where beneficial
3. Test thoroughly with the test add-ons as references
4. Follow the [Add-on Maintenance Guide](https://ddev.com/blog/ddev-add-on-maintenance-guide/) for ongoing updates

PHP-based add-ons provide a powerful complement to traditional bash actions, enabling more sophisticated configuration processing while maintaining the simplicity and reliability DDEV users expect.