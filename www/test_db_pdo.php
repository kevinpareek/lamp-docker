<?php

require_once './config.php';

$pdo = null;

try{
    $database = 'mysql:host='.$MYSQL_HOST.':3306';
    $pdo = new PDO($database, $MYSQL_USER, $MYSQL_PASSWORD);
    echo "Success: A proper connection to MySQL was made! The docker database is great.";    
} catch(PDOException $e) {
    echo "Error: Unable to connect to MySQL. Error:\n $e";
}

$pdo = null;

echo '<hr/>';
echo '<a href="/">Back</a>';