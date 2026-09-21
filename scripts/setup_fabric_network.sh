#!/usr/bin/env bash
set -o errexit   # Aborta a execução se um comando falhar
set -o nounset   # Aborta a execução se uma variável não definida for usada
set -o pipefail  # Aborta se algum comando em um pipeline falhar
# set -x         # Modo de depuração (descomente se precisar debugar)

# Pega o diretório onde o script está rodando (pasta scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Define a raiz do projeto (um nível acima de scripts/)
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/config.sh"
export CONTAINER_CLI_COMPOSE="${CONTAINER_CLI_COMPOSE:-docker compose}"

NETWORK_DIR="${PROJECT_ROOT}/network"
CHAINCODE_DIR="${PROJECT_ROOT}/contracts/simple/go"
API_CONFIG_DIR="${PROJECT_ROOT}/middleware"
API_WALLET_DIR="${PROJECT_ROOT}/middleware/wallet"

function network_down(){
    [[ -f "${NETWORK_DIR}/test-network/network.sh" ]] || die "Fabric test-network não encontrada em ${NETWORK_DIR}"
    (cd "${NETWORK_DIR}/test-network" && bash network.sh down)
}

function network_creation(){
    local qtd_orderers=$1  # Recebe a quantidade de orderers passada pela main
    
    [[ -f "${NETWORK_DIR}/install-fabric.sh" ]] || die "network/install-fabric.sh não encontrado"
    bash "${NETWORK_DIR}/install-fabric.sh" docker binary --fabric-version "${FABRIC_VERSION}"
    cd "${NETWORK_DIR}/test-network"
    
    echo "Levantando a rede do Hyperledger Fabric..."
    bash network.sh up createChannel -c "${FABRIC_CHANNEL}" -s couchdb -o "$qtd_orderers"
    
    echo "Subindo chaincode..."
    # O caminho do chaincode agora vem da variável corrigida CHAINCODE_DIR
    bash network.sh deployCC -ccn "${FABRIC_CHAINCODE}" -ccp "$CHAINCODE_DIR" -ccl go -c "${FABRIC_CHANNEL}"
}

function configure_middleware(){
    echo "Configurando credenciais do Middleware..."
    
    # Caminho do connection profile gerado pelo test-network
    local CCP_SRC="${NETWORK_DIR}/test-network/organizations/peerOrganizations/org1.example.com/connection-org1.json"
    
    if [ -f "$CCP_SRC" ]; then
        # Garante que a pasta config existe
        mkdir -p "$API_CONFIG_DIR"
        
        # Copia o perfil de conexão para dentro do middleware
        cp "$CCP_SRC" "$API_CONFIG_DIR/connection-profile.json"
        
        # Limpa carteira antiga para evitar conflitos
        rm -rf "$API_WALLET_DIR"
        
        echo "✅ Connection Profile atualizado em: $API_CONFIG_DIR"
    else
        echo "❌ ERRO: connection-org1.json não encontrado. A rede subiu?"
    fi

    echo "Registrando Admin na API..."
    if [ -f "${PROJECT_ROOT}/middleware/scripts/enrollAdmin.js" ]; then
        pushd "${PROJECT_ROOT}/middleware" > /dev/null
        # Instala dependências da API caso não estejam instaladas
        npm ci
        node scripts/enrollAdmin.js
        popd > /dev/null
    else
        echo "Aviso: Script enrollAdmin.js não encontrado."
    fi

}

main() {
    if [[ "${1:-}" == "--down" ]]; then
        network_down
        return
    fi

    local orderers=${1:-${ORDERERS}}

    bash "${SCRIPT_DIR}/bootstrap.sh"
    require_command go
    if [[ -f "${NETWORK_DIR}/test-network/network.sh" ]]; then
        network_down || true
    fi
    network_creation "$orderers"
    
    # Chama a configuração da API após a rede subir
    configure_middleware
}

main "$@"