<?php

/**
 * LAMP Docker Configuration
 * Updated by lamp config command
 * 
 * SECURITY NOTE: Change these default credentials in production!
 */

// Prevent direct access to config file
if (basename($_SERVER['SCRIPT_FILENAME'] ?? '') === 'config.php') {
    http_response_code(403);
    exit('Direct access not allowed');
}

# config value data - updated by lamp config command
# Default values for development environment
$MYSQL_HOST = 'database';
$MYSQL_DATABASE = 'docker';
$MYSQL_USER = 'docker';
$MYSQL_PASSWORD = 'docker';

$PMA_PORT = '8080';
$LOCAL_DOCUMENT_ROOT = dirname(__FILE__);
$APACHE_DOCUMENT_ROOT = '/var/www/html';
$APPLICATIONS_DIR_NAME = 'applications';
