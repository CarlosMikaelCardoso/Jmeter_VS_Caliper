#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/config.sh"

install_node_dependencies() {
    local node_major
    node_major="$(node -p 'process.versions.node.split(".")[0]')"
    ((node_major >= 20)) || die "Node.js 20 ou superior é necessário; versão encontrada: ${node_major}"
    echo "[INFO] Instalando dependências Node com lockfiles"
    (cd "${PROJECT_ROOT}" && npm ci)
    (cd "${MIDDLEWARE_DIR}" && npm ci)
    (cd "${PROJECT_ROOT}/api-besu" && npm ci)
}

install_python_dependencies() {
    local venv="${PROJECT_ROOT}/.venv"
    python3 -m venv "${venv}"
    "${venv}/bin/python" -m pip install --upgrade pip
    "${venv}/bin/pip" install -r "${PROJECT_ROOT}/requirements.txt"
}

main() {
    require_command node
    require_command npm
    require_command python3
    require_command go
    require_command docker
    docker compose version >/dev/null 2>&1 || die "Docker Compose v2 não encontrado. Execute primeiro: bash scripts/install_dependencies.sh"
    docker info >/dev/null 2>&1 || die "Docker não está acessível. Execute 'newgrp docker' ou faça login novamente."
    install_node_dependencies
    install_python_dependencies
    echo "[OK] Ambiente pronto. Copie .env.example para .env para personalizar a execução."
}

main "$@"