vcl 4.0;

# ============================================
# Default Varnish Configuration Template
# Copy and modify for custom setups
# Use hybrid.vcl or thunder.vcl for LAMP stack
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
    }
}

sub vcl_recv {
    # Only handle GET and HEAD requests
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    # Strip hash and other static parameters
    if (req.url ~ "\.(css|js|png|gif|jp(e)?g|swf|ico)") {
        unset req.http.cookie;
    }

    # Pass through for authentication/cookies (Basic WordPress/App logic)
    if (req.http.Authorization || req.http.Cookie) {
        return (pass);
    }

    return (hash);
}

sub vcl_backend_response {
    # Grace mode: Keep content for 2 minutes beyond TTL
    set beresp.grace = 2m;

    # Set a default TTL if not set by the backend
    if (beresp.ttl <= 0s) {
        set beresp.ttl = 120s;
        set beresp.uncacheable = true;
        return (deliver);
    }
    return (deliver);
}

sub vcl_deliver {
    # Add a header to indicate cache status
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
    
    # Remove some headers for security/cleanliness
    unset resp.http.X-Powered-By;
    unset resp.http.Server;
    unset resp.http.Via;
    unset resp.http.X-Varnish;
}
