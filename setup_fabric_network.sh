#!/usr/bin/env bash
set -o errexit   # Aborta a execução se um comando falhar
set -o nounset   # Aborta a execução se uma variável não definida for usada
set -o pipefail  # Aborta se algum comando em um pipeline falhar
set -x           # Modo de depuração: imprime cada comando antes de executá-lo

function install_dependencies(){
    # Instalação do git e curl
    sudo apt-get update
    sudo apt-get install git curl -y
    # Instalação do docker e docker-compose
    sudo apt-get install git curl docker-compose -y
    sudo systemctl start docker
    sudo usermod -a -G docker $USER
    docker --version
    docker-compose --version
    sudo systemctl enable docker
    # Instalação do GO e JQ
    sudo apt-get install golang-go jq -y
}

function network_creation(){
    # Script para instalar o Hyperledger Fabric
    curl -sSLO https://raw.githubusercontent.com/hyperledger/fabric/main/scripts/install-fabric.sh && \
    chmod +x install-fabric.sh && \
    ./install-fabric.sh docker samples binary --fabric-version 2.4.9 
    cd fabric-samples/test-network || exit
    git checkout v2.4.9
    # Levantar a rede do Hyperledger Fabric
    ./network.sh up createChannel -c gercom -s couchdb
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
    network_creation
}

# Executa a função principal
main "$@"
