#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

MIN_NODE_MAJOR=20
DOCKER_MAJOR=28
CHECK_ONLY=false

usage() {
    cat <<'EOF'
Uso: scripts/install_dependencies.sh [--check]

Instala as dependencias do sistema para executar Fabric/Besu, JMeter e Caliper.
Usa Docker 28.x para compatibilidade com o builder do Fabric 2.5.14.
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
    local docker_major=0
    local docker_version=""
    local cli_version=""
    local distro_id
    local distro_codename
    local candidate_codename
    local docker_repo_url

    if command -v docker >/dev/null 2>&1; then
        docker_major="$(docker version --format '{{.Client.Version}}' 2>/dev/null | cut -d. -f1 || true)"
        [[ -n "${docker_major}" ]] || docker_major=0
    fi

    if ((docker_major != DOCKER_MAJOR)) || ! docker compose version >/dev/null 2>&1; then
        echo "[INFO] Instalando Docker Engine ${DOCKER_MAJOR}.x e Docker Compose v2"
        distro_id="$(. /etc/os-release && echo "${ID}")"
        distro_codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")"
        case "${distro_id}" in
            ubuntu) docker_repo_url="https://download.docker.com/linux/ubuntu" ;;
            debian) docker_repo_url="https://download.docker.com/linux/debian" ;;
            *)
                echo "[ERRO] Distribuição não suportada pelo instalador Docker APT: ${distro_id}" >&2
                echo "[AÇÃO] Instale Docker ${DOCKER_MAJOR}.x manualmente e execute: bash scripts/install_dependencies.sh --check" >&2
                return 1
                ;;
        esac

        # Remove pacotes antigos/conflitantes do Ubuntu (docker.io, containerd canonical, runc)
        echo "[INFO] Removendo pacotes Docker/Containerd conflitantes do repositório da distribuição..."
        sudo apt-get remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc || true

        # Configura chave GPG oficial do Docker
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL "${docker_repo_url}/gpg" -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        if command -v gpg >/dev/null 2>&1; then
            sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg < /etc/apt/keyrings/docker.asc 2>/dev/null || true
            sudo chmod a+r /etc/apt/keyrings/docker.gpg 2>/dev/null || true
        fi

        # Para distros LTS conhecidas, usa o codename exato.
        # Fallback para noble/jammy apenas se for uma versão desconhecida/mais nova.
        local candidate_codenames=("${distro_codename}")
        case "${distro_codename}" in
            jammy|noble|focal|bookworm|bullseye)
                ;;
            *)
                candidate_codenames+=("noble" "jammy")
                ;;
        esac

        for candidate_codename in "${candidate_codenames[@]}"; do
            [[ -n "${candidate_codename}" ]] || continue
            printf '%s\n' \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] ${docker_repo_url} ${candidate_codename} stable" | \
                sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
            sudo apt-get update || true
            docker_version="$(apt-cache madison docker-ce 2>/dev/null | awk -v major=":${DOCKER_MAJOR}." '$3 ~ major && !found {found=$3} END {if (found) print found}')"
            [[ -n "${docker_version}" ]] && break
        done

        [[ -n "${docker_version}" ]] || {
            echo "[ERRO] Docker ${DOCKER_MAJOR}.x não está disponível no repositório configurado." >&2
            echo "[AÇÃO] Verifique as versões com: apt-cache madison docker-ce" >&2
            echo "[AÇÃO] Em Ubuntu 26.04 ou versões experimentais, use uma VM Ubuntu 22.04 (jammy) ou 24.04 (noble)." >&2
            return 1
        }

        cli_version="$(apt-cache madison docker-ce-cli 2>/dev/null | awk -v major=":${DOCKER_MAJOR}." '$3 ~ major && !found {found=$3} END {if (found) print found}')"
        [[ -n "${cli_version}" ]] || cli_version="${docker_version}"

        echo "[INFO] Instalando pacotes Docker 28: docker-ce=${docker_version} docker-ce-cli=${cli_version}"
        sudo apt-mark unhold docker-ce docker-ce-cli containerd.io 2>/dev/null || true
        sudo apt-get install -y --allow-downgrades \
            "docker-ce=${docker_version}" \
            "docker-ce-cli=${cli_version}" \
            containerd.io docker-buildx-plugin docker-compose-plugin
        sudo apt-mark hold docker-ce docker-ce-cli 2>/dev/null || true
    fi
}

configure_docker() {
    sudo systemctl daemon-reload 2>/dev/null || true
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

    sudo usermod -aG docker "${USER}" || true

    if ! docker info >/dev/null 2>&1; then
        echo "[WARN] Docker foi instalado e o serviço está ativo." >&2
        echo "[WARN] O usuário '${USER}' foi adicionado ao grupo 'docker', mas as permissões ainda não estão ativas nesta sessão de terminal." >&2
        echo "[AÇÃO] Execute no terminal: newgrp docker (ou faça logout e login novamente na VM)." >&2
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

    if command -v docker >/dev/null 2>&1; then
        local docker_major
        docker_major="$(docker version --format '{{.Client.Version}}' 2>/dev/null | cut -d. -f1 || true)"
        if [[ -z "${docker_major}" ]] && command -v sudo >/dev/null 2>&1; then
            docker_major="$(sudo docker version --format '{{.Server.Version}}' 2>/dev/null | cut -d. -f1 || true)"
        fi
        if [[ "${docker_major}" != "${DOCKER_MAJOR}" ]]; then
            echo "[ERRO] Docker ${docker_major:-desconhecido}.x encontrado; esperado: Docker ${DOCKER_MAJOR}.x"
            failed=1
        fi
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
