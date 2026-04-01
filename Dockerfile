FROM alpine:3.20
RUN apk add --no-cache perl coreutils bash rsync
COPY bin/balance_tv.pl /usr/local/bin/balance_tv
RUN chmod +x /usr/local/bin/balance_tv
ENTRYPOINT ["balance_tv"]
