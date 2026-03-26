#!/usr/bin/env bash
set -o errexit   # Aborta a execução se um comando falhar
set -o nounset   # Aborta a execução se uma variável não definida for usada
set -o pipefail  # Aborta se algum comando em um pipeline falhar
# set -x         # Modo de depuração (descomente se precisar debugar)

# Pega o diretório onde o script está rodando (pasta scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Define a raiz do projeto (um nível acima de scripts/)
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Caminhos atualizados conforme sua imagem
NETWORK_DIR="${PROJECT_ROOT}/network"
CHAINCODE_DIR="${PROJECT_ROOT}/contracts/simple/go"
API_CONFIG_DIR="${PROJECT_ROOT}/middleware"
API_WALLET_DIR="${PROJECT_ROOT}/middleware/wallet"

function install_dependencies(){
    # Instalação de dependências básicas
    sudo apt-get update
    sudo apt-get install -y git curl python3-pip jq golang-go ca-certificates gnupg lsb-release

    sudo snap install docker 
    echo "Iniciando Docker (Snap)..."
    sudo snap start docker || true
    
    echo "Aguardando Docker daemon estar pronto..."
    local timeout=30
    local counter=0
    while ! docker info >/dev/null 2>&1; do
        if [ $counter -ge $timeout ]; then
            echo "ERRO CRÍTICO: Timeout aguardando Docker iniciar."
            exit 1
        fi
        echo "Aguardando Docker... ($counter/$timeout s)"
        sleep 1
        ((counter++))
    done
    echo "Docker está rodando!"

    # Adiciona o usuário ao grupo docker se necessário (Segurança)
    if ! groups "$USER" | grep -q '\bdocker\b'; then
        echo "Adicionando usuário $USER ao grupo docker..."
        sudo useradd docker || true
        sudo usermod -aG docker "$USER"
        echo "AVISO: Talvez seja necessário fazer logoff/login para aplicar as permissões de grupo."
    fi

    # Mostra versões
    docker --version || true
    docker compose version || true
    
    # Instala Node.js 20
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs build-essential
    # Instala pacotes Python
    sudo apt-get install -y python3-pip
    pip3 install pandas matplotlib seaborn tabulate beautifulsoup4 numpy
}

function network_down(){
    if [ -d "$NETWORK_DIR/test-network" ]; then
        cd "$NETWORK_DIR/test-network" || exit
        ./network.sh down
    else
        echo "Aviso: Pasta test-network não encontrada em $NETWORK_DIR"
    fi
}

function network_creation(){
    local qtd_orderers=$1  # Recebe a quantidade de orderers passada pela main
    
    cd "$NETWORK_DIR" || exit
    # Se o install-fabric.sh estiver dentro de network/
    if [ -f "./install-fabric.sh" ]; then
        ./install-fabric.sh docker binary --fabric-version '2.5.9'
    fi
    
    cd ./test-network || exit
    
    echo "Levantando a rede do Hyperledger Fabric..."
    ./network.sh up createChannel -c gercom -s couchdb -o "$qtd_orderers"
    
    echo "Subindo chaincode..."
    # O caminho do chaincode agora vem da variável corrigida CHAINCODE_DIR
    ./network.sh deployCC -ccn simple -ccp "$CHAINCODE_DIR" -ccl go -c gercom
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
        if [ ! -d "node_modules" ]; then npm install; fi
        node scripts/enrollAdmin.js
        popd > /dev/null
    else
        echo "Aviso: Script enrollAdmin.js não encontrado."
    fi

}

function cleanup(){
    echo "Limpando arquivos e contêineres de uma execução anterior..."
    if [ -d "fabric-samples" ]; then
        if [ -d "fabric-samples/test-network" ]; then
            (cd fabric-samples/test-network && ./network.sh down) || echo "Falha ao derrubar a rede ou já estava parada."
        else
            echo "Diretório 'fabric-samples/test-network' não encontrado, pulando 'network.sh down'."
        fi
        sudo rm -rf fabric-samples install-fabric.sh
        echo "Limpeza concluída."
    else
        echo "Pasta 'fabric-samples' não encontrada. Nada para limpar."
    fi
}

main() {
    local orderers=${1:-5}

    install_dependencies
    cleanup
    network_down
    network_creation "$orderers"
    
    # Chama a configuração da API após a rede subir
    configure_middleware
}

main "$@"