<?php


ini_set('display_errors', true);
error_reporting(E_ALL);
ini_set("error_log", "404error.txt");

// Require Composer's autoloader.
require 'Medoo.php';
require 'config.php';

// Using Medoo namespace.
use Medoo\Medoo;

$database = new Medoo([
    // [required]
    'type' => 'mysql',
    'host' => $MYSQL_HOST,
    'database' => $MYSQL_DATABASE,
    'username' => $MYSQL_USER,
    'password' => $MYSQL_PASSWORD,


    // [optional]
    'charset' => 'utf8mb4',
    'collation' => 'utf8mb4_general_ci',
    'port' => 3306,
    'prefix' => 'mp_',


    'logging' => false,
]);

function redirect(string $url = '/')
{
    if (!headers_sent()) {
        header('Location: ' . $url);
    } else {
        echo '<script>window.location.href="' . $url . '";</script>';
        echo '<noscript><meta http-equiv="refresh" content="0;url=' . $url . '" /></noscript>';
    }
    exit();
}

function getIP()
{
    $keys = ['HTTP_CF_CONNECTING_IP', 'REMOTE_ADDR', 'HTTP_X_FORWARDED_FOR'];
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
    return '127.0.0.1';
}

if (isset($_SERVER['HTTP_REFERER'])) {
    $url = $_SERVER['HTTP_REFERER'];
} else {
    $url = "NULL";
}

$r_url = $_SERVER['REQUEST_URI'];
$c_time = time();
$ip = getIP();


$query = $database->select("page404", "*", ["p404_request_uri" => $r_url, "p404_http_referer" => $url, "p404_ip" => $ip]);
if (!empty($query) && count($query) > 0) {
    $idd = $query[0]['p404_id'];
    $data = $database->update("page404", ["p404_count[+]" => 1, "p404_update" => $c_time], ["p404_id" => $idd]);
    redirect("/404");

} else {
    $data = $database->insert("page404", ["p404_http_referer" => $url, "p404_request_uri" => $r_url, "p404_create" => $c_time, "p404_update" => $c_time, "p404_ip" => $ip]);
    redirect("/404");
}
