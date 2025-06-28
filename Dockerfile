FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    openvpn tor iproute2 iptables procps \
 && rm -rf /var/lib/apt/lists/*

RUN getent group debian-tor || groupadd -g 101 debian-tor && \
    id -u debian-tor >/dev/null 2>&1 || useradd -u 101 -g debian-tor -s /bin/false debian-tor

RUN mkdir -p /etc/openvpn /var/lib/tor/openvpn_service /etc/tor

RUN mkdir -p /var/lib/tor/openvpn_service && \
    chown -R debian-tor:debian-tor /var/lib/tor/openvpn_service && \
    chmod 700 /var/lib/tor/openvpn_service

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/etc/openvpn", "/var/lib/tor/openvpn_service"]

EXPOSE 1195

ENTRYPOINT ["/entrypoint.sh"]
