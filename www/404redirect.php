<?php

/**
 * 404 Error Logger and Redirect Handler
 * Logs 404 errors to database and redirects to 404 page
 */

// Only enable verbose errors in development
$appEnv = $_SERVER['APP_ENV'] ?? getenv('APP_ENV') ?: 'development';
if ($appEnv === 'development') {
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
} else {
    ini_set('display_errors', '0');
}
ini_set('error_log', '/var/log/php_errors.log');

// Require dependencies
require_once __DIR__ . '/Medoo.php';
require_once __DIR__ . '/config.php';

// Using Medoo namespace
use Medoo\Medoo;

/**
 * Redirect to a URL
 */
function redirect(string $url = '/'): void
{
    if (!headers_sent()) {
        header('Location: ' . $url);
    } else {
        echo '<script>window.location.href="' . htmlspecialchars($url, ENT_QUOTES, 'UTF-8') . '";</script>';
        echo '<noscript><meta http-equiv="refresh" content="0;url=' . htmlspecialchars($url, ENT_QUOTES, 'UTF-8') . '" /></noscript>';
    }
    exit();
}

/**
 * Get client IP address
 */
function getIP(): string
{
    $keys = ['HTTP_CF_CONNECTING_IP', 'HTTP_X_FORWARDED_FOR', 'HTTP_X_REAL_IP', 'REMOTE_ADDR'];
    foreach ($keys as $key) {
        if (!empty($_SERVER[$key])) {
            foreach (explode(',', $_SERVER[$key]) as $ip) {
                $ip = trim($ip);
                if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE) !== false) {
                    return $ip;
                }
            }
        }
    }
    return $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1';
}

try {
    $database = new Medoo([
        'type' => 'mysql',
        'host' => $MYSQL_HOST,
        'database' => $MYSQL_DATABASE,
        'username' => $MYSQL_USER,
        'password' => $MYSQL_PASSWORD,
        'charset' => 'utf8mb4',
        'collation' => 'utf8mb4_general_ci',
        'port' => 3306,
        'prefix' => 'mp_',
        'logging' => false,
        'error' => PDO::ERRMODE_EXCEPTION,
    ]);

    $url = $_SERVER['HTTP_REFERER'] ?? 'NULL';
    $r_url = $_SERVER['REQUEST_URI'] ?? '/';
    $c_time = time();
    $ip = getIP();

    // Check if entry exists
    $query = $database->select("page404", "*", [
        "p404_request_uri" => $r_url,
        "p404_http_referer" => $url,
        "p404_ip" => $ip
    ]);

    if (!empty($query) && count($query) > 0) {
        $idd = $query[0]['p404_id'];
        $database->update("page404", [
            "p404_count[+]" => 1,
            "p404_update" => $c_time
        ], ["p404_id" => $idd]);
    } else {
        $database->insert("page404", [
            "p404_http_referer" => $url,
            "p404_request_uri" => $r_url,
            "p404_create" => $c_time,
            "p404_update" => $c_time,
            "p404_ip" => $ip
        ]);
    }
} catch (Exception $e) {
    // Log error but don't expose to user
    error_log("404redirect.php error: " . $e->getMessage());
}

redirect("/404");
