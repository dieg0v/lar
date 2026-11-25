FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

COPY versions /tmp/lar-versions

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git unzip sudo zsh tzdata systemd-standalone-tmpfiles \
    && curl -fsSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb \
    && dpkg -i /tmp/debsuryorg-archive-keyring.deb \
    && printf '%s\n' 'deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ resolute main' > /etc/apt/sources.list.d/php.list \
    && apt-get update \
    && pkgs='' \
    && while read -r version listen; do \
         case "$version" in ''|\#*) continue ;; esac; \
         for mod in cli fpm mysql mbstring curl xml zip gd intl bcmath xdebug; do \
           pkgs="$pkgs php${version}-${mod}"; \
         done; \
         case "$version" in \
           8.5) ;; \
           *) pkgs="$pkgs php${version}-opcache" ;; \
         esac; \
         case "$version" in 5.6|7.*) pkgs="$pkgs php${version}-json" ;; esac; \
       done < /tmp/lar-versions \
    && apt-get install -y --no-install-recommends $pkgs \
    && rm -rf /var/lib/apt/lists/* /tmp/debsuryorg-archive-keyring.deb

RUN set -eu \
    && if getent group 1000 >/dev/null; then \
         web_group=$(getent group 1000 | cut -d: -f1); \
         if [ "$web_group" != "web" ]; then groupmod -n web "$web_group"; fi; \
       else \
         groupadd --gid 1000 web; \
       fi \
    && if getent passwd 1000 >/dev/null; then \
         web_user=$(getent passwd 1000 | cut -d: -f1); \
         if [ "$web_user" != "web" ]; then usermod -l web "$web_user"; fi; \
         usermod -d /home/web -m -g web -s /bin/zsh web; \
       else \
         useradd --uid 1000 --gid web --create-home --shell /bin/zsh web; \
       fi \
    && printf '%s\n' 'web ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/web \
    && chmod 440 /etc/sudoers.d/web \
    && passwd -l web \
    && mkdir -p /var/log/php /run/php /usr/local/lar \
    && chown web:web /var/log/php

RUN curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o /tmp/omz.sh \
    && su - web -c 'sh /tmp/omz.sh --unattended' \
    && rm -f /tmp/omz.sh

COPY node-versions /tmp/lar-node

RUN su - web -c 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash' \
    && su - web -c 'set -e; . "$HOME/.nvm/nvm.sh"; default=; while read -r version flag; do case "$version" in ""|\#*) continue ;; esac; nvm install "$version"; if [ "$flag" = "default" ]; then default=$version; fi; done < /tmp/lar-node; if [ -n "$default" ]; then nvm alias default "$default"; fi; nvm ls'

# Shell tools. mytop is not included: it watches a database server.
RUN set -eu \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        rclone rsync htop zip curl pdftk-java mysql-client \
        tar wget imagemagick ffmpeg tree python3 golang-go \
        jpegoptim optipng pngquant gifsicle webp libavif-bin \
        libxinerama1 libx11-6 libxext6 libxrender1 libsm6 libcups2 \
        libcairo2 libfontconfig1 libnss3 libxslt1.1 libxt6 libxrandr2 \
        libglu1-mesa libdbus-1-3 \
    && su - web -c '. "$HOME/.nvm/nvm.sh" && nvm use 22.21.1 && npm install -g svgo' \
    && ln -sfn "$(su - web -c '. "$HOME/.nvm/nvm.sh" && dirname "$(nvm which 22.21.1)"')/svgo" /usr/local/bin/svgo \
    && curl -fsSL -o /tmp/lo.tar.gz https://downloadarchive.documentfoundation.org/libreoffice/old/7.3.7.2/deb/x86_64/LibreOffice_7.3.7.2_Linux_x86-64_deb.tar.gz \
    && tar -xzf /tmp/lo.tar.gz -C /tmp \
    && dpkg -i /tmp/LibreOffice_7.3.7.2_Linux_x86-64_deb/DEBS/*.deb \
        || apt-get install -f -y --no-install-recommends \
    && ln -sfn /opt/libreoffice7.3/program/soffice /usr/local/bin/soffice \
    && ln -sfn /opt/libreoffice7.3/program/soffice /usr/local/bin/libreoffice \
    && curl -fsSL -o /usr/local/lib/unoconv https://raw.githubusercontent.com/unoconv/unoconv/0.7/unoconv \
    && chmod 755 /usr/local/lib/unoconv \
    && printf '%s\n' '#!/bin/sh' 'export UNO_PATH=/opt/libreoffice7.3/program' 'exec /opt/libreoffice7.3/program/python /usr/local/lib/unoconv "$@"' > /usr/local/bin/unoconv \
    && chmod 755 /usr/local/bin/unoconv \
    && soffice --version | grep -F '7.3.7.2' \
    && unoconv --version \
    && go version \
    && python3 --version \
    && for cmd in rclone rsync htop zip curl pdftk mysqldump tar wget ffmpeg tree jpegoptim optipng pngquant svgo gifsicle cwebp avifenc; do \
         command -v "$cmd"; \
       done \
    && { command -v magick || command -v convert; } \
    && rm -rf /var/lib/apt/lists/* /tmp/lo.tar.gz /tmp/LibreOffice_7.3.7.2_Linux_x86-64_deb

RUN rm -f /usr/local/bin/svgo \
    && printf '%s\n' '#!/bin/sh' 'exec /home/web/.nvm/versions/node/v22.21.1/bin/node /home/web/.nvm/versions/node/v22.21.1/lib/node_modules/svgo/bin/svgo.js "$@"' > /usr/local/bin/svgo \
    && chmod 755 /usr/local/bin/svgo \
    && svgo --version

# gulp 3 runs on Node 14. The CLI is global; the project sets the local version.
RUN su - web -c '. "$HOME/.nvm/nvm.sh" && nvm use 14.15.0 && npm install -g gulp-cli@2.3.0 --unsafe-perm --no-progress --cache /tmp/npm-cache' \
    && printf '%s\n' '#!/bin/sh' 'exec /home/web/.nvm/versions/node/v14.15.0/bin/node /home/web/.nvm/versions/node/v14.15.0/lib/node_modules/gulp-cli/bin/gulp.js "$@"' > /usr/local/bin/gulp \
    && chmod 755 /usr/local/bin/gulp

RUN set -eu \
    && apt-get update \
    && apt-get install -y --no-install-recommends tmux nano vim \
    && curl -fsSL -o /tmp/google-chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && apt-get install -y /tmp/google-chrome.deb \
    && rm -f /tmp/google-chrome.deb \
    && command -v tmux \
    && command -v nano \
    && command -v vim \
    && google-chrome --version \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch v0.7.1 https://github.com/zsh-users/zsh-autosuggestions.git /home/web/.oh-my-zsh/custom/plugins/zsh-autosuggestions \
    && git clone --depth 1 --branch 0.8.0 https://github.com/zsh-users/zsh-syntax-highlighting.git /home/web/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting \
    && chown -R web:web /home/web/.oh-my-zsh/custom/plugins

COPY zsh/lar.zsh-theme /home/web/.oh-my-zsh/custom/themes/lar.zsh-theme
COPY zsh/artisan.plugin.zsh /home/web/.oh-my-zsh/custom/plugins/artisan/artisan.plugin.zsh
COPY zsh/zshrc /home/web/.zshrc
COPY versions /usr/local/lar/versions
COPY entrypoint.sh /usr/local/bin/lar-php
COPY reload.sh /usr/local/bin/lar-php-reload

RUN chown web:web /home/web/.zshrc /home/web/.oh-my-zsh/custom/themes/lar.zsh-theme /home/web/.oh-my-zsh/custom/plugins/artisan/artisan.plugin.zsh \
    && chmod 755 /usr/local/bin/lar-php /usr/local/bin/lar-php-reload

# Composer stays in the image. The phar calls "php" from PATH, the one in this terminal.
RUN set -eu \
    && curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php \
    && php8.4 /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer \
    && rm -f /tmp/composer-setup.php \
    && php8.4 /usr/local/bin/composer --version

# qrencode and ping stay in the image. qrencode is /usr/bin/qrencode, version 4.1.1 or newer.
RUN set -eu \
    && apt-get update \
    && apt-get install -y --no-install-recommends qrencode iputils-ping \
    && rm -rf /var/lib/apt/lists/* \
    && test "$(command -v qrencode)" = /usr/bin/qrencode \
    && test "$(command -v ping)" = /usr/bin/ping \
    && qrencode --version 2>&1 | awk 'BEGIN { ok = 0 } /version/ { n = split($3, v, "."); major = v[1] + 0; minor = v[2] + 0; patch = v[3] + 0; if (major > 4 || (major == 4 && (minor > 1 || (minor == 1 && patch >= 1)))) ok = 1 } END { exit ok ? 0 : 1 }'

# upgrade.stamp changes when lar update accepts patches. This layer is rebuilt and the rest stays cached.
COPY upgrade.list /tmp/lar-upgrade.list
COPY upgrade.stamp /tmp/lar-upgrade.stamp
RUN set -eu \
    && pkgs=$(awk 'NF && $1 !~ /^#/ { printf "%s ", $1 }' /tmp/lar-upgrade.list) \
    && if [ -n "$pkgs" ]; then \
         apt-get update \
         && apt-get install -y --no-install-recommends --only-upgrade $pkgs \
         && rm -rf /var/lib/apt/lists/*; \
       fi

WORKDIR /home/web
ENTRYPOINT ["lar-php"]
