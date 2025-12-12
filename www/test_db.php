<?php

require_once './config.php';

echo "<h2>MySQLi Connection Test</h2>";
$link = mysqli_connect($MYSQL_HOST, $MYSQL_USER, $MYSQL_PASSWORD, null);

if (!$link) {
    echo "Error: Unable to connect to MySQL." . PHP_EOL;
    echo "Debugging errno: " . mysqli_connect_errno() . PHP_EOL;
    echo "Debugging error: " . mysqli_connect_error() . PHP_EOL;
} else {
    echo "Success: A proper connection to MySQL was made! The docker database is great." . PHP_EOL;
    mysqli_close($link);
}

echo "<hr/>";

echo "<h2>PDO Connection Test</h2>";
$pdo = null;

try {
    $database = 'mysql:host=' . $MYSQL_HOST . ';port=3306';
    $pdo = new PDO($database, $MYSQL_USER, $MYSQL_PASSWORD);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    echo "Success: A proper connection to MySQL was made! The docker database is great.";
} catch (PDOException $e) {
    echo "Error: Unable to connect to MySQL. Error:\n " . $e->getMessage();
}

$pdo = null;

echo '<hr/>';
echo '<a href="/">Back</a>';
