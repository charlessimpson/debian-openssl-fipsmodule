FROM debian:bookworm-slim

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends openssl; \
    rm -rf /var/lib/apt/lists/*

ENV OPENSSL_VERSION 3.0.8
ENV OPENSSL_SHA256 6c13d2bf38fdf31eac3ce2a347073673f5d63263398f1f69d0df4a41253e4b3e

RUN set -eux; \
    \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        dpkg-dev \
        gcc \
        gnupg \
        libfindbin-libs-perl \
        libc6-dev \
        make \
        wget \
    ; \
    rm -r /var/lib/apt/lists/*; \
    \
    wget -O openssl.tar.gz https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz; \
    echo "$OPENSSL_SHA256 *openssl.tar.gz" | sha256sum -c -; \
    \
    wget -O openssl.tar.gz.asc https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz.asc; \
    export GNUPGHOME="$(mktemp -d)"; \
    for key in \
        # Matt Caswell
        8657ABB260F056B1E5190839D9C4D26D0E604491 \
        # Paul Dale
        B7C1C14360F353A36862E4D5231C84CDDCC69C45 \
        # Richard Levitte
        7953AC1FBC3DC8B3B292393ED5E9E43F7DF9EE8C \
        A21FAB74B0088AA361152586B8EF1A6BA9DA2D5C \
        # Tomas Mraz
        EFC0A467D613CB83C7ED6D30D894E2CE8B3D79F5 \
        # openssl-omc@openssl.org
    ; do \
        gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$key"; \
    done; \
    gpg --batch --verify openssl.tar.gz.asc openssl.tar.gz; \
    gpgconf --kill all; \
    rm -rf "$GNUPGHOME" openssl.tar.gz.asc; \
    \
    mkdir -p src; \
    tar -xf openssl.tar.gz -C src --strip-components=1; \
    rm openssl.tar.gz; \
    cd src; \
    \
    DEB_ARCH=$(dpkg-architecture --query DEB_BUILD_GNU_TYPE); \
    ./Configure \
        --prefix=/usr \
        --openssldir=/usr/lib/ssl \
        --libdir=lib/$DEB_ARCH \
        enable-fips; \
    make -j "$(nproc)"; \
    make install_fips; \
    openssl fipsinstall -module /usr/lib/$DEB_ARCH/ossl-modules/fips.so -out /usr/lib/ssl/fipsmodule.cnf; \
    \
    cd ..; \
    rm -rf src; \
    \
    apt-mark auto '.*' > /dev/null; \
    [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    \
    sed -ri \
        -e 's!^# \.include fipsmodule\.cnf$!.include /usr/lib/ssl/fipsmodule.cnf!' \
        -e 's/^# providers = provider_sect$/providers = provider_sect/' \
        -e 's/^# \[provider_sect\]$/[provider_sect]/' \
        -e 's/^# default = default_sect$/base = base_sect/' \
        -e 's/^# fips = fips_sect$/fips = fips_sect/' \
        -e 's/^# \[default_sect\]$/[base_sect]/' \
        -e 's/^# activate = 1$/activate = 1/' \
        /etc/ssl/openssl.cnf; \
    \
    # Smoke test
    openssl fipsinstall -verify -module /usr/lib/$DEB_ARCH/ossl-modules/fips.so -in /usr/lib/ssl/fipsmodule.cnf; \
    openssl list -providers
