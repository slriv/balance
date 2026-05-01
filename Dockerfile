FROM perl:5.42-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsqlite3-dev rsync curl wget make gcc \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://cpanmin.us -o /usr/local/bin/cpanm \
 && chmod +x /usr/local/bin/cpanm \
 && cpanm --notest Mojolicious DBI DBD::SQLite \
 && rm -rf ~/.cpanm
COPY lib /usr/local/lib
COPY bin/balance_tv.pl /usr/local/bin/balance_tv
COPY bin/sonarr_reconcile.pl /usr/local/bin/sonarr_reconcile
COPY bin/plex_reconcile.pl /usr/local/bin/plex_reconcile
COPY bin/balance_web.pl /usr/local/bin/balance_web
COPY templates /usr/local/templates
COPY public /usr/local/public
RUN chmod +x /usr/local/bin/balance_tv /usr/local/bin/sonarr_reconcile /usr/local/bin/plex_reconcile /usr/local/bin/balance_web
ENTRYPOINT ["balance_tv"]
