<?php

// Security headers
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('X-XSS-Protection: 1; mode=block');
header('Content-Type: text/html; charset=UTF-8');

require_once './config.php';

// Helper function for safe output
function e(string $str): string {
    return htmlspecialchars($str, ENT_QUOTES | ENT_HTML5, 'UTF-8');
}

echo "<h2>MySQLi Connection Test</h2>";
$link = mysqli_connect($MYSQL_HOST, $MYSQL_USER, $MYSQL_PASSWORD, null);

if (!$link) {
    echo "Error: Unable to connect to MySQL." . PHP_EOL;
    echo "Debugging errno: " . e((string)mysqli_connect_errno()) . PHP_EOL;
    echo "Debugging error: " . e(mysqli_connect_error() ?? 'Unknown error') . PHP_EOL;
} else {
    echo "Success: A proper connection to MySQL was made! The docker database is great." . PHP_EOL;
    mysqli_close($link);
}

echo "<hr/>";

echo "<h2>PDO Connection Test</h2>";
$pdo = null;

try {
    $database = 'mysql:host=' . $MYSQL_HOST . ';port=3306;charset=utf8mb4';
    $pdo = new PDO($database, $MYSQL_USER, $MYSQL_PASSWORD, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
    echo "Success: A proper connection to MySQL was made! The docker database is great.";
} catch (PDOException $ex) {
    echo "Error: Unable to connect to MySQL. Error:\n " . e($ex->getMessage());
}

$pdo = null;

echo '<hr/>';
echo '<a href="/">Back</a>';
