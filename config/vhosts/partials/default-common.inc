    <Directory ${APACHE_DOCUMENT_ROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    # Optimization: Remove headers that cause duplication or leak info
    Header unset X-Powered-By
    Header unset Server

    # Health check endpoint (moved outside document root for safety)
    Alias /health-check.php /var/www/internal/health-check.php
    <Directory /var/www/internal>
        Require all granted
    </Directory>

    # Security: Block VCS directories
    <DirectoryMatch "/\.(git|svn|hg|bzr|cvs)">
        Require all denied
    </DirectoryMatch>
    
    # Security: Block sensitive files and extensions
    <FilesMatch "(\.env.*|\.ini$|\.htpasswd|\.htaccess|phpunit\.xml|composer\.(json|lock)|package(-lock)?\.json|yarn\.lock|Makefile|Dockerfile.*|docker-compose.*\.yml|\.(tdata|sdata|addonpk|bak|config|dist|fla|inc|log|psd|sh|sql|swp|tar|gz|zip|rar|7z))$">
        Require all denied
    </FilesMatch>
