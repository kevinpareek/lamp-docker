vcl 4.0;

# ============================================
# Hybrid Mode VCL - Nginx -> Varnish -> Apache
# ============================================

backend default {
    .host = "webserver";
    .port = "80";
    .first_byte_timeout = 60s;
    .connect_timeout = 5s;
    .between_bytes_timeout = 2s;
    .probe = {
        .url = "/";
        .timeout = 2s;
        .interval = 5s;
        .window = 5;
        .threshold = 3;
        .initial = 3;
    }
}

# Common cache logic
sub vcl_recv {
    # Only cache GET and HEAD requests
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    # Strip cookies for static assets
    if (req.url ~ "\.(css|js|png|gif|jp(e)?g|swf|ico|woff|woff2|ttf|eot|svg|webp|avif)(\?.*)?$") {
        unset req.http.cookie;
        return (hash);
    }

    # Pass through for admin/login/cart pages
    if (req.url ~ "^/(wp-admin|wp-login|admin|checkout|cart|my-account|login|logout)") {
        return (pass);
    }

    # Pass through for authenticated users
    if (req.http.Authorization || req.http.Cookie ~ "(wordpress_logged_in|PHPSESSID|laravel_session)") {
        return (pass);
    }

    return (hash);
}

sub vcl_backend_response {
    # Cache static assets longer
    if (bereq.url ~ "\.(css|js|png|gif|jp(e)?g|swf|ico|woff|woff2|ttf|eot|svg|webp|avif)(\?.*)?$") {
        unset beresp.http.cookie;
        unset beresp.http.set-cookie;
        set beresp.ttl = 7d;
    }

    # Grace: serve stale content while fetching new
    set beresp.grace = 6h;
    
    # Don't cache errors
    if (beresp.status >= 500) {
        set beresp.ttl = 0s;
        set beresp.uncacheable = true;
    }
    
    return (deliver);
}

sub vcl_deliver {
    # Debug header
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
        set resp.http.X-Cache-Hits = obj.hits;
    } else {
        set resp.http.X-Cache = "MISS";
    }
    
    # Security: Remove internal headers
    unset resp.http.X-Powered-By;
    unset resp.http.Server;
    unset resp.http.X-Varnish;
    unset resp.http.Via;
}
