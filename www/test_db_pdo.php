<?php

require_once './config.php';

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