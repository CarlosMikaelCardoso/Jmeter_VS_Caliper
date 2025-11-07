#!/usr/bin/env bash
set -o errexit   # Aborta a execução se um comando falhar
set -o nounset   # Aborta a execução se uma variável não definida for usada
set -o pipefail  # Aborta se algum comando em um pipeline falhar
set -x           # Modo de depuração: imprime cada comando antes de executá-lo

DIRETORIO_BECHMARKS="${HOME}/Jmeter_VS_Caliper/testes_fabric"

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
    # Verifica se o caliper-cli já está instalado (via npx sem install ou em node_modules)
    # Função auxiliar: tenta um comando (com silencioso), faz uma segunda tentativa se falhar,
    # mas não permite que o script aborta por causa de 'set -o errexit'
    attempt_cmd() {
        local cmd="$*"
        local rc=0
        set +o errexit
        eval "$cmd"
        rc=$?
        if [ $rc -ne 0 ]; then
            echo "Aviso: comando falhou (rc=$rc). Tentando novamente..."
            sleep 2
            eval "$cmd"
            rc=$?
        fi
        set -o errexit
        return $rc
    }

    if npx --no-install caliper --version > /dev/null 2>&1 || [ -d node_modules/@hyperledger/caliper-cli ]; then
        echo "Caliper CLI já instalado. Pulando instalação."
    else
        echo "Instalando @hyperledger/caliper-cli..."
        attempt_cmd "npm install --only=prod @hyperledger/caliper-cli > /dev/null 2>&1" \
            || echo "Falha ao instalar @hyperledger/caliper-cli — prosseguindo (pode causar erros posteriores)."
    fi

    # Verifica se o binding para Fabric já foi feito (várias possibilidades de nomes de pacote)
    if npm ls --depth=0 @hyperledger/caliper-sut-fabric > /dev/null 2>&1 \
       || npm ls --depth=0 @hyperledger/caliper-fabric > /dev/null 2>&1 \
       || [ -d node_modules/@hyperledger/caliper-sut-fabric ] \
       || [ -d node_modules/@hyperledger/caliper-fabric ]; then
        echo "Caliper Fabric binding já presente. Pulando bind."
    else
        echo "Executando 'caliper bind' para fabric:2.4..."
        attempt_cmd "npx caliper bind --caliper-bind-sut fabric:2.4 > /dev/null 2>&1" \
            || echo "Falha ao executar 'caliper bind' — prosseguindo (pode causar erros posteriores)."
    fi

    cd "${DIRETORIO_BECHMARKS}" || exit
    echo Iniciando o caliper...
    npx caliper launch manager --caliper-workspace ./ \
    --caliper-networkconfig fabric/test-network.yaml \
    --caliper-benchconfig simple/config.yaml \
    --caliper-fabric-gateway-enabled
}

main() {
    cleanup
    install_dependencies_caliper
    caliper_setup
}

main "$@"