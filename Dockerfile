# syntax=docker/dockerfile:1

ARG PERL_VERSION=5.42

# =============================================================================
# Stage 1: builder — compilers, dev headers, cpanm
# =============================================================================
FROM perl:${PERL_VERSION} AS builder

ARG ARRAPI_REF=main
ARG PLEXAPI_REF=main

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        cpanminus \
        git \
        libsqlite3-dev \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install perl-arrapi (WebService::Arr)
RUN git clone --depth 1 --branch "${ARRAPI_REF}" \
        https://github.com/slriv/perl-arrapi.git /opt/src/arrapi
WORKDIR /opt/src/arrapi
RUN cpanm --notest --installdeps . && cpanm --notest .

# Install perl-plexapi (WebService::Plex)
RUN git clone --depth 1 --branch "${PLEXAPI_REF}" \
        https://github.com/slriv/perl-plexapi.git /opt/src/plexapi
WORKDIR /opt/src/plexapi
RUN cpanm --notest --installdeps . && cpanm --notest .

# Install App::Balance CPAN deps before copying source.
# This layer is cached as long as the dep list below does not change,
# so iterating on app code does not re-run a full cpanm install.
WORKDIR /opt/src/balance
RUN cpanm --notest \
        Mojolicious \
        DBI \
        DBD::SQLite \
        File::ShareDir \
        File::ShareDir::Install \
        LWP::UserAgent \
        JSON::XS \
        HTTP::Tiny \
        JSON::PP \
        Image::ExifTool

# Copy source and install the app (rebuilds on code changes only)
COPY . /opt/src/balance
RUN perl Makefile.PL \
    && make \
    && make install

# =============================================================================
# Stage 2: runtime — no build tools, no dev headers
# =============================================================================
FROM perl:${PERL_VERSION} AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libsqlite3-0 \
        curl \
        rsync \
        ca-certificates \
        inotify-tools \
    && rm -rf /var/lib/apt/lists/*

# Copy all installed Perl modules from builder
COPY --from=builder /usr/local/lib/perl5 /usr/local/lib/perl5

# Copy installed entrypoint scripts from builder
COPY --from=builder \
    /usr/local/bin/balance \
    /usr/local/bin/balance_web \
    /usr/local/bin/balance_plex \
    /usr/local/bin/balance_sonarr \
    /usr/local/bin/

# Entrypoint
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Non-root user
RUN useradd -m -u 1000 -s /bin/bash balance \
    && mkdir -p /artifacts \
    && chown balance:balance /artifacts

VOLUME ["/artifacts"]
USER balance

ENV BALANCE_ARTIFACT_ROOT=/artifacts

EXPOSE 3010

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -fs http://localhost:3010/ > /dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["balance_web", "daemon", "-l", "http://0.0.0.0:3010"]