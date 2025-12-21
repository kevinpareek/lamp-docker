<?php
/**
 * PHP Turbo Stack - Default Welcome Page
 * 
 * This page displays system information and service status.
 * Sensitive information is hidden in production mode.
 */

// Get environment settings
$app_env = getenv('APP_ENV') ?: 'development';
$installation_type = getenv('INSTALLATION_TYPE');

// Auto-detect installation type if not set
if (!$installation_type) {
    $server_ip = $_SERVER['SERVER_ADDR'] ?? '127.0.0.1';
    // Check if IP is public
    $is_public = filter_var(
        $server_ip, 
        FILTER_VALIDATE_IP, 
        FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE
    );
    
    // Also check for common local hostnames
    $host = $_SERVER['HTTP_HOST'] ?? '';
    $is_local_host = preg_match('/(localhost|\.local|\.test|\.example)$/i', $host);
    
    $installation_type = ($is_public && !$is_local_host) ? 'live' : 'local';
}

$stack_mode = getenv('STACK_MODE') ?: 'hybrid';
$php_version = getenv('PHPVERSION') ?: 'php8.3';
$database_type = getenv('DATABASE') ?: 'mysql8.0';
$is_production = ($app_env === 'production');
$is_live = ($installation_type === 'live');

// Get PHP extensions (only in development)
$extensions = [];
if (!$is_production) {
    $extensions = get_loaded_extensions();
    sort($extensions);
}

// Check services
$redis_status = false;
$redis_info = [];
$memcached_status = false;
$memcached_info = [];
$database_status = false;
$database_info = [];
$varnish_status = false;

// Check Redis
if (extension_loaded('redis')) {
    try {
        $redis = new Redis();
        $redis_status = @$redis->connect('redis', 6379, 1);
        if ($redis_status) {
            $redis_pass = getenv('REDIS_PASSWORD');
            if ($redis_pass) {
                try {
                    $redis->auth($redis_pass);
                } catch (Exception $e) {
                    // Auth failed but connection works
                }
            }
            // Get Redis info in development
            if (!$is_production) {
                try {
                    $info = $redis->info();
                    $redis_info = [
                        'version' => $info['redis_version'] ?? 'N/A',
                        'memory' => isset($info['used_memory_human']) ? $info['used_memory_human'] : 'N/A',
                        'clients' => $info['connected_clients'] ?? 'N/A',
                        'uptime' => isset($info['uptime_in_days']) ? $info['uptime_in_days'] . ' days' : 'N/A',
                    ];
                } catch (Exception $e) {}
            }
            $redis->close();
        }
    } catch (Exception $e) {
        $redis_status = false;
    }
}

// Check Memcached
if (extension_loaded('memcached')) {
    try {
        $memcached = new Memcached();
        $memcached->addServer('memcached', 11211);
        $stats = $memcached->getStats();
        $memcached_status = $stats !== false && !empty($stats);
        
        // Get Memcached info in development
        if ($memcached_status && !$is_production) {
            $server_stats = reset($stats); // Get first server stats
            if ($server_stats) {
                $memcached_info = [
                    'version' => $server_stats['version'] ?? 'N/A',
                    'memory_used' => isset($server_stats['bytes']) ? round($server_stats['bytes'] / 1024 / 1024, 2) . ' MB' : 'N/A',
                    'memory_limit' => isset($server_stats['limit_maxbytes']) ? round($server_stats['limit_maxbytes'] / 1024 / 1024) . ' MB' : 'N/A',
                    'curr_items' => $server_stats['curr_items'] ?? 'N/A',
                    'total_items' => $server_stats['total_items'] ?? 'N/A',
                    'connections' => $server_stats['curr_connections'] ?? 'N/A',
                    'hits' => $server_stats['get_hits'] ?? 'N/A',
                    'misses' => $server_stats['get_misses'] ?? 'N/A',
                    'uptime' => isset($server_stats['uptime']) ? round($server_stats['uptime'] / 86400, 1) . ' days' : 'N/A',
                ];
            }
        }
    } catch (Exception $e) {
        $memcached_status = false;
    }
}

// Check Database
if (extension_loaded('mysqli')) {
    $db_host = getenv('MYSQL_HOST') ?: 'dbhost';
    $db_user = getenv('MYSQL_USER') ?: 'docker';
    $db_pass = getenv('MYSQL_PASSWORD') ?: 'docker';
    $db_name = getenv('MYSQL_DATABASE') ?: 'docker';
    
    $mysqli = @new mysqli($db_host, $db_user, $db_pass);
    $database_status = !$mysqli->connect_error;
    if ($database_status) {
        // Get database info in development
        if (!$is_production) {
            // Detect if MariaDB or MySQL from version string
            $version_string = $mysqli->server_info ?? '';
            $is_mariadb = stripos($version_string, 'mariadb') !== false;
            
            // Extract clean version number
            preg_match('/(\d+\.\d+\.\d+)/', $version_string, $matches);
            $clean_version = $matches[1] ?? $version_string;
            
            $database_info = [
                'host' => $db_host,
                'user' => $db_user,
                'database' => $db_name,
                'version' => $clean_version,
                'version_full' => $version_string,
                'type' => $is_mariadb ? 'MariaDB' : 'MySQL',
                'charset' => $mysqli->character_set_name() ?? 'N/A',
            ];
        }
        $mysqli->close();
    }
}

// Check Varnish (via HTTP header or direct connection)
$cache_header = $_SERVER['HTTP_X_CACHE'] ?? 'N/A';
$varnish_detected = ($cache_header !== 'N/A');

$varnish_status = false;
$varnish_socket = @fsockopen('varnish', 80, $errno, $errstr, 0.5);
if ($varnish_socket) {
    $varnish_status = true;
    fclose($varnish_socket);
} elseif ($varnish_detected) {
    $varnish_status = true;
}

// Caching is only active in production mode in this stack
// User logic: HIT = Active, MISS = Deactive
$is_caching_active = ($cache_header === 'HIT');

$varnish_info = [];
if (!$is_production) {
    $varnish_info = [
        'enabled' => $varnish_status,
        'detected' => $varnish_detected,
        'caching' => $is_caching_active,
        'mode' => $stack_mode,
        'cache_header' => $cache_header,
    ];
}

// Security recommendations based on environment
$security_tips = [];
if ($is_production && !$is_live) {
    $security_tips[] = [
        'type' => 'warning',
        'message' => 'Production mode with local installation. Consider switching to <code>INSTALLATION_TYPE=live</code> for public deployment.'
    ];
}
if (!$is_production && $is_live) {
    $security_tips[] = [
        'type' => 'error',
        'message' => '⚠️ Live server running in development mode! Set <code>APP_ENV=production</code> immediately.'
    ];
}
if (!$is_production) {
    $security_tips[] = [
        'type' => 'info',
        'message' => 'Development mode: Debug info visible. Switch to <code>APP_ENV=production</code> before going live.'
    ];
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PHP Turbo Stack</title>
    <meta name="robots" content="noindex, nofollow">
    <style>
        :root {
            --primary: #6366f1;
            --primary-dark: #4f46e5;
            --success: #10b981;
            --warning: #f59e0b;
            --error: #ef4444;
            --info: #3b82f6;
            --bg: #0f172a;
            --card: #1e293b;
            --text: #e2e8f0;
            --muted: #94a3b8;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
            background: var(--bg);
            color: var(--text);
            min-height: 100vh;
            padding: 2rem;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        header {
            text-align: center;
            margin-bottom: 2rem;
        }
        h1 {
            font-size: 2.5rem;
            font-weight: 700;
            background: linear-gradient(135deg, var(--primary) 0%, #a855f7 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            margin-bottom: 0.5rem;
        }
        .subtitle {
            color: var(--muted);
            font-size: 1.1rem;
        }
        .env-badge {
            display: inline-block;
            padding: 0.25rem 0.75rem;
            border-radius: 1rem;
            font-size: 0.8rem;
            font-weight: 600;
            margin: 0.5rem 0.25rem;
        }
        .env-production { background: rgba(16, 185, 129, 0.2); color: var(--success); }
        .env-development { background: rgba(245, 158, 11, 0.2); color: var(--warning); }
        .env-live { background: rgba(99, 102, 241, 0.2); color: var(--primary); }
        .env-local { background: rgba(148, 163, 184, 0.2); color: var(--muted); }
        .alert {
            padding: 1rem;
            border-radius: 0.5rem;
            margin-bottom: 1rem;
            display: flex;
            align-items: center;
            gap: 0.75rem;
        }
        .alert-error { background: rgba(239, 68, 68, 0.15); border: 1px solid var(--error); color: var(--error); }
        .alert-warning { background: rgba(245, 158, 11, 0.15); border: 1px solid var(--warning); color: var(--warning); }
        .alert-info { background: rgba(59, 130, 246, 0.15); border: 1px solid var(--info); color: var(--info); }
        .alert code { background: rgba(0,0,0,0.3); padding: 0.1rem 0.4rem; border-radius: 0.25rem; }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 1.5rem;
        }
        .card {
            background: var(--card);
            border-radius: 1rem;
            padding: 1.5rem;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .card h2 {
            font-size: 1.1rem;
            color: var(--primary);
            margin-bottom: 1rem;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }
        .info-row {
            display: flex;
            justify-content: space-between;
            padding: 0.5rem 0;
            border-bottom: 1px solid rgba(255,255,255,0.05);
        }
        .info-row:last-child { border-bottom: none; }
        .info-label { color: var(--muted); }
        .info-value { font-weight: 500; }
        .status {
            display: inline-flex;
            align-items: center;
            gap: 0.3rem;
            padding: 0.25rem 0.75rem;
            border-radius: 1rem;
            font-size: 0.85rem;
            font-weight: 500;
        }
        .status-ok { background: rgba(16, 185, 129, 0.2); color: var(--success); }
        .status-error { background: rgba(239, 68, 68, 0.2); color: var(--error); }
        .extensions {
            display: flex;
            flex-wrap: wrap;
            gap: 0.5rem;
        }
        .ext-tag {
            background: rgba(99, 102, 241, 0.2);
            color: var(--primary);
            padding: 0.25rem 0.75rem;
            border-radius: 0.5rem;
            font-size: 0.8rem;
        }
        .hidden-info {
            color: var(--muted);
            font-style: italic;
            padding: 1rem;
            text-align: center;
        }
        footer {
            text-align: center;
            margin-top: 3rem;
            color: var(--muted);
        }
        footer a {
            color: var(--primary);
            text-decoration: none;
        }
        footer a:hover { text-decoration: underline; }
        .best-practices {
            margin-top: 1.5rem;
        }
        .best-practices h3 {
            font-size: 0.9rem;
            color: var(--muted);
            margin-bottom: 0.75rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }
        .practice-item {
            display: flex;
            align-items: flex-start;
            gap: 0.5rem;
            padding: 0.5rem 0;
            font-size: 0.9rem;
            color: var(--text);
        }
        .practice-item .check { color: var(--success); }
        .practice-item .warn { color: var(--warning); }
        .config-value {
            font-family: 'Monaco', 'Consolas', monospace;
            font-size: 0.85rem;
            background: rgba(99, 102, 241, 0.15);
            padding: 0.15rem 0.5rem;
            border-radius: 0.25rem;
        }
        .section-title {
            font-size: 0.8rem;
            color: var(--muted);
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-top: 1rem;
            margin-bottom: 0.5rem;
            padding-top: 0.75rem;
            border-top: 1px solid rgba(255,255,255,0.05);
        }
        .copy-btn {
            background: rgba(99, 102, 241, 0.2);
            border: none;
            color: var(--primary);
            padding: 0.2rem 0.5rem;
            border-radius: 0.25rem;
            cursor: pointer;
            font-size: 0.75rem;
            margin-left: 0.5rem;
        }
        .copy-btn:hover { background: rgba(99, 102, 241, 0.4); }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🚀 PHP Turbo Stack</h1>
            <p class="subtitle">High-performance PHP development environment</p>
            <div>
                <span class="env-badge <?= $is_production ? 'env-production' : 'env-development' ?>">
                    <?= $is_production ? '🔒 Production' : '🔧 Development' ?>
                </span>
                <span class="env-badge <?= $is_live ? 'env-live' : 'env-local' ?>">
                    <?= $is_live ? '🌐 Live Server' : '💻 Local' ?>
                </span>
                <span class="env-badge" style="background: rgba(168, 85, 247, 0.2); color: #a855f7;">
                    ⚡ <?= ucfirst($stack_mode) ?> Mode
                </span>
            </div>
        </header>

        <?php if (!empty($security_tips)): ?>
            <?php foreach ($security_tips as $tip): ?>
                <div class="alert alert-<?= $tip['type'] ?>">
                    <?= $tip['message'] ?>
                </div>
            <?php endforeach; ?>
        <?php endif; ?>

        <div class="grid">
            <div class="card">
                <h2>📊 System Information</h2>
                <div class="info-row">
                    <span class="info-label">PHP Version</span>
                    <span class="info-value"><?= PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION . '.' . PHP_RELEASE_VERSION ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Web Server</span>
                    <span class="info-value"><?= php_sapi_name() === 'fpm-fcgi' ? 'PHP-FPM + Nginx (Thunder)' : 'Apache + mod_php (Hybrid)' ?></span>
                </div>
                <?php if (!$is_production): ?>
                <div class="info-row">
                    <span class="info-label">Stack Mode</span>
                    <span class="config-value"><?= strtoupper($stack_mode) ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Operating System</span>
                    <span class="info-value"><?= php_uname('s') . ' ' . php_uname('r') ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Server Software</span>
                    <span class="info-value"><?= $_SERVER['SERVER_SOFTWARE'] ?? 'N/A' ?></span>
                </div>
                <?php endif; ?>
                <div class="info-row">
                    <span class="info-label">Memory Limit</span>
                    <span class="info-value"><?= ini_get('memory_limit') ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Upload Max Size</span>
                    <span class="info-value"><?= ini_get('upload_max_filesize') ?></span>
                </div>
                <?php if (!$is_production): ?>
                <div class="info-row">
                    <span class="info-label">Post Max Size</span>
                    <span class="info-value"><?= ini_get('post_max_size') ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Max Execution Time</span>
                    <span class="info-value"><?= ini_get('max_execution_time') ?>s</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Max Input Vars</span>
                    <span class="info-value"><?= ini_get('max_input_vars') ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Display Errors</span>
                    <span class="info-value"><?= ini_get('display_errors') ? 'On' : 'Off' ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Error Reporting</span>
                    <span class="info-value"><?= ini_get('error_reporting') == E_ALL ? 'E_ALL' : ini_get('error_reporting') ?></span>
                </div>
                <?php endif; ?>
            </div>

            <div class="card">
                <h2>🔌 Service Status</h2>
                <div class="info-row">
                    <span class="info-label">Database</span>
                    <span class="status <?= $database_status ? 'status-ok' : 'status-error' ?>">
                        <?= $database_status ? '● Connected' : '○ Disconnected' ?>
                    </span>
                </div>
                <div class="info-row">
                    <span class="info-label">Redis</span>
                    <span class="status <?= $redis_status ? 'status-ok' : 'status-error' ?>">
                        <?= $redis_status ? '● Connected' : '○ Disconnected' ?>
                    </span>
                </div>
                <div class="info-row">
                    <span class="info-label">Varnish Cache</span>
                    <div style="text-align: right;">
                        <span class="status <?= $varnish_status ? 'status-ok' : 'status-error' ?>">
                            <?= $varnish_status ? '● Connected' : '○ Disconnected' ?>
                        </span>
                        <?php if ($varnish_status): ?>
                            <div style="font-size: 0.7rem; margin-top: 0.2rem; color: <?= $is_caching_active ? 'var(--success)' : 'var(--warning)' ?>;">
                                <?= $is_caching_active ? '● Caching Active (HIT)' : '○ Caching Deactive (MISS)' ?>
                            </div>
                        <?php endif; ?>
                    </div>
                </div>
                <div class="info-row">
                    <span class="info-label">Memcached</span>
                    <span class="status <?= $memcached_status ? 'status-ok' : 'status-error' ?>">
                        <?= $memcached_status ? '● Connected' : '○ Disconnected' ?>
                    </span>
                </div>
                <div class="info-row">
                    <span class="info-label">OPcache</span>
                    <span class="status <?= function_exists('opcache_get_status') && @opcache_get_status() ? 'status-ok' : 'status-error' ?>">
                        <?= function_exists('opcache_get_status') && @opcache_get_status() ? '● Enabled' : '○ Disabled' ?>
                    </span>
                </div>
                <?php if (!$is_production): ?>
                <div class="info-row">
                    <span class="info-label">APCu</span>
                    <span class="status <?= function_exists('apcu_enabled') && apcu_enabled() ? 'status-ok' : 'status-error' ?>">
                        <?= function_exists('apcu_enabled') && apcu_enabled() ? '● Enabled' : '○ Disabled' ?>
                    </span>
                </div>
                <div class="info-row">
                    <span class="info-label">Xdebug</span>
                    <span class="status <?= extension_loaded('xdebug') ? 'status-ok' : 'status-error' ?>">
                        <?= extension_loaded('xdebug') ? '● Enabled' : '○ Disabled' ?>
                    </span>
                </div>
                <?php endif; ?>

                <div class="best-practices">
                    <h3>📋 Best Practices</h3>
                    <?php if ($is_production): ?>
                        <div class="practice-item">
                            <span class="check">✓</span> Production mode enabled - errors hidden from users
                        </div>
                        <div class="practice-item">
                            <span class="<?= !extension_loaded('xdebug') ? 'check' : 'warn' ?>">
                                <?= !extension_loaded('xdebug') ? '✓' : '!' ?>
                            </span>
                            <?= !extension_loaded('xdebug') ? 'Xdebug disabled (recommended)' : 'Xdebug enabled - disable for better performance' ?>
                        </div>
                    <?php else: ?>
                        <div class="practice-item">
                            <span class="warn">!</span> Switch to <code>APP_ENV=production</code> before deployment
                        </div>
                        <div class="practice-item">
                            <span class="warn">!</span> Set <code>INSTALL_XDEBUG=false</code> for production
                        </div>
                    <?php endif; ?>
                    <?php if ($is_live): ?>
                        <div class="practice-item">
                            <span class="check">✓</span> Let's Encrypt SSL ready for public domains
                        </div>
                    <?php else: ?>
                        <div class="practice-item">
                            <span class="check">✓</span> Local SSL via mkcert for .localhost domains
                        </div>
                    <?php endif; ?>
                </div>
            </div>

            <?php if (!$is_production && $database_status && !empty($database_info)): ?>
            <div class="card">
                <h2>💾 Database Information</h2>
                <div class="info-row">
                    <span class="info-label">Type</span>
                    <span class="config-value"><?= htmlspecialchars($database_info['type']) ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Version</span>
                    <span class="info-value"><?= htmlspecialchars($database_info['version']) ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Charset</span>
                    <span class="info-value"><?= htmlspecialchars($database_info['charset']) ?></span>
                </div>
                <div class="section-title">Connection Details</div>
                <div class="info-row">
                    <span class="info-label">Host</span>
                    <span class="config-value"><?= htmlspecialchars($database_info['host']) ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Port</span>
                    <span class="config-value">3306</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Username</span>
                    <span class="config-value"><?= htmlspecialchars($database_info['user']) ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Database</span>
                    <span class="config-value"><?= htmlspecialchars($database_info['database']) ?></span>
                </div>
                <div class="section-title">Quick Access</div>
                <div class="info-row">
                    <span class="info-label">phpMyAdmin</span>
                    <span class="info-value"><a href="http://localhost:8080" target="_blank" style="color: var(--primary);">localhost:8080</a></span>
                </div>
            </div>
            <?php endif; ?>

            <?php if (!$is_production && $redis_status && !empty($redis_info)): ?>
            <div class="card">
                <h2>🔴 Redis Information</h2>
                <div class="info-row">
                    <span class="info-label">Version</span>
                    <span class="info-value"><?= htmlspecialchars($redis_info['version']) ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Memory Used</span>
                    <span class="info-value"><?= htmlspecialchars($redis_info['memory']) ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Connected Clients</span>
                    <span class="info-value"><?= htmlspecialchars($redis_info['clients']) ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Uptime</span>
                    <span class="info-value"><?= htmlspecialchars($redis_info['uptime']) ?></span>
                </div>
                <div class="section-title">Connection Details</div>
                <div class="info-row">
                    <span class="info-label">Host</span>
                    <span class="config-value">redis</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Port</span>
                    <span class="config-value">6379</span>
                </div>
            </div>
            <?php endif; ?>

            <?php if (!$is_production && $memcached_status && !empty($memcached_info)): ?>
            <div class="card">
                <h2>🟢 Memcached Information</h2>
                <div class="info-row">
                    <span class="info-label">Version</span>
                    <span class="info-value"><?= htmlspecialchars($memcached_info['version']) ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Memory Used</span>
                    <span class="info-value"><?= htmlspecialchars($memcached_info['memory_used']) ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Memory Limit</span>
                    <span class="info-value"><?= htmlspecialchars($memcached_info['memory_limit']) ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Current Items</span>
                    <span class="info-value"><?= htmlspecialchars($memcached_info['curr_items']) ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Total Items</span>
                    <span class="info-value"><?= htmlspecialchars($memcached_info['total_items']) ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Connections</span>
                    <span class="info-value"><?= htmlspecialchars($memcached_info['connections']) ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Cache Hits</span>
                    <span class="info-value"><?= htmlspecialchars($memcached_info['hits']) ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Cache Misses</span>
                    <span class="info-value"><?= htmlspecialchars($memcached_info['misses']) ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Uptime</span>
                    <span class="info-value"><?= htmlspecialchars($memcached_info['uptime']) ?></span>
                </div>
                <div class="section-title">Connection Details</div>
                <div class="info-row">
                    <span class="info-label">Host</span>
                    <span class="config-value">memcached</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Port</span>
                    <span class="config-value">11211</span>
                </div>
            </div>
            <?php endif; ?>

            <?php if (!$is_production): ?>
            <div class="card">
                <h2>⚡ Varnish Cache</h2>
                <div class="info-row">
                    <span class="info-label">Service Status</span>
                    <span class="status <?= $varnish_status ? 'status-ok' : 'status-error' ?>">
                        <?= $varnish_status ? '● Connected' : '○ Disconnected' ?>
                    </span>
                </div>
                <div class="info-row">
                    <span class="info-label">Cache Result</span>
                    <span class="status <?= $is_caching_active ? 'status-ok' : 'status-error' ?>">
                        <?= $is_caching_active ? '● Active (HIT)' : '○ Deactive (MISS)' ?>
                    </span>
                </div>
                <div class="info-row">
                    <span class="info-label">Current Request</span>
                    <span class="info-value" style="color: <?= $varnish_detected ? 'var(--success)' : 'var(--error)' ?>;">
                        <?= $varnish_detected ? 'Via Varnish Proxy' : 'Direct Access (Bypassed)' ?>
                    </span>
                </div>
                <div class="info-row">
                    <span class="info-label">Stack Mode</span>
                    <span class="config-value"><?= strtoupper($stack_mode) ?></span>
                </div>
                <?php if ($stack_mode === 'hybrid'): ?>
                <div class="info-row">
                    <span class="info-label">Request Flow</span>
                    <span class="info-value" style="font-size: 0.85rem;">Nginx → Varnish → Apache</span>
                </div>
                <?php else: ?>
                <div class="info-row">
                    <span class="info-label">Request Flow</span>
                    <span class="info-value" style="font-size: 0.85rem;">Nginx → Varnish → PHP-FPM</span>
                </div>
                <?php endif; ?>
                <div class="section-title">Headers</div>
                <div class="info-row">
                    <span class="info-label">X-Varnish</span>
                    <span class="info-value"><?= $_SERVER['HTTP_X_VARNISH'] ?? 'N/A' ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">X-Cache</span>
                    <span class="info-value"><?= $_SERVER['HTTP_X_CACHE'] ?? 'N/A' ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Via</span>
                    <span class="info-value" style="font-size: 0.8rem;"><?= $_SERVER['HTTP_VIA'] ?? 'N/A' ?></span>
                </div>
            </div>

            <div class="card">
                <h2>📧 Developer Tools</h2>
                <div class="info-row">
                    <span class="info-label">Mailpit (Email)</span>
                    <span class="info-value"><a href="http://localhost:8025" target="_blank" style="color: var(--primary);">localhost:8025</a></span>
                </div>
                <div class="info-row">
                    <span class="info-label">phpMyAdmin</span>
                    <span class="info-value"><a href="http://localhost:8080" target="_blank" style="color: var(--primary);">localhost:8080</a></span>
                </div>
                <div class="section-title">SMTP Settings</div>
                <div class="info-row">
                    <span class="info-label">Host</span>
                    <span class="config-value">mailpit</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Port</span>
                    <span class="config-value">1025</span>
                </div>
            </div>

            <div class="card">
                <h2>🚀 Get Started</h2>
                <div style="display: flex; flex-direction: column; gap: 1rem; margin-top: 0.5rem;">
                    <div style="background: linear-gradient(135deg, rgba(99, 102, 241, 0.15) 0%, rgba(168, 85, 247, 0.15) 100%); border: 1px solid rgba(99, 102, 241, 0.3); border-radius: 0.75rem; padding: 1rem;">
                        <div style="display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.5rem;">
                            <span style="background: var(--primary); color: white; width: 28px; height: 28px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-weight: bold; font-size: 0.85rem;">1</span>
                            <span style="font-weight: 600; color: var(--text);">Interactive Menu</span>
                        </div>
                        <div style="display: flex; align-items: center; background: rgba(0,0,0,0.4); padding: 0.75rem 1rem; border-radius: 0.5rem;">
                            <span style="color: var(--muted); margin-right: 0.5rem;">$</span>
                            <code style="flex: 1; font-size: 1.1rem; color: #10b981; font-family: 'Monaco', 'Consolas', monospace;">tbs</code>
                            <button onclick="copyCmd('tbs', this)" style="background: rgba(99, 102, 241, 0.3); border: none; color: var(--primary); padding: 0.3rem 0.6rem; border-radius: 0.3rem; cursor: pointer; font-size: 0.75rem; display: flex; align-items: center; gap: 0.3rem;" onmouseover="this.style.background='rgba(99, 102, 241, 0.5)'" onmouseout="this.style.background='rgba(99, 102, 241, 0.3)'">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>
                                Copy
                            </button>
                        </div>
                        <p style="color: var(--muted); font-size: 0.85rem; margin-top: 0.5rem;">Opens interactive menu with all options</p>
                    </div>
                    <div style="background: linear-gradient(135deg, rgba(16, 185, 129, 0.15) 0%, rgba(59, 130, 246, 0.15) 100%); border: 1px solid rgba(16, 185, 129, 0.3); border-radius: 0.75rem; padding: 1rem;">
                        <div style="display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.5rem;">
                            <span style="background: var(--success); color: white; width: 28px; height: 28px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-weight: bold; font-size: 0.85rem;">2</span>
                            <span style="font-weight: 600; color: var(--text);">View All Commands</span>
                        </div>
                        <div style="display: flex; align-items: center; background: rgba(0,0,0,0.4); padding: 0.75rem 1rem; border-radius: 0.5rem;">
                            <span style="color: var(--muted); margin-right: 0.5rem;">$</span>
                            <code style="flex: 1; font-size: 1.1rem; color: #10b981; font-family: 'Monaco', 'Consolas', monospace;">tbs -h</code>
                            <button onclick="copyCmd('tbs -h', this)" style="background: rgba(16, 185, 129, 0.3); border: none; color: var(--success); padding: 0.3rem 0.6rem; border-radius: 0.3rem; cursor: pointer; font-size: 0.75rem; display: flex; align-items: center; gap: 0.3rem;" onmouseover="this.style.background='rgba(16, 185, 129, 0.5)'" onmouseout="this.style.background='rgba(16, 185, 129, 0.3)'">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>
                                Copy
                            </button>
                        </div>
                        <p style="color: var(--muted); font-size: 0.85rem; margin-top: 0.5rem;">Shows complete help with all available commands</p>
                    </div>
                </div>
                <script>
                function copyCmd(cmd, btn) {
                    navigator.clipboard.writeText(cmd).then(function() {
                        var originalHTML = btn.innerHTML;
                        btn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"></polyline></svg> Copied!';
                        btn.style.background = 'rgba(16, 185, 129, 0.5)';
                        setTimeout(function() { 
                            btn.innerHTML = originalHTML;
                            btn.style.background = '';
                        }, 1500);
                    });
                }
                </script>
            </div>
            <?php endif; ?>

            <?php if (!$is_production && !empty($extensions)): ?>
            <div class="card" style="grid-column: 1 / -1;">
                <h2>📦 Loaded PHP Extensions (<?= count($extensions) ?>)</h2>
                <div class="extensions">
                    <?php foreach ($extensions as $ext): ?>
                        <span class="ext-tag"><?= htmlspecialchars($ext) ?></span>
                    <?php endforeach; ?>
                </div>
            </div>
            <?php elseif ($is_production): ?>
            <div class="card" style="grid-column: 1 / -1;">
                <h2>📦 PHP Extensions</h2>
                <p class="hidden-info">🔒 Extension list hidden in production mode for security</p>
            </div>
            <?php endif; ?>
        </div>

        <footer>
            <p>
                <a href="https://github.com/kevinpareek/turbo-stack" target="_blank">PHP Turbo Stack v1.0.2</a>
                <?php if (!$is_production): ?>
                &nbsp;|&nbsp; Run <code>tbs help</code> for commands
                &nbsp;|&nbsp; <code>tbs app add myapp</code> to create an app
                <?php endif; ?>
            </p>
        </footer>
    </div>
</body>
</html>
