#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/config.sh"

check_node_directory_ownership() {
    local directory
    local foreign_path
    local owner
    local group
    owner="$(id -un)"
    group="$(id -gn)"
    for directory in "${PROJECT_ROOT}/node_modules" "${MIDDLEWARE_DIR}/node_modules" "${PROJECT_ROOT}/api-besu/node_modules"; do
        [[ -d "${directory}" ]] || continue
        foreign_path="$(find "${directory}" -maxdepth 2 ! -user "${owner}" -print -quit)"
        if [[ -z "${foreign_path}" ]]; then
            continue
        fi

        echo "[ERRO] ${directory} contém arquivos de outro usuário, provavelmente root." >&2
        echo "[AÇÃO] Execute manualmente: sudo chown -R ${owner}:${group} '${directory}'" >&2
        echo "[AÇÃO] Depois execute novamente: npm run setup" >&2
        return 1
    done
}

install_node_dependencies() {
    local node_major
    node_major="$(node -p 'process.versions.node.split(".")[0]')"
    ((node_major >= 20)) || die "Node.js 20 ou superior é necessário; versão encontrada: ${node_major}"
    check_node_directory_ownership
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

check_python_environment() {
    [[ -x "${PYTHON_BIN}" ]] || die "Ambiente Python não encontrado. Execute primeiro: npm run setup"
    "${PYTHON_BIN}" -c "import bs4, jinja2, matplotlib, numpy, pandas, seaborn, tabulate" 2>/dev/null || \
        die "Dependências Python ausentes ou incompletas no venv. Execute: npm run setup"
}

main() {
    require_command node
    require_command npm
    require_command python3
    require_command go
    require_command docker
    docker compose version >/dev/null 2>&1 || die "Docker Compose v2 não encontrado. Execute primeiro: bash scripts/install_dependencies.sh"
    require_docker_access
    install_node_dependencies
    install_python_dependencies
    check_python_environment
    echo "[OK] Ambiente pronto. Copie .env.example para .env para personalizar a execução."
}

main "$@"