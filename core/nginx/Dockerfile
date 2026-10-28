FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
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
