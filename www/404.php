<?php


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

pr("404 Page Error");
pr($_SERVER);


echo '<hr/>';
echo '<a href="/">Back</a>';