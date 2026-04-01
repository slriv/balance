FROM alpine:3.20
RUN apk add --no-cache perl coreutils bash rsync
COPY lib /usr/local/lib
COPY bin/balance_tv.pl /usr/local/bin/balance_tv
COPY bin/sonarr_reconcile.pl /usr/local/bin/sonarr_reconcile
COPY bin/plex_reconcile.pl /usr/local/bin/plex_reconcile
RUN chmod +x /usr/local/bin/balance_tv /usr/local/bin/sonarr_reconcile /usr/local/bin/plex_reconcile
ENTRYPOINT ["balance_tv"]
