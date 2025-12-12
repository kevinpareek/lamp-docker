<?php

require_once './config.php';

$domainData = [];

function extractDomainData($file)
{
    $content = file_get_contents($file);
    $domain = extractPattern($content, '/ServerName\s+([^\s;]+)/i');
    $path = extractPattern($content, '/DocumentRoot\s+([^\s;]+)/i');

    // Remove quotes if present
    $path = trim($path, '"\'');

    return $domain && $path ? ['domain' => $domain, 'path' => $path] : null;
}

function extractPattern($content, $pattern)
{
    return preg_match($pattern, $content, $matches) ? $matches[1] : '';
}

function getDomainData()
{
    $vhost_dir = '/etc/apache2/sites-enabled';
    $domainData = [];
    if (is_dir($vhost_dir)) {
        $confFiles = glob($vhost_dir . '/*.conf');
        foreach ($confFiles as $file) {
            if ($file != '/etc/apache2/sites-enabled/default.conf') {
                $data = extractDomainData($file);
                if ($data) {
                    $domainData[] = $data;
                }
            }
        }
    }
    return $domainData;
}

$domainData = getDomainData();

define('DOMAIN_APP_DIR', $APPLICATIONS_DIR_NAME ?? 'applications');

function getSubDir($currDir = null)
{
    $dir = $currDir ?? __DIR__;
    $exclude_dir = DOMAIN_APP_DIR;

    if (is_dir($dir)) {
        $filesAndDirs = scandir($dir);
        $subDirs = array_filter($filesAndDirs, fn($item) => is_dir($dir . DIRECTORY_SEPARATOR . $item) && $item != '.' && $item != '..');

        return array_filter($subDirs, fn($subDir) => $subDir != "assets" && $subDir != $exclude_dir);
    }
    return [];
}

?>

<!DOCTYPE html>
<html lang="en">

<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>LAMP STACK</title>
    <link rel="shortcut icon" href="/assets/images/favicon.svg" type="image/svg+xml">
    <link rel="stylesheet" href="/assets/css/bulma.min.css">
    <link rel="stylesheet" href="/style.css">
</head>

<body>
    <section class="hero is-medium is-info is-bold">
        <div class="hero-body">
            <div class="container has-text-centered">
                <h1 class="title">
                    LAMP STACK
                </h1>
                <h2 class="subtitle">
                    Your local development environment
                </h2>
            </div>
        </div>
    </section>
    <section class="section">
        <div class="container">
            <div class="columns">
                <div class="column">
                    <h3 class="title is-3 has-text-centered">Environment</h3>
                    <hr>
                    <div class="content">
                        <ul>
                            <li><?= function_exists('apache_get_version') ? apache_get_version() : $_SERVER['SERVER_SOFTWARE']; ?></li>
                            <li>PHP <?= phpversion(); ?></li>
                            <li>
                                <?php
                                $link = mysqli_connect($MYSQL_HOST, $MYSQL_USER, $MYSQL_PASSWORD, $MYSQL_DATABASE);

                                if (mysqli_connect_errno()) {
                                    printf("MySQL connection failed: %s", mysqli_connect_error());
                                } else {
                                    printf("MySQL Server %s", mysqli_get_server_info($link));
                                }
                                mysqli_close($link);
                                ?>
                            </li>
                            <li><a href="/phpinfo.php">PHP Info</a></li>
                            <li><a href="/phpinfo-modules.php">PHP Module</a></li>
                            <li><a href="/php-ext.php">PHP extensions</a></li>
                            <li><a href="/server.php">Server Param</a></li>
                        </ul>
                    </div>
                </div>
                <div class="column">
                    <h3 class="title is-3 has-text-centered">Quick Links</h3>
                    <hr>
                    <div class="content">
                        <ul>
                            <li><a target="_blank" href="http://localhost:<?= $PMA_PORT; ?>">phpMyAdmin</a></li>
                            <li><a href="/test_db.php">Test DB Connection (MySQLi & PDO)</a></li>
                            <li><a href="/nonexistent-page-test">Check 404 Error</a></li>
                            <li><a target="_blank" href="http://localhost:8025">Mailpit</a></li>
                        </ul>
                    </div>
                </div>
            </div>
        </div>
    </section>

    <section class="section">
        <div class="container">
            <div class="columns">
                <?php
                if (!empty($domainData)) {
                    echo '<div class="column">
    <h3 class="title is-3 has-text-centered">' . ucfirst(DOMAIN_APP_DIR) . '</h3>
    <hr>
    <div class="content">
        <ul>';

                    foreach ($domainData as $dd) {
                        echo '
                        <li>
                            <a target="_blank" href="https://' . $dd['domain'] . '">' . str_replace($_ENV['APACHE_DOCUMENT_ROOT'] . '/' . DOMAIN_APP_DIR . '/', '', $dd['path']) . '</a>
                            <br> -<code>' . $dd['path'] . '</code>
                            <br> -<code>' . str_replace($_ENV['APACHE_DOCUMENT_ROOT'], $LOCAL_DOCUMENT_ROOT, $dd['path']) . '</code>
                         </li>';
                    }
                    echo    '</ul>
    </div>
</div>';
                }

                $sDirList = getSubDir();
                if (!empty($sDirList)) {
                    foreach ($sDirList as $sDirName) {
                        echo '<div class="column">
                    <h3 class="title is-3 has-text-centered">' . ucfirst($sDirName) . '</h3>
                    <hr>
                    <div class="content">
                        <ul>';

                        $ssDirList = getSubDir(__DIR__ . '/' . $sDirName);
                        if (!empty($ssDirList)) {
                            foreach ($ssDirList as $ssDirName) {
                                echo '<li><a target="_blank" href="http://localhost/' . $sDirName . '/' . $ssDirName . '/">' . $ssDirName . '</a></li>';
                            }
                        }

                        echo    '</ul>
                    </div>
                </div>';
                    }
                }
                ?>
            </div>
        </div>
    </section>
    <footer>
        <p>
            <a href="https://github.com/kevinpareek/lamp-docker" target="_blank">LAMP Docker</a>
        </p>
        <p>Your local development environment</p>
    </footer>
</body>

</html>