#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${CONFIG_DIR}/../.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

if [[ -f "${ENV_FILE}" ]]; then
    set -o allexport
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +o allexport
fi

: "${TOTAL_ROUNDS:=32}"
: "${BACKEND:=fabric}"
: "${JMETER_WORKERS:=25}"
: "${CALIPER_WORKERS:=5}"
: "${ORDERERS:=5}"
: "${FABRIC_CHANNEL:=gercom}"
: "${FABRIC_CHAINCODE:=simple}"
: "${FABRIC_VERSION:=2.5.14}"
: "${API_HOST:=127.0.0.1}"
: "${API_PORT:=3000}"
: "${MONITOR_HOST:=127.0.0.1}"
: "${MONITOR_PORT:=3002}"
: "${JMETER_VERSION:=5.6.3}"
: "${JAVA_VERSION:=21.0.7}"
: "${BESU_RPC_URL:=http://127.0.0.1:8545}"
: "${BESU_RPC_URLS:=${BESU_RPC_URL}}"
: "${BESU_API_PORT:=3001}"
: "${BESU_DEPLOYER_PRIVATE_KEY:=}"
: "${BESU_CONTRACT_ADDRESS:=}"

RESULTS_DIR="${PROJECT_ROOT}/results"
PYTHON_BIN="${PROJECT_ROOT}/.venv/bin/python"
NETWORK_DIR="${PROJECT_ROOT}/network/test-network"
MIDDLEWARE_DIR="${PROJECT_ROOT}/middleware"
CALIPER_DIR="${PROJECT_ROOT}/benchmarks/caliper_fabric"
JMETER_DIR="${PROJECT_ROOT}/benchmarks/jmeter_fabric"

export PROJECT_ROOT ENV_FILE BACKEND TOTAL_ROUNDS JMETER_WORKERS CALIPER_WORKERS ORDERERS
export FABRIC_CHANNEL FABRIC_CHAINCODE FABRIC_VERSION API_HOST API_PORT
export MONITOR_HOST MONITOR_PORT JMETER_VERSION JAVA_VERSION RESULTS_DIR PYTHON_BIN
export NETWORK_DIR MIDDLEWARE_DIR CALIPER_DIR JMETER_DIR
export BESU_RPC_URL BESU_RPC_URLS BESU_API_PORT BESU_DEPLOYER_PRIVATE_KEY BESU_CONTRACT_ADDRESS

die() {
    echo "[ERRO] $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: $1. Execute primeiro: bash scripts/install_dependencies.sh"
}

require_docker_access() {
    require_command docker
    docker info >/dev/null 2>&1 || die "Docker não está acessível. Execute manualmente: sudo usermod -aG docker ${USER} && newgrp docker"
    docker compose version >/dev/null 2>&1 || die "Docker Compose v2 não está disponível. Execute bash scripts/install_dependencies.sh"
}