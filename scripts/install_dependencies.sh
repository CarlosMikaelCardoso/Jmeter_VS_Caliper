#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

MIN_NODE_MAJOR=20
CHECK_ONLY=false

usage() {
    cat <<'EOF'
Uso: scripts/install_dependencies.sh [--check]

Instala as dependencias do sistema para executar Fabric/Besu, JMeter e Caliper.
--check  apenas verifica as ferramentas, sem instalar nada.
EOF
}

for argument in "$@"; do
    case "${argument}" in
        --check) CHECK_ONLY=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Argumento desconhecido: ${argument}" >&2; usage >&2; exit 2 ;;
    esac
done

require_sudo() {
    command -v sudo >/dev/null 2>&1 || {
        echo "[ERRO] sudo é necessário para instalar dependências." >&2
        exit 1
    }
}

install_base_packages() {
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl git gnupg jq make \
        python3 python3-pip python3-venv wget sysstat netcat-openbsd golang-go
}

install_node() {
    local node_major=0
    if command -v node >/dev/null 2>&1; then
        node_major="$(node -p 'process.versions.node.split(".")[0]')"
    fi

    if ((node_major >= MIN_NODE_MAJOR)) && command -v npm >/dev/null 2>&1; then
        return
    fi

    echo "[INFO] Removendo pacotes Node antigos antes de instalar Node.js ${MIN_NODE_MAJOR}.x"
    # Ubuntu ships nodejs/libnode-dev separately; libnode-dev owns headers
    # that conflict with the NodeSource package.
    sudo dpkg --configure -a || true
    sudo apt-get remove -y libnode-dev nodejs npm || true
    sudo apt-get autoremove -y || true
    sudo apt-get -f install -y

    echo "[INFO] Instalando Node.js ${MIN_NODE_MAJOR}.x e npm"
    curl -fsSL "https://deb.nodesource.com/setup_${MIN_NODE_MAJOR}.x" | sudo -E bash -
    sudo apt-get install -y nodejs
}

install_docker() {
    if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
        echo "[INFO] Instalando Docker Engine e Docker Compose v2"
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
            sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        printf '%s\n' \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"${VERSION_CODENAME}\") stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
}

configure_docker() {
    if ! sudo systemctl enable --now docker; then
        echo "[ERRO] Docker não iniciou. Últimos eventos do docker.service:" >&2
        sudo journalctl -u docker.service -n 80 --no-pager >&2 || true
        echo "[ERRO] Últimos eventos do containerd.service:" >&2
        sudo journalctl -u containerd.service -n 40 --no-pager >&2 || true
        echo "[ERRO] Configuração atual do Docker:" >&2
        sudo test -f /etc/docker/daemon.json && sudo sed -n '1,160p' /etc/docker/daemon.json >&2 || \
            echo "(daemon.json ausente)" >&2
        return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        echo "[WARN] Docker foi instalado, mas este usuário ainda não tem acesso ao socket." >&2
        echo "[AÇÃO] Execute manualmente: sudo usermod -aG docker ${USER}" >&2
        echo "[AÇÃO] Depois execute: newgrp docker (ou faça logout/login)" >&2
        return 0
    fi

    if ! groups "${USER}" | grep -qw docker; then
        echo "[WARN] Docker está acessível nesta sessão, mas o grupo docker ainda não está associado ao usuário." >&2
        echo "[AÇÃO] Se necessário, execute manualmente: sudo usermod -aG docker ${USER}" >&2
    fi
}

check_tools() {
    local failed=0
    local command
    for command in curl git go jq python3 wget sar node npm docker; do
        if command -v "${command}" >/dev/null 2>&1; then
            printf '[OK] %-8s %s\n' "${command}" "$(command -v "${command}")"
        else
            printf '[ERRO] %-8s ausente\n' "${command}"
            failed=1
        fi
    done

    if docker compose version >/dev/null 2>&1; then
        echo "[OK] docker compose disponível"
    else
        echo "[ERRO] docker compose ausente"
        failed=1
    fi

    if command -v node >/dev/null 2>&1; then
        local node_major
        node_major="$(node -p 'process.versions.node.split(".")[0]')"
        if ((node_major < MIN_NODE_MAJOR)); then
            echo "[ERRO] Node.js ${node_major} encontrado; mínimo: ${MIN_NODE_MAJOR}"
            failed=1
        fi
    fi

    return "${failed}"
}

main() {
    if [[ "${CHECK_ONLY}" == true ]]; then
        check_tools
        return
    fi

    require_sudo
    install_base_packages
    install_node
    install_docker
    configure_docker
    check_tools
    echo "[OK] Dependências do sistema instaladas. Abra uma nova sessão para aplicar o grupo docker."
}

main "$@"
