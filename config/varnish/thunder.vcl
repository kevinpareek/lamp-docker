vcl 4.0;

# ============================================
# Thunder Mode VCL - Nginx -> Varnish -> nginx-fpm -> PHP-FPM
# Production-Ready Configuration
# Architecture: Client -> Nginx:80/443 -> Varnish:80 -> nginx-fpm:8080 -> PHP-FPM:9000
# ============================================

import std;

backend default {
    .host = "webserver";
    .port = "8080";
    .first_byte_timeout = 300s;
    .connect_timeout = 10s;
    .between_bytes_timeout = 10s;
    .max_connections = 300;
    .probe = {
        .url = "/health-check.php";
        .timeout = 5s;
        .interval = 10s;
        .window = 5;
        .threshold = 3;
        .initial = 3;
        .expected_response = 200;
    }
}

# ACL for purge requests
acl purge_allowed {
    "localhost";
    "127.0.0.1";
    "::1";
    "172.0.0.0"/8;  # Docker default network
    "192.168.0.0"/16;  # Docker custom networks
    "10.0.0.0"/8;  # Docker networks
}

sub vcl_recv {
    # ============================================
    # Normalize Accept-Encoding (Improve Cache Hit Rate)
    # ============================================
    if (req.http.Accept-Encoding) {
        if (req.url ~ "\.(jpg|png|gif|gz|tgz|bz2|tbz|mp3|ogg)$") {
            unset req.http.Accept-Encoding;
        } else if (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } else if (req.http.Accept-Encoding ~ "deflate") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            unset req.http.Accept-Encoding;
        }
    }

    # ============================================
    # Strip Varnish internal headers from backend
    # ============================================
    unset req.http.X-Varnish;

    # ============================================
    # DEVELOPMENT MODE: Bypass cache completely
    # ============================================
    if (req.http.X-App-Env == "development") {
        return (pass);
    }

    # ============================================
    # Health check endpoint
    # ============================================
    if (req.url == "/varnish-health") {
        return (synth(200, "OK"));
    }

    # ============================================
    # Purge handling
    # ============================================
    if (req.method == "PURGE") {
        if (!client.ip ~ purge_allowed) {
            return (synth(405, "Not allowed"));
        }
        return (purge);
    }

    # ============================================
    # Normalize host header
    # ============================================
    set req.http.Host = regsub(req.http.Host, ":[0-9]+", "");

    # ============================================
    # Normalize Query String (Improve Cache Hit Rate)
    # ============================================
    if (req.url ~ "\?") {
        # Remove tracking parameters
        set req.url = regsuball(req.url, "(^|&)(_ga|_gat|_gid|_fbp|_gcl_au|__utm|utm_source|utm_medium|utm_campaign|utm_content|utm_term|fbclid|gclid|msclkid|mc_cid|mc_eid)(&|$)", "\1");
        # Remove trailing & or ?
        set req.url = regsub(req.url, "(\?|&)$", "");
        # If only ? remains, remove it
        if (req.url ~ "\?$") {
            set req.url = regsub(req.url, "\?$", "");
        }
    }

    # ============================================
    # Only cache GET and HEAD
    # ============================================
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    # ============================================
    # Static assets - always cache
    # ============================================
    if (req.url ~ "\\.(css|js|png|gif|jpe?g|ico|woff2?|ttf|eot|svg|webp|avif|mp4|webm|pdf)($|\\?)") {
        unset req.http.Cookie;
        return (hash);
    }

    # ============================================
    # Admin/Login/Cart - never cache
    # ============================================
    if (req.url ~ "^/(wp-admin|wp-login|admin|checkout|cart|my-account|login|logout|register|dashboard|api/)") {
        return (pass);
    }

    # ============================================
    # POST requests - never cache
    # ============================================
    if (req.http.Authorization) {
        return (pass);
    }

    # ============================================
    # Session cookies - never cache
    # ============================================
    if (req.http.Cookie ~ "(wordpress_logged_in|PHPSESSID|laravel_session|PrestaShop-|wp-postpass|woocommerce_)") {
        return (pass);
    }

    # Strip marketing cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "(^|;\\s*)(_ga|_gat|_gid|_fbp|_gcl_au|__utm)[^;]*", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "^;\\s*", "");
    
    if (req.http.Cookie ~ "^\\s*$") {
        unset req.http.Cookie;
    }

    return (hash);
}

sub vcl_backend_response {
    # ============================================
    # Don't cache errors
    # ============================================
    if (beresp.status >= 500) {
        set beresp.ttl = 0s;
        set beresp.uncacheable = true;
        return (deliver);
    }

    # ============================================
    # Static assets - long TTL
    # ============================================
    if (bereq.url ~ "\\.(css|js|png|gif|jpe?g|ico|woff2?|ttf|eot|svg|webp|avif|mp4|webm|pdf)($|\\?)") {
        unset beresp.http.Cookie;
        unset beresp.http.Set-Cookie;
        set beresp.ttl = 30d;
        set beresp.http.Cache-Control = "public, max-age=2592000, immutable";
    }

    # ============================================
    # HTML pages & Redirects - short TTL
    # ============================================
    if (beresp.http.Content-Type ~ "text/html" || beresp.status == 301 || beresp.status == 302) {
        set beresp.ttl = 5m;
        set beresp.grace = 24h;
    }

    # ============================================
    # Grace period for stale content
    # ============================================
    set beresp.grace = 24h;
    set beresp.keep = 1h;

    # ============================================
    # Gzip handling
    # ============================================
    if (beresp.http.Content-Type ~ "(text|application/(json|javascript|xml))") {
        set beresp.do_gzip = true;
    }

    return (deliver);
}

sub vcl_deliver {
    # ============================================
    # Cache status headers (Only in development)
    # ============================================
    if (req.http.X-App-Env == "development") {
        if (obj.hits > 0) {
            set resp.http.X-Cache = "HIT";
            set resp.http.X-Cache-Hits = obj.hits;
        } else {
            set resp.http.X-Cache = "MISS";
        }
    } else {
        # Hide all cache/internal headers in production for clean look
        unset resp.http.X-Cache;
        unset resp.http.X-Cache-Hits;
        unset resp.http.Age;
        unset resp.http.X-Varnish;
        unset resp.http.Via;
    }

    # ============================================
    # Security & Identification headers
    # ============================================
    unset resp.http.X-Powered-By;
    unset resp.http.Server;
    
    # Remove common security headers from backend to avoid duplicates 
    # and keep it minimal
    if (req.http.X-App-Env != "development") {
        unset resp.http.X-Frame-Options;
        unset resp.http.X-XSS-Protection;
        unset resp.http.X-Content-Type-Options;
        unset resp.http.Referrer-Policy;
        unset resp.http.Strict-Transport-Security;
    }
}

sub vcl_synth {
    if (resp.status == 200) {
        set resp.http.Content-Type = "text/plain; charset=utf-8";
        synthetic("OK");
        return (deliver);
    }
}

sub vcl_backend_error {
    set beresp.http.Content-Type = "text/html; charset=utf-8";
    synthetic({"<!DOCTYPE html>
<html>
<head><title>Service Temporarily Unavailable</title></head>
<body>
<h1>503 Service Temporarily Unavailable</h1>
<p>Please try again later.</p>
</body>
</html>"});
    return (deliver);
}
