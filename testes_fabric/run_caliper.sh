#!/usr/bin/env bash
set -o errexit   # Aborta a execução se um comando falhar
set -o nounset   # Aborta a execução se uma variável não definida for usada
set -o pipefail  # Aborta se algum comando em um pipeline falhar
set -x           # Modo de depuração: imprime cada comando antes de executá-lo

DIRETORIO_CHAINCODE="../../testes_fabric/caliper-benchmarks/src/fabric/scenario/simple/go"

function cleanup(){
    echo "Limpando arquivos e diretórios de uma execução anterior..."
    sudo rm -rf caliper-benchmarks 
    echo "Limpeza concluída."
}

function install_dependencies_caliper(){
    sudo apt-get update
    sudo apt-get install -y git npm
}

function caliper_setup(){
    # git clone https://github.com/hyperledger/caliper-benchmarks
    # cd caliper-benchmarks || exit
    # npm install --only=prod @hyperledger/caliper-cli > /dev/null 2>&1
    # npx caliper bind --caliper-bind-sut fabric:2.4 > /dev/null 2>&1

    echo instalando a chaincode
    cd .. || exit
    echo "Diretório atual: $(pwd)"
    cd fabric-samples/test-network || exit
    ./network.sh deployCC -ccn simple -ccp "$DIRETORIO_CHAINCODE" -ccl go -c gercom
    cd ../../testes_fabric/caliper-benchmarks || exit
    echo iniciando o caliper
    npx caliper launch manager --caliper-workspace ./ \
    --caliper-networkconfig networks/fabric/test-network.yaml \
    --caliper-benchconfig benchmarks/scenario/simple/config.yaml \
    --caliper-flow-only-test --caliper-fabric-gateway-enabled
}

main() {
    # cleanup
    install_dependencies_caliper
    caliper_setup
}

main "$@"