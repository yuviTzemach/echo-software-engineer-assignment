FROM debian:bookworm-slim AS test
COPY build/output/*.deb /tmp/
RUN apt-get update \
    && apt-get install -y --no-install-recommends /tmp/nginx_*.deb \
    && rm -rf /var/lib/apt/lists/* /tmp/*.deb

STOPSIGNAL SIGQUIT
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]