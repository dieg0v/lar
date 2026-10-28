FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends apache2 \
    && a2enmod proxy proxy_fcgi rewrite headers ssl \
    && a2dissite 000-default \
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
    && sed -i 's/^export APACHE_RUN_USER=.*/export APACHE_RUN_USER=web/' /etc/apache2/envvars \
    && sed -i 's/^export APACHE_RUN_GROUP=.*/export APACHE_RUN_GROUP=web/' /etc/apache2/envvars \
    && rm -rf /var/lib/apt/lists/*

COPY conf/lar.conf /etc/apache2/conf-available/lar.conf
COPY htdocs/index.html /var/www/html/index.html
COPY entrypoint.sh /usr/local/bin/lar-apache

RUN a2enconf lar && chmod 755 /usr/local/bin/lar-apache

EXPOSE 80
ENTRYPOINT ["lar-apache"]
