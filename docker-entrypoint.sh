#!/bin/sh
set -e

CONFIG_PATH="${PAPERCLIP_CONFIG:-/paperclip/instances/default/config.json}"
CONFIG_DIR=$(dirname "$CONFIG_PATH")
ENV_FILE="$CONFIG_DIR/.env"

# Create directories if needed
mkdir -p "$CONFIG_DIR/data/storage" "$CONFIG_DIR/data/backups" "$CONFIG_DIR/secrets" "$CONFIG_DIR/logs"

# Generate config.json if missing (ephemeral container — regenerate every deploy)
if [ ! -f "$CONFIG_PATH" ]; then
  echo "[entrypoint] Generating config.json..."

  ALLOWED_HOSTNAMES="[]"
  if [ -n "$PAPERCLIP_ALLOWED_HOSTNAMES" ]; then
    # Convert comma-separated to JSON array
    ALLOWED_HOSTNAMES=$(echo "$PAPERCLIP_ALLOWED_HOSTNAMES" | awk -F',' '{
      printf "["
      for(i=1;i<=NF;i++) {
        gsub(/^[ \t]+|[ \t]+$/, "", $i)
        printf "\"%s\"", $i
        if(i<NF) printf ","
      }
      printf "]"
    }')
  fi

  cat > "$CONFIG_PATH" <<CONF
{
  "\$meta": {
    "version": 1,
    "updatedAt": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
    "source": "docker-entrypoint"
  },
  "database": {
    "mode": "postgres",
    "connectionString": "${DATABASE_URL}",
    "backup": {
      "enabled": true,
      "intervalMinutes": 60,
      "retentionDays": 30,
      "dir": "$CONFIG_DIR/data/backups"
    }
  },
  "logging": {
    "mode": "file",
    "logDir": "$CONFIG_DIR/logs"
  },
  "server": {
    "deploymentMode": "${PAPERCLIP_DEPLOYMENT_MODE:-authenticated}",
    "exposure": "${PAPERCLIP_DEPLOYMENT_EXPOSURE:-private}",
    "host": "${HOST:-0.0.0.0}",
    "port": ${PORT:-3100},
    "allowedHostnames": ${ALLOWED_HOSTNAMES},
    "serveUi": ${SERVE_UI:-true}
  },
  "auth": {
    "baseUrlMode": "auto",
    "disableSignUp": false
  },
  "storage": {
    "provider": "local_disk",
    "localDisk": {
      "baseDir": "$CONFIG_DIR/data/storage"
    },
    "s3": {
      "bucket": "",
      "region": "us-east-1",
      "endpoint": "",
      "prefix": "",
      "forcePathStyle": false
    }
  },
  "secrets": {
    "provider": "local_encrypted",
    "strictMode": false,
    "localEncrypted": {
      "keyFilePath": "$CONFIG_DIR/secrets/master.key"
    }
  }
}
CONF
  echo "[entrypoint] Config created at $CONFIG_PATH"
fi

# Ensure .env with JWT secret exists
if [ ! -f "$ENV_FILE" ] && [ -n "$PAPERCLIP_AGENT_JWT_SECRET" ]; then
  echo "PAPERCLIP_AGENT_JWT_SECRET=$PAPERCLIP_AGENT_JWT_SECRET" > "$ENV_FILE"
  echo "[entrypoint] Created .env with JWT secret"
fi

# Ensure master.key exists for local_encrypted secrets
KEY_FILE="$CONFIG_DIR/secrets/master.key"
if [ ! -f "$KEY_FILE" ]; then
  head -c 32 /dev/urandom | base64 > "$KEY_FILE"
  echo "[entrypoint] Generated master.key"
fi

# Start the server
exec node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js
