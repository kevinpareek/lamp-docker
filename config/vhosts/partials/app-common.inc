    <Directory ${APACHE_DOCUMENT_ROOT}/${APPLICATIONS_DIR_NAME}/${APP_NAME}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
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
