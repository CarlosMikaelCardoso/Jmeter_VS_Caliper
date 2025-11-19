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

    # Adiciona o usuário ao grupo docker se necessário e informa para re-login
    if ! groups "$USER" | grep -q '\bdocker\b'; then
        sudo usermod -aG docker "$USER"
        echo "Usuário adicionado ao grupo 'docker'. Faça logout/login ou rode: newgrp docker"
    fi

    # Verifica conectividade com o daemon e avisa em caso de erro
    if ! docker info >/dev/null 2>&1; then
        echo "Aviso: não foi possível conectar ao daemon Docker;"
        echo " - Caso use o Docker Engine: execute 'sudo systemctl start docker' e verifique 'sudo systemctl status docker'."
        echo " - Caso use Docker Desktop: execute 'systemctl --user start docker-desktop' e verifique 'systemctl --user status docker-desktop'."
        echo "Se o problema for permissões, verifique se seu usuário está no grupo 'docker' (logout/login necessário)."
    fi

    # Mostra versões (não falhar se os comandos não existirem)
    docker --version || true
    docker compose version || true

    # Instala pacotes Python no diretório do usuário para evitar necessidade de sudo
    pip3 install --user pandas matplotlib || true
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
    network_creation
}

# Executa a função principal
main "$@"
