<?php
try {
     $pdo = new PDO("mysql:host=dbhost;dbname=docker", "docker", "VVtbwdNrdk3Wea2USp0");
     echo "Database connection successful!\n";
} catch (Exception $e) {
     echo "Database connection failed: " . $e->getMessage() . "\n";
}
?>