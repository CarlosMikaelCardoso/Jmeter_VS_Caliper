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
JMETER_DIR="${PROJECT_ROOT}/apache-jmeter-${JMETER_VERSION}" 
JMETER_BIN="${JMETER_DIR}/bin/jmeter"
JMETER_URL="https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz"

# Configurações do Java
JAVA_DIR_NAME="jdk-21.0.7"
JAVA_TAR_GZ="jdk-21.0.7_linux-x64_bin.tar.gz"
JAVA_URL="https://download.oracle.com/java/21/archive/${JAVA_TAR_GZ}"
export JAVA_HOME="${PROJECT_ROOT}/${JAVA_DIR_NAME}"

# Configuração API
API_HOST=$(hostname -I | awk '{print $1}')
API_PORT="3000"
MONITOR_PORT="3002"

# Parâmetros de entrada
NUM_USERS=${1:-5}
NUM_REPETITIONS=${2:-1}

# --- FUNÇÕES DE SETUP ---

cleanup() {
    echo "--- Limpando resultados antigos em ${RESULTS_DIR} ---"
    if [ -d "${RESULTS_DIR}" ]; then
        rm -rf "${RESULTS_DIR:?}"/*
    else
        mkdir -p "${RESULTS_DIR}"
    fi
}

check_and_install_java() {
    echo "--- Verificando instalação do Java ---"
    if [ ! -d "$JAVA_HOME" ] || [ ! -f "${JAVA_HOME}/bin/java" ]; then
        echo "Baixando e instalando JDK na raiz do projeto..."
        pushd "${PROJECT_ROOT}" > /dev/null
        wget -q --show-progress -O "${JAVA_TAR_GZ}" "${JAVA_URL}"
        tar -xzf "${JAVA_TAR_GZ}" && rm "${JAVA_TAR_GZ}"
        popd > /dev/null
    fi
    export PATH="${JAVA_HOME}/bin:$PATH"
    java -version 2>&1 | head -n 2
}

# --- VALIDAÇÃO E SETUP GERAL ---
mkdir -p "${RESULTS_DIR}"

if [ ! -f "$JMETER_BIN" ]; then
    echo "Baixando JMeter..."
    pushd "${PROJECT_ROOT}" > /dev/null
    wget -q --show-progress "$JMETER_URL"
    tar -xzf "apache-jmeter-${JMETER_VERSION}.tgz" && rm "apache-jmeter-${JMETER_VERSION}.tgz"
    popd > /dev/null
fi

check_and_install_java

JMX_OPEN="${BENCHMARK_DIR}/test_round1_open.jmx"
JMX_QUERY="${BENCHMARK_DIR}/test_round2_query.jmx"
JMX_TRANSFER="${BENCHMARK_DIR}/test_round3_transfer.jmx"

# --- CÁLCULO DE LOOPS E GERAÇÃO DE DADOS ---
generate_accounts_csv() {
    echo "Gerando massa de dados (CSVs) SEM CONFLITOS MVCC..."
    
    # Define loops para Open/Query e reduz para Transfer
    if [ "$NUM_USERS" -eq 5 ]; then
        OPEN_LOOPS=200;
    elif [ "$NUM_USERS" -eq 10 ]; then
        OPEN_LOOPS=100;
    elif [ "$NUM_USERS" -eq 25 ]; then
        OPEN_LOOPS=40;
    elif [ "$NUM_USERS" -eq 50 ]; then
        OPEN_LOOPS=20;
    else
        OPEN_LOOPS=200;
    fi
    
    # Transfer Loops define quantas transações. 
    # Para evitar MVCC, precisamos de contas suficientes.
    TRANSFER_LOOPS=$((OPEN_LOOPS / 10))
    if [ "$TRANSFER_LOOPS" -lt 1 ]; then TRANSFER_LOOPS=1; fi

    echo "Configuração: Users=$NUM_USERS | Open/Query Loops=$OPEN_LOOPS | Transfer Loops=$TRANSFER_LOOPS"
    
    # Total de contas criadas
    local NUMBER_OF_ACCOUNTS=$((NUM_USERS * OPEN_LOOPS))
    
    local accounts_file="${RESULTS_DIR}/all_accounts.txt"
    local open_csv="${RESULTS_DIR}/open_accounts.csv"
    local transfer_csv="${RESULTS_DIR}/transfer_accounts.csv"

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

        // 1. Gera contas para Open e Query (Distribuído por thread)
        for (let t = 1; t <= numUsers; t++) {
            const threadAccs = [];
            for (let i = 0; i < accountsPerThread; i++) {
                const acc = 'userJmeter' + get26Num(accIndex++);
                threadAccs.push(acc);
                totalAccounts.push(acc);
            }
            fs.writeFileSync('open_accounts_thread_' + t + '.csv', 'accountId\n' + threadAccs.join('\n'));
        }
        
        // CSV Global
        fs.writeFileSync('${open_csv}', 'accountId\n' + totalAccounts.join('\n'));
        fs.writeFileSync('${accounts_file}', totalAccounts.join('\n'));
        
        // 2. GERAÇÃO DE TRANSFERÊNCIAS (ESTRATÉGIA SEM COLISÃO)
        // Divide as contas em duas metades: Remetentes (primeira metade) e Destinatários (segunda metade)
        // Isso garante que uma conta nunca seja remetente e destinatária ao mesmo tempo
        
        const midPoint = Math.floor(totalAccounts.length / 2);
        const senders = totalAccounts.slice(0, midPoint);
        const receivers = totalAccounts.slice(midPoint, totalAccounts.length);
        
        const transferPairs = [];
        
        // Pareia Sender[i] com Receiver[i].
        // Como a lista é sequencial e única, nunca haverá colisão de chaves (MVCC)
        // desde que o número de transferências não exceda o número de pares únicos disponíveis.
        
        const maxUniquePairs = Math.min(senders.length, receivers.length);
        const requestedTransfers = ${NUM_USERS} * 200; // Gera excedente para garantir
        
        let pairIndex = 0;
        for(let i=0; i < requestedTransfers; i++) {
            // Se acabar os pares únicos, volta ao início (aí sim pode ter MVCC se o loop for muito rápido,
            // mas com a carga reduzida do Transfer, isso é improvável)
            if (pairIndex >= maxUniquePairs) pairIndex = 0;
            
            const src = senders[pairIndex];
            const tgt = receivers[pairIndex];
            
            transferPairs.push(src + ',' + tgt);
            pairIndex++;
        }
        
        fs.writeFileSync('${transfer_csv}', 'source_account,target_account\n' + transferPairs.join('\n'));
        console.log('Gerados ' + transferPairs.length + ' pares de transferência (Estratégia Split-Set).');
    "
    popd > /dev/null
}

# --- EXECUÇÃO ---
run_test_and_monitor() {
    local JMX_FILE=$1
    local ROUND_NAME=$2
    local RUN_NUMBER=$3
    local CSV_FILE_PATH=$4
    local CURRENT_LOOPS=$5  # NOVO ARGUMENTO: Quantidade de loops específica desta rodada

    local JTL_FILE="${RESULTS_DIR}/results_${ROUND_NAME,,}_run_${RUN_NUMBER}.jtl"
    local DOCKER_LOG="${RESULTS_DIR}/docker_stats_${ROUND_NAME,,}_run_${RUN_NUMBER}.log"

    echo "--- Executando: ${ROUND_NAME} (Run ${RUN_NUMBER}) [Loops: ${CURRENT_LOOPS}] ---"

    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": \"${RUN_NUMBER}\"}" \
        "http://${API_HOST}:${MONITOR_PORT}/monitor/start"

    # Passa loopCount dinamicamente
    "${JMETER_BIN}" -n -t "$JMX_FILE" -l "$JTL_FILE" \
        -JcsvDataFile="${CSV_FILE_PATH}" \
        -JapiHost="$API_HOST" \
        -JnumUsers="$NUM_USERS" \
        -JloopCount="$CURRENT_LOOPS" 

    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": \"${RUN_NUMBER}\"}" \
        "http://${API_HOST}:${MONITOR_PORT}/monitor/stop"

    curl -s -o "$DOCKER_LOG" "http://${API_HOST}:${MONITOR_PORT}/monitor/logs/${ROUND_NAME}/${RUN_NUMBER}"
}

# --- MAIN ---
echo "--- Preparando Teste JMeter ---"
cleanup
generate_accounts_csv # Define as variáveis OPEN_LOOPS e TRANSFER_LOOPS

# Limpa erros da API
curl -s -X POST "http://${API_HOST}:${API_PORT}/errors/clear" > /dev/null

for (( i=1; i<=$NUM_REPETITIONS; i++ ))
do
    echo "--- Repetição $i de $NUM_REPETITIONS ---"
    
    # Open e Query usam carga total (OPEN_LOOPS)
    run_test_and_monitor "$JMX_OPEN" "Open" "$i" "${RESULTS_DIR}/open_accounts.csv" "$OPEN_LOOPS"
    
    run_test_and_monitor "$JMX_QUERY" "Query" "$i" "${RESULTS_DIR}/open_accounts_thread_" "$OPEN_LOOPS"
    
    # Transfer usa carga reduzida (TRANSFER_LOOPS)
    run_test_and_monitor "$JMX_TRANSFER" "Transfer" "$i" "${RESULTS_DIR}/transfer_accounts.csv" "$TRANSFER_LOOPS"
done

echo "--- Gerando Gráficos ---"
if [ -f "$GENERATE_GRAPHS_SCRIPT" ]; then
    python3 "$GENERATE_GRAPHS_SCRIPT" "${RESULTS_DIR}"
else
    echo "Aviso: Script de gráficos não encontrado."
fi

echo "Concluído. Resultados em: ${RESULTS_DIR}"