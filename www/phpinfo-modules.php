<?php

// Only allow access in development environment
$appEnv = $_SERVER['APP_ENV'] ?? getenv('APP_ENV') ?: 'development';
if (php_sapi_name() !== 'cli' && $appEnv === 'production') {
    http_response_code(403);
    echo 'Access denied in production environment';
    exit;
}

phpinfo(INFO_MODULES);

echo '<hr/>';
echo '<a href="/">Back</a>';