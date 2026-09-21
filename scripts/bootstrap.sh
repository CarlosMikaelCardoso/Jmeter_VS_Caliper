#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/config.sh"

install_system_dependencies() {
    local missing=()
    local command
    for command in curl git go jq python3 wget; do
        command -v "${command}" >/dev/null 2>&1 || missing+=("${command}")
    done

    if ! command -v sar >/dev/null 2>&1; then
        missing+=("sysstat")
    fi
    if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
        missing+=("nodejs" "npm")
    fi
    if ! command -v docker >/dev/null 2>&1; then
        missing+=("docker.io")
    fi

    if ((${#missing[@]} == 0)); then
        return
    fi

    command -v sudo >/dev/null 2>&1 || die "sudo é necessário para instalar dependências do sistema"
    echo "[INFO] Instalando dependências do sistema: ${missing[*]}"
    sudo apt-get update
    local packages=(ca-certificates curl git jq python3-venv wget sysstat nodejs npm docker.io)
    if ! command -v go >/dev/null 2>&1; then
        packages+=(golang-go)
    fi
    sudo apt-get install -y "${packages[@]}"
}

configure_docker() {
    docker info >/dev/null 2>&1 || sudo systemctl start docker
    docker info >/dev/null 2>&1 || die "Docker não está acessível. Verifique o daemon e as permissões do usuário."
    docker compose version >/dev/null 2>&1 || die "Docker Compose não está disponível. Instale o plugin 'docker compose'."
    if ! groups "${USER}" | grep -qw docker; then
        echo "[WARN] Usuário fora do grupo docker; use 'newgrp docker' ou faça login novamente."
    fi
}

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
    install_system_dependencies
    configure_docker
    install_node_dependencies
    install_python_dependencies
    echo "[OK] Ambiente pronto. Copie .env.example para .env para personalizar a execução."
}

main "$@"