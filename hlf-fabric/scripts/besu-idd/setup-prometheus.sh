#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

# RPC Besu
RPC_IP="${RPC_IP:-$(ip -4 addr show eth1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')}"
RPC_HTTP_PORT=8545
RPC_WS_PORT=8945
RPC_HTTP_URL="http://${RPC_IP}:${RPC_HTTP_PORT}/"
RPC_WS_URL="ws://${RPC_IP}:${RPC_WS_PORT}/"

# Network
CHAIN_ID=10001
NETWORK_NAME="Iliada Besu IDD"
NETWORK_SHORT_NAME="Iliada"
NETWORK_COIN_NAME="BesuCoin"
NETWORK_COIN_SYMBOL="BES"
NETWORK_COIN_DECIMALS=18

# Prometheus
PROMETHEUS_VERSION=0.15.0
PROMETHEUS_REPOSITORY_URL="https://github.com/prometheus-operator/kube-prometheus"
PROMETHEUS_BRANCH_VERSION="v${PROMETHEUS_VERSION}"

function clone_repositories() {
    git clone --branch "$PROMETHEUS_BRANCH_VERSION" "$PROMETHEUS_REPOSITORY_URL"
    cd blockscout/docker-compose
}

function update_docker_compose_config(){
    cat <<EOF > docker-compose.yml
version: '3.9'

services:
  redis-db:
    extends:
      file: ./services/redis.yml
      service: redis-db

  db-init:
    extends:
      file: ./services/db.yml
      service: db-init

  db:
    depends_on:
      db-init:
        condition: service_completed_successfully
    extends:
      file: ./services/db.yml
      service: db

  backend:
    depends_on:
      - db
      - redis-db
    extends:
      file: ./services/backend.yml
      service: backend
    build:
      context: ..
      dockerfile: ./docker/Dockerfile
      args:
        RELEASE_VERSION: ${BLOCKSCOUT_VERSION}
    links:
      - db:database
    environment:
      ETHEREUM_JSONRPC_HTTP_URL: ${RPC_HTTP_URL}
      ETHEREUM_JSONRPC_TRACE_URL: ${RPC_HTTP_URL}
      ETHEREUM_JSONRPC_WS_URL: ${RPC_WS_URL}
      CHAIN_ID: '${CHAIN_ID}'
    ports:
      - "${BLOCKSCOUT_BACKEND_PORT}:${BLOCKSCOUT_BACKEND_PORT}"

  nft_media_handler:
    depends_on:
      - backend
    extends:
      file: ./services/nft_media_handler.yml
      service: nft_media_handler
    build:
      context: ..
      dockerfile: ./docker/Dockerfile
      args:
        RELEASE_VERSION: ${BLOCKSCOUT_VERSION}

  visualizer:
    extends:
      file: ./services/visualizer.yml
      service: visualizer

  sig-provider:
    extends:
      file: ./services/sig-provider.yml
      service: sig-provider

  frontend:
    depends_on:
      - backend
    extends:
      file: ./services/frontend.yml
      service: frontend
    ports:
      - "${BLOCKSCOUT_FRONTEND_PORT}:${BLOCKSCOUT_FRONTEND_PORT}"

  stats-db-init:
    extends:
      file: ./services/stats.yml
      service: stats-db-init

  stats-db:
    depends_on:
      stats-db-init:
        condition: service_completed_successfully
    extends:
      file: ./services/stats.yml
      service: stats-db

  stats:
    depends_on:
      - stats-db
      - backend
    extends:
      file: ./services/stats.yml
      service: stats

  user-ops-indexer:
    depends_on:
      - db
      - backend
    extends:
      file: ./services/user-ops-indexer.yml
      service: user-ops-indexer

  proxy:
    depends_on:
      - backend
      - frontend
      - stats
    extends:
      file: ./services/nginx.yml
      service: proxy
EOF
}

function update_frontend_envs() {
    cat <<EOF > envs/common-frontend.env
NEXT_PUBLIC_API_HOST=${BLOCKSCOUT_BACKEND_HOST}
NEXT_PUBLIC_API_PROTOCOL=http
NEXT_PUBLIC_API_PORT=${BLOCKSCOUT_BACKEND_PORT}
NEXT_PUBLIC_API_WEBSOCKET_PROTOCOL=ws
NEXT_PUBLIC_API_BASE_PATH=/
NEXT_PUBLIC_API_SPEC_URL=https://raw.githubusercontent.com/blockscout/blockscout-api-v2-swagger/main/swagger.yaml
NEXT_PUBLIC_STATS_API_HOST=http://${BLOCKSCOUT_BACKEND_HOST}:${BLOCKSCOUT_BACKEND_PORT}
NEXT_PUBLIC_VISUALIZE_API_HOST=http://${VISUALIZER_HOST}:8081
NEXT_PUBLIC_NETWORK_NAME=${NETWORK_NAME}
NEXT_PUBLIC_NETWORK_SHORT_NAME=${NETWORK_SHORT_NAME}
NEXT_PUBLIC_NETWORK_ID=${CHAIN_ID}
NEXT_PUBLIC_NETWORK_CURRENCY_NAME=${NETWORK_COIN_NAME}
NEXT_PUBLIC_NETWORK_CURRENCY_SYMBOL=${NETWORK_COIN_SYMBOL}
NEXT_PUBLIC_NETWORK_CURRENCY_DECIMALS=${NETWORK_COIN_DECIMALS}
NEXT_PUBLIC_APP_HOST=${BLOCKSCOUT_FRONTEND_HOST}
NEXT_PUBLIC_APP_PROTOCOL=http
NEXT_PUBLIC_APP_PORT=${BLOCKSCOUT_FRONTEND_PORT}
NEXT_PUBLIC_IS_TESTNET=true
NEXT_PUBLIC_HOMEPAGE_CHARTS=['daily_txs']
NEXT_PUBLIC_AD_BANNER_PROVIDER=none
NEXT_PUBLIC_AD_TEXT_PROVIDER=none
# Optional: Uncomment and set if using WalletConnect
# NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID=
EOF
}

function update_backend_envs() {
  cat <<EOF > envs/common-blockscout.env
ETHEREUM_JSONRPC_VARIANT=besu
ETHEREUM_JSONRPC_TRANSPORT=http
ETHEREUM_JSONRPC_HTTP_URL=${RPC_HTTP_URL}
ETHEREUM_JSONRPC_TRACE_URL=${RPC_HTTP_URL}
ETHEREUM_JSONRPC_WS_URL=${RPC_WS_URL}
ETHEREUM_JSONRPC_DISABLE_ARCHIVE_BALANCES=false
ETHEREUM_JSONRPC_HTTP_TIMEOUT=60000
ETHEREUM_JSONRPC_ARCHIVE_BALANCES_WINDOW=200
ETHEREUM_JSONRPC_GETH_ALLOW_EMPTY_TRACES=true
DISABLE_PENDING_TRANSACTIONS_FETCHER=true
DISABLE_EXCHANGE_RATES=true
DISABLE_INDEXER=false
DISABLE_INDEXER_CATCHUP=false
INDEXER_DISABLE_INTERNAL_TRANSACTIONS_FETCHER=true
INDEXER_DISABLE_CONTRACT_CODE_FETCHER=true
CHAIN_ID=${CHAIN_ID}
COIN_NAME=${NETWORK_COIN_NAME}
COIN=${NETWORK_COIN_SYMBOL}
DATABASE_URL=${BLOCKSCOUT_DATABASE_URL}
ECTO_USE_SSL=false
POOL_SIZE=80
POOL_SIZE_API=10
PORT=${BLOCKSCOUT_BACKEND_PORT}
DISABLE_MARKET=true
ADMIN_PANEL_ENABLED=false
RE_CAPTCHA_DISABLED=true
DECODE_NOT_A_CONTRACT_CALLS=true
TXS_STATS_DAYS_TO_COMPILE_AT_INIT=10
COIN_BALANCE_HISTORY_DAYS=90
MICROSERVICE_VISUALIZE_SOL2UML_URL=http://${VISUALIZER_HOST}:8050/
MICROSERVICE_SIG_PROVIDER_URL=http://${SIG_PROVIDER_HOST}:8050/
MICROSERVICE_ACCOUNT_ABSTRACTION_URL=http://${ACCOUNT_ABSTRACTION_HOST}:8050/
MICROSERVICE_SC_VERIFIER_TYPE=eth_bytecode_db
MICROSERVICE_VISUALIZE_SOL2UML_ENABLED=true
MICROSERVICE_SIG_PROVIDER_ENABLED=true
NFT_MEDIA_HANDLER_ENABLED=false
NFT_MEDIA_HANDLER_REMOTE_DISPATCHER_NODE_MODE_ENABLED=false
SECRET_KEY_BASE=${BLOCKSCOUT_SECRET_KEY_BASE}
ACCOUNT_CLOAK_KEY=
ACCOUNT_ENABLED=false
ACCOUNT_REDIS_URL=redis://redis-db:6379
EOF
}

function update_user_ops_indexer_envs() {
  cat <<EOF > envs/common-user-ops-indexer.env
USER_OPS_INDEXER__SERVER__HTTP__ENABLED=true
USER_OPS_INDEXER__SERVER__HTTP__ADDR=0.0.0.0:8050
USER_OPS_INDEXER__SERVER__HTTP__MAX_BODY_SIZE=2097152
USER_OPS_INDEXER__SERVER__GRPC__ENABLED=false
USER_OPS_INDEXER__SERVER__GRPC__ADDR=0.0.0.0:8051
USER_OPS_INDEXER__API__MAX_PAGE_SIZE=100
USER_OPS_INDEXER__INDEXER__RPC_URL=${RPC_WS_URL}
USER_OPS_INDEXER__INDEXER__CONCURRENCY=20
USER_OPS_INDEXER__INDEXER__ENTRYPOINTS__V06=true
USER_OPS_INDEXER__INDEXER__ENTRYPOINTS__V07=true
USER_OPS_INDEXER__INDEXER__REALTIME__ENABLED=true
USER_OPS_INDEXER__INDEXER__PAST_RPC_LOGS_INDEXER__ENABLED=true
USER_OPS_INDEXER__INDEXER__PAST_RPC_LOGS_INDEXER__BLOCK_RANGE=1000
USER_OPS_INDEXER__INDEXER__PAST_DB_LOGS_INDEXER__ENABLED=true
USER_OPS_INDEXER__INDEXER__PAST_DB_LOGS_INDEXER__START_BLOCK=-100000
USER_OPS_INDEXER__INDEXER__PAST_DB_LOGS_INDEXER__END_BLOCK=0
USER_OPS_INDEXER__DATABASE__CONNECT__URL=${BLOCKSCOUT_DATABASE_URL}
USER_OPS_INDEXER__DATABASE__CREATE_DATABASE=false
USER_OPS_INDEXER__DATABASE__RUN_MIGRATIONS=true
USER_OPS_INDEXER__METRICS__ENABLED=true
USER_OPS_INDEXER__METRICS__ADDR=0.0.0.0:6060
USER_OPS_INDEXER__METRICS__ROUTE=/metrics
USER_OPS_INDEXER__JAEGER__ENABLED=false
USER_OPS_INDEXER__JAEGER__AGENT_ENDPOINT=localhost:6831
USER_OPS_INDEXER__TRACING__ENABLED=true
USER_OPS_INDEXER__TRACING__FORMAT=default
EOF
}

function update_configs() {
    update_docker_compose_config
    update_frontend_envs
    update_backend_envs
    update_user_ops_indexer_envs
}

function start_service() {
    docker-compose up -d
}

main() {
    clone_repositories
    update_configs
    start_service
    chown_directories
}

main "$@"