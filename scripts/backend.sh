#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/config.sh"

ACTION="${1:-}"
[[ -n "${ACTION}" ]] || die "Uso: BACKEND=fabric|besu $0 network-up|network-down|network-check|api"

case "${BACKEND}" in
    fabric)
        case "${ACTION}" in
            network-up) bash "${SCRIPT_DIR}/setup_fabric_network.sh" ;;
            network-down) bash "${SCRIPT_DIR}/setup_fabric_network.sh" --down ;;
            network-check) [[ -f "${NETWORK_DIR}/network.sh" ]] || die "Fabric test-network não encontrada" ;;
            api) exec node "${MIDDLEWARE_DIR}/api.js" ;;
            *) die "Ação inválida para Fabric: ${ACTION}" ;;
        esac
        ;;
    besu)
        case "${ACTION}" in
            network-up) bash "${PROJECT_ROOT}/setup_besu_network.sh" ;;
            network-check) bash "${PROJECT_ROOT}/setup_besu_network.sh" --check ;;
            network-down)
                [[ -f "${PROJECT_ROOT}/docker-compose.yaml" ]] || die "docker-compose.yaml do Besu não encontrado"
                docker compose -f "${PROJECT_ROOT}/docker-compose.yaml" down --volumes --remove-orphans
                ;;
            api)
                [[ -n "${BESU_DEPLOYER_PRIVATE_KEY}" ]] || die "BESU_DEPLOYER_PRIVATE_KEY não configurada"
                [[ -n "${BESU_CONTRACT_ADDRESS}" ]] || die "BESU_CONTRACT_ADDRESS não configurada"
                exec env \
                    BESU_RPC_URL="${BESU_RPC_URL}" \
                    BESU_DEPLOYER_PRIVATE_KEY="${BESU_DEPLOYER_PRIVATE_KEY}" \
                    BESU_CONTRACT_ADDRESS="${BESU_CONTRACT_ADDRESS}" \
                    BESU_API_PORT="${BESU_API_PORT}" \
                    node "${PROJECT_ROOT}/api-besu/api_single_node.js"
                ;;
            *) die "Ação inválida para Besu: ${ACTION}" ;;
        esac
        ;;
    *) die "BACKEND inválido: ${BACKEND}. Use fabric ou besu" ;;
esac