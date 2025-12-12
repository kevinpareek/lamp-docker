<?php

// Only allow access in development environment
$appEnv = $_SERVER['APP_ENV'] ?? getenv('APP_ENV') ?: 'development';
if (php_sapi_name() !== 'cli' && $appEnv === 'production') {
    http_response_code(403);
    echo 'Access denied in production environment';
    exit;
}

echo '<pre>';
print_r(get_loaded_extensions());
echo '</pre>';

echo '<hr/>';
echo '<a href="/">Back</a>';