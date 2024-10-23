<?php


ini_set('display_errors', true);
error_reporting(E_ALL);
ini_set("error_log", "404error.txt");

// Require Composer's autoloader.
require '404Medoo.php';

// Using Medoo namespace.
use Medoo\Medoo;

$database = new Medoo([
    // [required]
    'type' => 'mysql',
    'host' => 'database',
    'database' => 'docker',
    'username' => 'docker',
    'password' => 'docker',


    // [optional]
    'charset' => 'utf8mb4',
    'collation' => 'utf8mb4_general_ci',
    'port' => 3306,
    'prefix' => 'mp_',


    'logging' => false,
]);

function redirect(string $url = '/')
{
    header('Location: ' . $url);
    exit();
}

function getIP()
{
    foreach (array('HTTP_CF_CONNECTING_IP', 'REMOTE_ADDR', 'HTTP_X_FORWARDED_FOR',) as $key) {
        if (array_key_exists($key, $_SERVER) === true) {
            foreach (explode(',', $_SERVER[$key]) as $ip) {
                $ip = trim($ip);
                if ($ip == "::1") {
                    return '127.0.0.1';
                } elseif (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE) !== false) {
                    return $ip;
                }
            }
        }
    }

    return '127.0.0.1';
}

function pr($data, $type = 0)
{
    if (is_array($data)) {
        echo '<pre>';
        print_r($data);
        echo '</pre>';
    } elseif (is_object($data)) {
        //$data  = (array) $data;
        echo '<pre>';
        print_r($data);
        echo '</pre>';
    } else {
        echo $data;
    }

    if ($type != 0) {
        exit();
    } else {
        echo '<hr>';
    }
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
    //echo $data->rowCount(); // Returns the number of rows affected by the last SQL statement
    //$account_id = $data->id(); //Last Insert ID
    redirect("/404");


}
