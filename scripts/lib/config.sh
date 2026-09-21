#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

if [[ -f "${ENV_FILE}" ]]; then
    set -o allexport
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +o allexport
fi

: "${TOTAL_ROUNDS:=32}"
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

RESULTS_DIR="${PROJECT_ROOT}/results"
NETWORK_DIR="${PROJECT_ROOT}/network/test-network"
MIDDLEWARE_DIR="${PROJECT_ROOT}/middleware"
CALIPER_DIR="${PROJECT_ROOT}/benchmarks/caliper_fabric"
JMETER_DIR="${PROJECT_ROOT}/benchmarks/jmeter_fabric"

export PROJECT_ROOT ENV_FILE TOTAL_ROUNDS JMETER_WORKERS CALIPER_WORKERS ORDERERS
export FABRIC_CHANNEL FABRIC_CHAINCODE FABRIC_VERSION API_HOST API_PORT
export MONITOR_HOST MONITOR_PORT JMETER_VERSION JAVA_VERSION RESULTS_DIR
export NETWORK_DIR MIDDLEWARE_DIR CALIPER_DIR JMETER_DIR

die() {
    echo "[ERRO] $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: $1. Execute: npm run setup"
}