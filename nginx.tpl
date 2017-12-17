{% for srvname, service in services.items() %}
upstream {{ service.upstream }} {
{% for upstream in service.hosts %}
	server {{ upstream.host }}:{{ upstream.port }};
{% endfor %}
}

server {
    server_name {{ ' '.join(service.vhosts) }};
    listen [::]:443{{ ' default_server' if service.default }} ssl http2;
    listen 443{{ ' default_server' if service.default }} ssl http2;

    ssl_certificate {{ service.certificate }};
    ssl_trusted_certificate {{ service.trusted_certificate }};
    ssl_certificate_key {{ service.certificate_key }};

    include /etc/nginx/conf.d/{{ service.vhosts[0] }}/*.conf;

    # From https://community.letsencrypt.org/t/how-to-nginx-configuration-to-enable-acme-challenge-support-on-all-http-virtual-hosts/5622
    location ^~ /.well-known/acme-challenge/ {
        default_type "text/plain";
        alias {{ wellknown_path }};
    }

    # Hide /acme-challenge subdirectory and return 404 on all requests.
    # It is somewhat more secure than letting Nginx return 403.
    # Ending slash is important!
    location = /.well-known/acme-challenge/ {
        return 404;
    }

    location / {
        proxy_pass {{ service.protocol }}://{{ service.upstream }};
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
    }
}
{% endfor %}
