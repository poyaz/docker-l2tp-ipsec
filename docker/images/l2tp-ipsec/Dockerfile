FROM alpine:3.18

RUN apk add --no-cache strongswan ppp xl2tpd openssh bash

COPY docker-entrypoint.sh docker-healcheck.sh /usr/local/bin/

RUN chmod +x \
    /usr/local/bin/docker-entrypoint.sh \
    /usr/local/bin/docker-healcheck.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

ENV VPN_ADDR=""
ENV VPN_USER=""
ENV VPN_PASS=""
ENV VPN_PSK=""

HEALTHCHECK --interval=30s --timeout=5s \
    CMD bash /usr/local/bin/docker-healcheck.sh