<?php
/**
 * PHP Turbo Stack - Default Welcome Page
 */

// Get PHP extensions
$extensions = get_loaded_extensions();
sort($extensions);

// Check services
$redis_status = false;
$memcached_status = false;
$database_status = false;

// Check Redis
if (extension_loaded('redis')) {
    try {
        $redis = new Redis();
        $redis_status = @$redis->connect('redis', 6379, 1);
        if ($redis_status) $redis->close();
    } catch (Exception $e) {
        $redis_status = false;
    }
}

// Check Memcached
if (extension_loaded('memcached')) {
    try {
        $memcached = new Memcached();
        $memcached->addServer('memcached', 11211);
        $memcached_status = $memcached->getStats() !== false;
    } catch (Exception $e) {
        $memcached_status = false;
    }
}

// Check Database
if (extension_loaded('mysqli')) {
    $db_host = getenv('MYSQL_HOST') ?: 'database';
    $db_user = getenv('MYSQL_USER') ?: 'docker';
    $db_pass = getenv('MYSQL_PASSWORD') ?: 'docker';
    
    $mysqli = @new mysqli($db_host, $db_user, $db_pass);
    $database_status = !$mysqli->connect_error;
    if ($database_status) $mysqli->close();
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PHP Turbo Stack</title>
    <style>
        :root {
            --primary: #6366f1;
            --primary-dark: #4f46e5;
            --success: #10b981;
            --warning: #f59e0b;
            --error: #ef4444;
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
            margin-bottom: 3rem;
        }
        h1 {
            font-size: 2.5rem;
            font-weight: 700;
            background: linear-gradient(135deg, var(--primary) 0%, #a855f7 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            margin-bottom: 0.5rem;
        }
        .subtitle {
            color: var(--muted);
            font-size: 1.1rem;
        }
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
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🚀 PHP Turbo Stack</h1>
            <p class="subtitle">High-performance PHP development environment</p>
        </header>

        <div class="grid">
            <div class="card">
                <h2>📊 System Information</h2>
                <div class="info-row">
                    <span class="info-label">PHP Version</span>
                    <span class="info-value"><?= phpversion() ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Web Server</span>
                    <span class="info-value"><?= php_sapi_name() === 'fpm-fcgi' ? 'PHP-FPM + Nginx' : 'Apache' ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Operating System</span>
                    <span class="info-value"><?= php_uname('s') . ' ' . php_uname('r') ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Memory Limit</span>
                    <span class="info-value"><?= ini_get('memory_limit') ?></span>
                </div>
                <div class="info-row">
                    <span class="info-label">Max Execution Time</span>
                    <span class="info-value"><?= ini_get('max_execution_time') ?>s</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Upload Max Size</span>
                    <span class="info-value"><?= ini_get('upload_max_filesize') ?></span>
                </div>
            </div>

            <div class="card">
                <h2>🔌 Service Status</h2>
                <div class="info-row">
                    <span class="info-label">Database (MySQL/MariaDB)</span>
                    <span class="status <?= $database_status ? 'status-ok' : 'status-error' ?>">
                        <?= $database_status ? '● Connected' : '○ Disconnected' ?>
                    </span>
                </div>
                <div class="info-row">
                    <span class="info-label">Redis Cache</span>
                    <span class="status <?= $redis_status ? 'status-ok' : 'status-error' ?>">
                        <?= $redis_status ? '● Connected' : '○ Disconnected' ?>
                    </span>
                </div>
                <div class="info-row">
                    <span class="info-label">Memcached</span>
                    <span class="status <?= $memcached_status ? 'status-ok' : 'status-error' ?>">
                        <?= $memcached_status ? '● Connected' : '○ Disconnected' ?>
                    </span>
                </div>
                <div class="info-row">
                    <span class="info-label">OPcache</span>
                    <span class="status <?= function_exists('opcache_get_status') && opcache_get_status() ? 'status-ok' : 'status-error' ?>">
                        <?= function_exists('opcache_get_status') && opcache_get_status() ? '● Enabled' : '○ Disabled' ?>
                    </span>
                </div>
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
            </div>

            <div class="card" style="grid-column: 1 / -1;">
                <h2>📦 Loaded PHP Extensions</h2>
                <div class="extensions">
                    <?php foreach ($extensions as $ext): ?>
                        <span class="ext-tag"><?= htmlspecialchars($ext) ?></span>
                    <?php endforeach; ?>
                </div>
            </div>
        </div>

        <footer>
            <p>
                <a href="https://github.com/kevinpareek/turbo-stack" target="_blank">PHP Turbo Stack</a>
                &nbsp;|&nbsp; Run <code>tbs help</code> for commands
            </p>
        </footer>
    </div>
</body>
</html>
