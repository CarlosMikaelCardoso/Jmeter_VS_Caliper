#!/bin/bash

# --- DEFINIÇÃO DE CAMINHOS RELATIVOS ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Caminhos da Nova Estrutura
BENCHMARK_DIR="${PROJECT_ROOT}/benchmarks/jmeter_fabric"
RESULTS_DIR="${PROJECT_ROOT}/results/jmeter_runs"
GENERATE_GRAPHS_SCRIPT="${SCRIPT_DIR}/generateGraphs.py"
MIDDLEWARE_DIR="${PROJECT_ROOT}/middleware"

# Configuração JMeter
JMETER_VERSION="5.6.3"
JMETER_DIR="${PROJECT_ROOT}/apache-jmeter-${JMETER_VERSION}" # Instala na raiz do projeto
JMETER_BIN="${JMETER_DIR}/bin/jmeter"
JMETER_URL="https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz"

# Configurações do Java (Instalação Local)
JAVA_DIR_NAME="jdk-21.0.7"
JAVA_TAR_GZ="jdk-21.0.7_linux-x64_bin.tar.gz"
JAVA_URL="https://download.oracle.com/java/21/archive/${JAVA_TAR_GZ}"
# Define JAVA_HOME apontando para a pasta na raiz do projeto
export JAVA_HOME="${PROJECT_ROOT}/${JAVA_DIR_NAME}"

# Configuração API
API_HOST=$(hostname -I | awk '{print $1}')
API_PORT="3000"
MONITOR_PORT="3002"

# Parâmetros de entrada
NUM_USERS=${1:-5}
NUM_REPETITIONS=${2:-1}

# --- FUNÇÕES DE SETUP ---

check_and_install_java() {
    echo "--- Verificando instalação do Java ---"
    
    # Verifica se o Java já existe na pasta local do projeto
    if [ ! -d "$JAVA_HOME" ] || [ ! -f "${JAVA_HOME}/bin/java" ]; then
        echo "Java local não encontrado em: ${JAVA_HOME}"
        echo "Baixando e instalando JDK ${JAVA_DIR_NAME} na raiz do projeto..."
        
        # Muda para a raiz para baixar e extrair
        pushd "${PROJECT_ROOT}" > /dev/null
        
        if ! command -v wget &> /dev/null; then 
            echo "Erro: 'wget' não está instalado. Por favor, instale-o."
            exit 1
        fi
        
        wget -q --show-progress -O "${JAVA_TAR_GZ}" "${JAVA_URL}"
        
        if [ $? -ne 0 ]; then 
            echo "Erro: Falha ao baixar o Java. Verifique sua conexão."
            exit 1
        fi
        
        tar -xzf "${JAVA_TAR_GZ}"
        rm "${JAVA_TAR_GZ}"
        
        echo "Java ${JAVA_DIR_NAME} instalado com sucesso."
        popd > /dev/null
    else
        echo "Java local já instalado em ${JAVA_HOME}"
    fi
    
    # Configura o PATH para usar ESTE java prioritariamente
    export PATH="${JAVA_HOME}/bin:$PATH"
    
    # Confirmação visual da versão
    echo "Versão do Java em uso:"
    java -version 2>&1 | head -n 2
}

# --- VALIDAÇÃO E SETUP GERAL ---

# Cria diretório de resultados
mkdir -p "${RESULTS_DIR}"

# Instalação do JMeter (se não existir na raiz)
if [ ! -f "$JMETER_BIN" ]; then
    echo "Baixando JMeter para a raiz do projeto..."
    pushd "${PROJECT_ROOT}" > /dev/null
    if ! command -v wget &> /dev/null; then echo "Erro: 'wget' necessário."; exit 1; fi
    wget -q --show-progress "$JMETER_URL"
    tar -xzf "apache-jmeter-${JMETER_VERSION}.tgz"
    rm "apache-jmeter-${JMETER_VERSION}.tgz"
    popd > /dev/null
fi

# Chama a função de verificação/instalação do Java
check_and_install_java

# Caminhos dos Planos de Teste
JMX_OPEN="${BENCHMARK_DIR}/test_round1_open.jmx"
JMX_QUERY="${BENCHMARK_DIR}/test_round2_query.jmx"
JMX_TRANSFER="${BENCHMARK_DIR}/test_round3_transfer.jmx"

# --- GERAÇÃO DE DADOS (CSV) ---
generate_accounts_csv() {
    echo "Gerando massa de dados (CSVs)..."
    
    # Lógica de loops baseada no número de usuários (mantida do original)
    if [ "$NUM_USERS" -eq 5 ]; then
        OPEN_LOOPS=200;
    elif [ "$NUM_USERS" -eq 10 ]; then
        OPEN_LOOPS=100;
    elif [ "$NUM_USERS" -eq 25 ]; then
        OPEN_LOOPS=40;
    elif [ "$NUM_USERS" -eq 50 ]; then
        OPEN_LOOPS=20;
    else
        OPEN_LOOPS=200; # Default fallback
    fi
    
    local NUMBER_OF_ACCOUNTS=$((NUM_USERS * OPEN_LOOPS))
    
    local accounts_file="${RESULTS_DIR}/all_accounts.txt"
    local open_csv="${RESULTS_DIR}/open_accounts.csv"
    local transfer_csv="${RESULTS_DIR}/transfer_accounts.csv"

    # Usa node para gerar os dados. Executa na pasta results para salvar lá.
    pushd "${RESULTS_DIR}" > /dev/null
    
    node -e "
        const fs = require('fs');
        const DICTIONARY = 'abcdefghijklmnopqrstuvwxyz';
        function get26Num(n) { let result = ''; while(n >= 0) { result = DICTIONARY.charAt(n % DICTIONARY.length) + result; n = Math.floor(n / DICTIONARY.length) - 1; } return result; }
        
        const numAccounts = ${NUMBER_OF_ACCOUNTS};
        const numUsers = ${NUM_USERS};
        const accountsPerThread = Math.floor(numAccounts / numUsers);
        
        let totalAccounts = [];
        let accIndex = 0;

        // Gera CSVs individuais por thread (para Query)
        for (let t = 1; t <= numUsers; t++) {
            const threadAccs = [];
            for (let i = 0; i < accountsPerThread; i++) {
                const acc = 'userJmeter' + get26Num(accIndex++);
                threadAccs.push(acc);
                totalAccounts.push(acc);
            }
            fs.writeFileSync('open_accounts_thread_' + t + '.csv', 'accountId\n' + threadAccs.join('\n'));
        }
        
        // Gera CSV global para Open e Transfer
        fs.writeFileSync('${open_csv}', 'accountId\n' + totalAccounts.join('\n'));
        fs.writeFileSync('${accounts_file}', totalAccounts.join('\n'));
        
        // Gera CSV de Transferência
        const transferPairs = [];
        const totalTransfers = ${NUM_USERS} * 10; 
        for(let i=0; i<totalTransfers; i++) {
            const src = totalAccounts[Math.floor(Math.random() * totalAccounts.length)];
            let tgt = totalAccounts[Math.floor(Math.random() * totalAccounts.length)];
            while(src === tgt) tgt = totalAccounts[Math.floor(Math.random() * totalAccounts.length)];
            transferPairs.push(src + ',' + tgt);
        }
        fs.writeFileSync('${transfer_csv}', 'source_account,target_account\n' + transferPairs.join('\n'));
    "
    popd > /dev/null
}

# --- EXECUÇÃO ---
run_test_and_monitor() {
    local JMX_FILE=$1
    local ROUND_NAME=$2
    local RUN_NUMBER=$3
    local CSV_FILE_PATH=$4 # Caminho completo do CSV

    local JTL_FILE="${RESULTS_DIR}/results_${ROUND_NAME,,}_run_${RUN_NUMBER}.jtl"
    local DOCKER_LOG="${RESULTS_DIR}/docker_stats_${ROUND_NAME,,}_run_${RUN_NUMBER}.log"

    echo "--- Executando: ${ROUND_NAME} (Run ${RUN_NUMBER}) ---"

    # Inicia Monitoramento
    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": \"${RUN_NUMBER}\"}" \
        "http://${API_HOST}:${MONITOR_PORT}/monitor/start"

    # Executa JMeter
    # Passa csvDataFile apontando para RESULTS_DIR onde os CSVs foram gerados
    "${JMETER_BIN}" -n -t "$JMX_FILE" -l "$JTL_FILE" \
        -JcsvDataFile="${CSV_FILE_PATH}" \
        -JapiHost="$API_HOST"

    # Para Monitoramento
    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": \"${RUN_NUMBER}\"}" \
        "http://${API_HOST}:${MONITOR_PORT}/monitor/stop"

    # Baixa Log
    curl -s -o "$DOCKER_LOG" "http://${API_HOST}:${MONITOR_PORT}/monitor/logs/${ROUND_NAME}/${RUN_NUMBER}"
}

# --- MAIN ---
echo "--- Preparando Teste JMeter ---"
generate_accounts_csv

# Limpa erros da API
curl -s -X POST "http://${API_HOST}:${API_PORT}/errors/clear" > /dev/null

for (( i=1; i<=$NUM_REPETITIONS; i++ ))
do
    echo "--- Repetição $i de $NUM_REPETITIONS ---"
    
    # Atenção aos caminhos dos CSVs gerados na função generate_accounts_csv
    run_test_and_monitor "$JMX_OPEN" "Open" "$i" "${RESULTS_DIR}/open_accounts.csv"
    
    # Para Query, o JMeter usa o prefixo e adiciona o número da thread. 
    # Passamos o prefixo do arquivo gerado em RESULTS_DIR
    run_test_and_monitor "$JMX_QUERY" "Query" "$i" "${RESULTS_DIR}/open_accounts_thread_"
    
    run_test_and_monitor "$JMX_TRANSFER" "Transfer" "$i" "${RESULTS_DIR}/transfer_accounts.csv"
done

echo "--- Gerando Gráficos ---"
if [ -f "$GENERATE_GRAPHS_SCRIPT" ]; then
    python3 "$GENERATE_GRAPHS_SCRIPT" "${RESULTS_DIR}"
else
    echo "Aviso: Script de gráficos não encontrado em $GENERATE_GRAPHS_SCRIPT"
fi

echo "Concluído. Resultados em: ${RESULTS_DIR}"