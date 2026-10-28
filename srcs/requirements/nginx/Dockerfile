FROM debian:bookworm

ARG DOMAIN_NAME

RUN apt-get update \
 && apt-get install -y --no-install-recommends nginx openssl \
 && rm -f /etc/nginx/sites-enabled/default \
 && ln -sf /dev/stdout /var/log/nginx/access.log \
 && ln -sf /dev/stderr /var/log/nginx/error.log \
 && mkdir -p /etc/nginx/ssl \
 && openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout /etc/nginx/ssl/server.key \
      -out /etc/nginx/ssl/server.crt \
      -subj "/CN=${DOMAIN_NAME}" \
      -addext "subjectAltName=DNS:${DOMAIN_NAME}" \
 && rm -rf /var/lib/apt/lists/*

COPY conf/nginx.conf /etc/nginx/conf.d/default.conf
RUN sed -i "s/DOMAIN_NAME_PLACEHOLDER/${DOMAIN_NAME}/" /etc/nginx/conf.d/default.conf

EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]
