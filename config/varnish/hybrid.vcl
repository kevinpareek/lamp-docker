vcl 4.0;

backend default {
    .host = "webserver";
    .port = "80";
    .first_byte_timeout = 60s;
    .connect_timeout = 5s;
    .between_bytes_timeout = 2s;
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
    # Set TTL for static assets
    if (bereq.url ~ "\.(css|js|png|gif|jp(e)?g|swf|ico)") {
        unset beresp.http.cookie;
        set beresp.ttl = 365d;
    }

    # Allow stale content if backend is down
    set beresp.grace = 6h;
}

sub vcl_deliver {
    # Add debug header
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
}
