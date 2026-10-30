FROM hashicorp/vault-enterprise:2.0.3-ent

USER root

RUN apk add --no-cache \
    curl \
    jq \
    bash \
    python3 \
    openssl \
    ca-certificates

COPY config/   /vault/config/
COPY scripts/  /vault/scripts/
RUN chmod +x /vault/scripts/*.sh

ENV VAULT_ADDR=http://127.0.0.1:8200

EXPOSE 8200 8201

ENTRYPOINT ["/bin/bash", "/vault/scripts/vault-entrypoint.sh"]
