FROM alpine:3.20
RUN apk add --no-cache perl perl-dev coreutils bash rsync sqlite-dev curl wget make gcc musl-dev
RUN curl -L https://cpanmin.us | perl - --notest Mojolicious DBI DBD::SQLite
COPY lib /usr/local/lib
COPY bin/balance_tv.pl /usr/local/bin/balance_tv
COPY bin/sonarr_reconcile.pl /usr/local/bin/sonarr_reconcile
COPY bin/plex_reconcile.pl /usr/local/bin/plex_reconcile
COPY bin/balance_web.pl /usr/local/bin/balance_web
COPY templates /usr/local/share/balance/templates
COPY public /usr/local/share/balance/public
RUN chmod +x /usr/local/bin/balance_tv /usr/local/bin/sonarr_reconcile /usr/local/bin/plex_reconcile /usr/local/bin/balance_web
ENTRYPOINT ["balance_tv"]
