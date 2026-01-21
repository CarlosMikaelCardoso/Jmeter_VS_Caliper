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
    # No contexto do Wrapper, NUM_REPETITIONS é o ID da Rodada atual
    local ROUND_ID="${NUM_REPETITIONS}"
    
    echo "--- [Data Gen] Gerando CSVs para Rodada Global ${ROUND_ID} ---"

    # Define cargas (Mantendo sua lógica original)
    local BASE_LOOPS=100
    if [ "$NUM_USERS" -eq 5 ]; then BASE_LOOPS=200; fi
    if [ "$NUM_USERS" -eq 10 ]; then BASE_LOOPS=100; fi
    if [ "$NUM_USERS" -eq 20 ]; then BASE_LOOPS=50; fi

    # Exporta variáveis para o JMeter
    export OPEN_LOOPS=$BASE_LOOPS
    export TRANSFER_LOOPS=$((BASE_LOOPS / 2))
    if [ "$TRANSFER_LOOPS" -lt 1 ]; then export TRANSFER_LOOPS=1; fi
    export CURRENT_LOOPS=$OPEN_LOOPS 

    # Limpa arquivos antigos na pasta de resultados
    rm -f "${RESULTS_DIR}"/open_accounts*.csv "${RESULTS_DIR}"/transfer_accounts*.csv

    echo "   -> Gerando arquivos individuais por Thread (${NUM_USERS} threads)..."

    # Loop para gerar um arquivo separado para CADA thread (Worker)
    for (( thread=1; thread<=NUM_USERS; thread++ ))
    do
        local OPEN_THREAD_FILE="${RESULTS_DIR}/open_accounts_thread_${thread}.csv"
        local TRANSFER_THREAD_FILE="${RESULTS_DIR}/transfer_accounts_thread_${thread}.csv"
        
        # Prefixo base para esta thread nesta rodada: r1_user1_
        local THREAD_PREFIX="r${ROUND_ID}_user${thread}_"

        # 1. Gera contas para esta thread (1 até 200)
        # Formato: r1_user1_1, r1_user1_2 ...
        awk -v prefix="$THREAD_PREFIX" -v loops="$OPEN_LOOPS" 'BEGIN {
            for(i=1; i<=loops; i++) {
                print prefix i ",1000000000000000"
            }
        }' > "${OPEN_THREAD_FILE}"

        # 2. Gera transferências para esta thread (1 até 100)
        # O destino e a origem são escolhidos APENAS dentro das contas desta thread
        # Isso elimina 100% dos conflitos MVCC entre threads diferentes.
        awk -v prefix="$THREAD_PREFIX" -v acc_limit="$OPEN_LOOPS" -v tx_loops="$TRANSFER_LOOPS" 'BEGIN {
            srand();
            for(i=1; i<=tx_loops; i++) {
                src = int(1 + rand() * acc_limit);
                dst = int(1 + rand() * acc_limit);
                
                # Garante que não transfere para si mesmo
                while(src == dst) {
                    dst = int(1 + rand() * acc_limit);
                }
                print prefix src "," prefix dst ",10"
            }
        }' > "${TRANSFER_THREAD_FILE}"
    done
    
    # Gera um arquivo unificado apenas para registro (opcional, o JMeter vai usar os _thread_X.csv)
    cat "${RESULTS_DIR}"/open_accounts_thread_*.csv > "${RESULTS_DIR}/open_accounts.csv"
    cat "${RESULTS_DIR}"/transfer_accounts_thread_*.csv > "${RESULTS_DIR}/transfer_accounts.csv"

    echo "✅ Dados gerados: ${NUM_USERS} arquivos separados. Exemplo: r${ROUND_ID}_user1_1"
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
# cleanup
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