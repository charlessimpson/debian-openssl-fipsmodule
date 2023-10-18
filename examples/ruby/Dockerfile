FROM ruby:3.2-bookworm

ARG OPENSSL_MODULES=/usr/lib/x86_64-linux-gnu/ossl-modules

COPY --from=debian-openssl-fipsmodule:3.0.8 $OPENSSL_MODULES/fips.so $OPENSSL_MODULES/fips.so
RUN openssl fipsinstall -module $OPENSSL_MODULES/fips.so -out /usr/lib/ssl/fipsmodule.cnf
COPY --from=debian-openssl-fipsmodule:3.0.8 /etc/ssl/openssl.cnf /etc/ssl/openssl.cnf
