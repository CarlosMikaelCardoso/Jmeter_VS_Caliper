#!/usr/bin/env bash
set -o errexit   # Aborta a execução se um comando falhar
set -o nounset   # Aborta a execução se uma variável não definida for usada
set -o pipefail  # Aborta se algum comando em um pipeline falhar
set -x           # Modo de depuração: imprime cada comando antes de executá-lo

DIRETORIO_REDE="${HOME}/Jmeter_VS_Caliper/testes_fabric/network_fabric"
DIRETORIO_CHAINCODE="${HOME}/Jmeter_VS_Caliper/testes_fabric/chaincode_simple/simple/go"

function install_dependencies(){
    # Instalação de dependências básicas
    sudo apt-get update
    sudo apt-get install -y git curl python3-pip jq golang-go ca-certificates gnupg lsb-release

    sudo snap install docker 
    
    # ---------------------------------------------------------
    # MODIFICAÇÃO: Correção específica para Docker via SNAP
    # Garante que o serviço iniciou e libera permissão no socket
    echo "Configurando permissões do Docker (Snap)..."
    sudo snap start docker || true
    sleep 5 # Aguarda o daemon subir completamente
    
    # Esta linha resolve o 'permission denied' forçando acesso de leitura/escrita
    if [ -e /var/run/docker.sock ]; then
        sudo chmod 666 /var/run/docker.sock
    else
        echo "Aviso: Socket /var/run/docker.sock não encontrado. O Docker pode não estar rodando."
    fi
    # ---------------------------------------------------------

    # Adiciona o usuário ao grupo docker se necessário
    if ! groups "$USER" | grep -q '\bdocker\b'; then
        sudo useradd docker 
        sudo usermod -aG docker "$USER"
    fi

    # Verifica conectividade com o daemon
    if ! docker info >/dev/null 2>&1; then
        echo "Aviso: Ainda não foi possível conectar ao daemon Docker."
        echo "Tentando forçar permissão novamente..."
        sudo chmod 666 /var/run/docker.sock
        
        if ! docker info >/dev/null 2>&1; then
            echo "ERRO CRÍTICO: Docker inacessível. Abortando."
            exit 1
        fi
    fi

    # Mostra versões
    docker --version || true
    docker compose version || true
    # Instala Node.js 20
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs build-essential
    # Instala pacotes Python
    pip3 install --user pandas matplotlib || true
}

function network_down(){
    cd "$DIRETORIO_REDE/test-network" || exit
    ./network.sh down
}

function network_creation(){
    # Script para instalar o Hyperledger Fabric
    # curl -sSLO https://raw.githubusercontent.com/hyperledger/fabric/main/scripts/install-fabric.sh && \
    # chmod +x install-fabric.sh && \
    cd "$DIRETORIO_REDE" || exit
    ./install-fabric.sh docker binary --fabric-version 2.4.9 
    cd ./test-network || exit
    # Levantar a rede do Hyperledger Fabric
    echo levantando a rede do Hyperledger Fabric
    ./network.sh up createChannel -c gercom -s couchdb -o 5
    echo Subindo chaincode na rede do Hyperledger Fabric
    ./network.sh deployCC -ccn simple -ccp "$DIRETORIO_CHAINCODE" -ccl go -c gercom
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
    cleanup
    install_dependencies
    network_down
    network_creation
}

# Executa a função principal
main "$@"
