FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

# nginx.org mainline, pinned to 1.31.9. Ubuntu's package is a different version.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gpg \
    && curl -fsSL https://nginx.org/keys/nginx_signing.key \
        | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg \
    && printf '%s\n' 'deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/mainline/ubuntu resolute nginx' \
        > /etc/apt/sources.list.d/nginx.list \
    && printf '%s\n' '#!/bin/sh' 'exit 101' > /usr/sbin/policy-rc.d \
    && chmod 755 /usr/sbin/policy-rc.d \
    && apt-get update \
    && apt-get install -y --no-install-recommends nginx=1.31.9-1~resolute \
    && rm -f /usr/sbin/policy-rc.d \
    && rm -rf /var/lib/apt/lists/* \
    && nginx -v 2>&1 | grep -F 'nginx/1.31.9' \
    && if getent group 1000 >/dev/null; then \
         web_group=$(getent group 1000 | cut -d: -f1); \
         if [ "$web_group" != "web" ]; then groupmod -n web "$web_group"; fi; \
       else \
         groupadd --gid 1000 web; \
       fi \
    && if getent passwd 1000 >/dev/null; then \
         web_user=$(getent passwd 1000 | cut -d: -f1); \
         if [ "$web_user" != "web" ]; then usermod -l web "$web_user"; fi; \
         usermod -d /home/web -m -g web -s /usr/sbin/nologin web; \
       else \
         useradd --uid 1000 --gid web --create-home --shell /usr/sbin/nologin web; \
       fi \
    && rm -f /etc/nginx/sites-enabled/default

COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /usr/local/bin/lar-nginx

RUN chmod 755 /usr/local/bin/lar-nginx

EXPOSE 80
ENTRYPOINT ["lar-nginx"]
