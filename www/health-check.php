<?php
/**
 * Health Check Endpoint for Turbo Stack
 * Used by Varnish probe and monitoring systems
 * 
 * Usage:
 *   /health-check.php         - Basic health (200 OK)
 *   /health-check.php?full=1  - Full status with service checks (JSON)
 */

// Prevent caching
header('Cache-Control: no-cache, no-store, must-revalidate');
header('Pragma: no-cache');
header('Expires: 0');

// Basic health check (default)
if (!isset($_GET['full'])) {
    http_response_code(200);
    header('Content-Type: text/plain');
    echo 'OK';
    exit;
}

// Full health check with service status
header('Content-Type: application/json');

$status = [
    'status' => 'healthy',
    'timestamp' => date('c'),
    'php_version' => PHP_VERSION,
    'services' => []
];

// Check MySQL/MariaDB
try {
    $dsn = 'mysql:host=' . (getenv('DB_HOST') ?: 'dbhost') . ';dbname=' . (getenv('MYSQL_DATABASE') ?: 'docker');
    $pdo = new PDO($dsn, getenv('MYSQL_USER') ?: 'docker', getenv('MYSQL_PASSWORD') ?: 'docker', [
        PDO::ATTR_TIMEOUT => 3,
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION
    ]);
    $status['services']['mysql'] = 'connected';
} catch (Exception $e) {
    $status['services']['mysql'] = 'error';
    $status['status'] = 'degraded';
}

// Check Redis
try {
    if (class_exists('Redis')) {
        $redis = new Redis();
        $redis->connect('redis', 6379, 2.0);
        $pass = getenv('REDIS_PASSWORD') ?: ($_ENV['REDIS_PASSWORD'] ?? ($_SERVER['REDIS_PASSWORD'] ?? ''));
        if ($pass) $redis->auth($pass);
        $redis->ping();
        $status['services']['redis'] = 'connected';
    } else {
        $status['services']['redis'] = 'extension_missing';
    }
} catch (Exception $e) {
    $status['services']['redis'] = 'error';
}

// Check Memcached
try {
    if (class_exists('Memcached')) {
        $memcached = new Memcached();
        $memcached->addServer('memcached', 11211);
        $memcached->getVersion();
        $status['services']['memcached'] = 'connected';
    } else {
        $status['services']['memcached'] = 'extension_missing';
    }
} catch (Exception $e) {
    $status['services']['memcached'] = 'error';
}

// Check disk space
$free = disk_free_space('/var/www/html');
$total = disk_total_space('/var/www/html');
$usedPercent = round(($total - $free) / $total * 100);
$status['disk'] = [
    'free_gb' => round($free / 1073741824, 2),
    'total_gb' => round($total / 1073741824, 2),
    'used_percent' => $usedPercent
];

if ($usedPercent > 90) {
    $status['status'] = 'degraded';
}

// Memory usage
$status['memory'] = [
    'used_mb' => round(memory_get_usage(true) / 1048576, 2),
    'peak_mb' => round(memory_get_peak_usage(true) / 1048576, 2)
];

// Set response code based on health status
// Note: Varnish probes usually don't use ?full=1, so they hit the basic check above.
// If they do use ?full=1, we return 200 even if degraded to prevent global 503.
http_response_code(200);
header('X-Health-Status: ' . $status['status']);
echo json_encode($status, JSON_PRETTY_PRINT);

