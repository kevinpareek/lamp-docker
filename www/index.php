<?php

// echo '<pre>';
// print_r($_ENV);
// exit;

$MYSQL_HOST="database";
$MYSQL_DATABASE="docker";
$MYSQL_USER="docker";
$MYSQL_PASSWORD="docker";

$PMA_PORT="8080";
$LOCAL_DOCUMENT_ROOT = '/Users/pukharajpareek/Desktop/mywork/docker-lamp/htdocs';
$vhost_dir = '/etc/apache2/sites-enabled';
$domainData = [];

function extractDomainData($file)
{
    $content = file_get_contents($file);
    $domain = extractPattern($content, '/ServerName\s+(\S+)/');
    $path = extractPattern($content, '/DocumentRoot\s+(\S+)/');

    return $domain && $path ? ['domain' => $domain, 'path' => $path] : null;
}

function extractPattern($content, $pattern)
{
    return preg_match($pattern, $content, $matches) ? $matches[1] : '';
}

function getDomainData($vhost_dir)
{
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

$domainData = getDomainData($vhost_dir);

define('DOMAIN_APP_DIR', !empty($domainData[0]) ? explode("/", $domainData[0]['path'])[4] : 'applications');

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
    <style>
        .hero {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%) !important;
        }

        footer {
            margin-top: auto;
            padding: 20px 0;
            background-color: #222;
            color: #fff;
            text-align: center;
            width: 100%;
            display: flex;
            flex-direction: column;
            align-items: center;
            border-top: 5px solid #715dbb;
        }

        footer p {
            margin: 5px 0;
        }

        footer a {
            color: #715dbb;
            text-decoration: none;
        }

        footer a:hover {
            color: #fff;
            text-decoration: underline;
        }
    </style>
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
                            <li><?= apache_get_version(); ?></li>
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
                            <li><a href="/test_db.php">Test DB Connection with mysqli</a></li>
                            <li><a href="/test_db_pdo.php">Test DB Connection with PDO</a></li>
                            <li><a href="#">Check 404 Error</a></li>
                            <li><a href="#">Check Error</a></li>
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