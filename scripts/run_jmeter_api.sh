#!/bin/bash

# --- DEFINIÇÃO DE CAMINHOS RELATIVOS ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Caminhos Base
BENCHMARK_DIR="${PROJECT_ROOT}/benchmarks/jmeter_fabric"
BASE_RESULTS_DIR="${PROJECT_ROOT}/results/jmeter_runs" # Diretório raiz dos resultados
GENERATE_GRAPHS_SCRIPT="${SCRIPT_DIR}/generateGraphs.py"

# Configuração JMeter
JMETER_VERSION="5.6.3"
JMETER_DIR="${PROJECT_ROOT}/apache-jmeter-${JMETER_VERSION}" 
JMETER_BIN="${JMETER_DIR}/bin/jmeter"
JMETER_URL="https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz"

# Java Config
JAVA_DIR_NAME="jdk-21.0.7"
JAVA_TAR_GZ="jdk-21.0.7_linux-x64_bin.tar.gz"
JAVA_URL="https://download.oracle.com/java/21/archive/${JAVA_TAR_GZ}"
export JAVA_HOME="${PROJECT_ROOT}/${JAVA_DIR_NAME}"

# API Config
API_HOST=$(hostname -I | awk '{print $1}')
API_PORT="3000"
MONITOR_PORT="3002"
# Recebe o caminho do log como 1º argumento. Se não passar, usa 'api.log' no local atual.
LOG_OUTPUT="${1:-api.log}"

echo "Iniciando API Middleware..."
echo "Logs serão salvos em: $LOG_OUTPUT"

# Navega até o diretório do middleware e inicia o node
# O '2>&1' redireciona erros também para o log
# O '&' roda em background para não travar o terminal
cd ../middleware
npm install > /dev/null 2>&1 # Instala dependências silenciosamente
nohup node api.js > "$LOG_OUTPUT" 2>&1 &

API_PID=$!
echo "API iniciada com PID: $API_PID"

# Salva o PID para poder matar o processo depois (no script de 32 rodadas)
echo $API_PID > ../api_pid.txt
sleep 5

# Parâmetros
NUM_USERS=${2:-5}
ROUND_ID=${3:-1}

# --- CONFIGURAÇÃO DE DIRETÓRIO POR RODADA ---
# Aqui criamos a pasta específica desta rodada
ROUND_DIR="${BASE_RESULTS_DIR}/round_${ROUND_ID}"
mkdir -p "${ROUND_DIR}"

echo "[INFO] Configurando saída para: ${ROUND_DIR}"

# --- FUNÇÕES DE SETUP ---

check_and_install_java() {
    if [ ! -d "$JAVA_HOME" ] || [ ! -f "${JAVA_HOME}/bin/java" ]; then
        echo "--- Instalando Java ---"
        pushd "${PROJECT_ROOT}" > /dev/null
        wget -q --show-progress -O "${JAVA_TAR_GZ}" "${JAVA_URL}"
        tar -xzf "${JAVA_TAR_GZ}" && rm "${JAVA_TAR_GZ}"
        popd > /dev/null
    fi
    export PATH="${JAVA_HOME}/bin:$PATH"
}

if [ ! -f "$JMETER_BIN" ]; then
    echo "--- Baixando JMeter ---"
    pushd "${PROJECT_ROOT}" > /dev/null
    wget -q --show-progress "$JMETER_URL"
    tar -xzf "apache-jmeter-${JMETER_VERSION}.tgz" && rm "apache-jmeter-${JMETER_VERSION}.tgz"
    popd > /dev/null
fi

check_and_install_java


# --- CAMINHOS DOS JMX (JMETER) ---
JMX_OPEN="${BENCHMARK_DIR}/test_round1_open.jmx"
JMX_QUERY="${BENCHMARK_DIR}/test_round2_query.jmx"
JMX_TRANSFER="${BENCHMARK_DIR}/test_round3_transfer.jmx"

# --- GERAÇÃO DE DADOS ---
generate_accounts_csv() {
    echo "[INFO] - [Data Gen] Gerando CSVs na pasta: round_${ROUND_ID}"

    local BASE_LOOPS=100
    if [ "$NUM_USERS" -eq 5 ]; then BASE_LOOPS=200; fi
    if [ "$NUM_USERS" -eq 10 ]; then BASE_LOOPS=100; fi
    if [ "$NUM_USERS" -eq 20 ]; then BASE_LOOPS=50; fi
    if [ "$NUM_USERS" -eq 25 ]; then BASE_LOOPS=40; fi
    if [ "$NUM_USERS" -eq 50 ]; then BASE_LOOPS=20; fi
    
    export OPEN_LOOPS=$BASE_LOOPS
    export TRANSFER_LOOPS=$((BASE_LOOPS / 2))
    if [ "$TRANSFER_LOOPS" -lt 1 ]; then export TRANSFER_LOOPS=1; fi
    export CURRENT_LOOPS=$OPEN_LOOPS 

    # Gera arquivos dentro do diretório da rodada (ROUND_DIR)
    for (( thread=1; thread<=NUM_USERS; thread++ ))
    do
        local OPEN_THREAD_FILE="${ROUND_DIR}/open_accounts_thread_${thread}.csv"
        local TRANSFER_THREAD_FILE="${ROUND_DIR}/transfer_accounts_thread_${thread}.csv"
        local THREAD_PREFIX="r${ROUND_ID}_user${thread}_"

        awk -v prefix="$THREAD_PREFIX" -v loops="$OPEN_LOOPS" 'BEGIN {
            for(i=1; i<=loops; i++) { print prefix i ",1000000000000000" }
        }' > "${OPEN_THREAD_FILE}"

        awk -v prefix="$THREAD_PREFIX" -v acc_limit="$OPEN_LOOPS" -v tx_loops="$TRANSFER_LOOPS" 'BEGIN {
            srand();
            for(i=1; i<=tx_loops; i++) {
                src = int(1 + rand() * acc_limit);
                dst = int(1 + rand() * acc_limit);
                while(src == dst) { dst = int(1 + rand() * acc_limit); }
                print prefix src "," prefix dst ",10"
            }
        }' > "${TRANSFER_THREAD_FILE}"
    done
    
    # Consolida para OPEN (caso necessário) dentro da pasta da rodada
    cat "${ROUND_DIR}"/open_accounts_thread_*.csv > "${ROUND_DIR}/open_accounts.csv"
}

# --- EXECUÇÃO ---
run_test_and_monitor() {
    local JMX_FILE=$1
    local ROUND_NAME=$2
    local RUN_NUMBER=$3
    local CSV_FILE_PATH=$4
    local CURRENT_LOOPS=$5

    # Salva JTL e Logs na pasta da rodada
    local JTL_FILE="${ROUND_DIR}/results_${ROUND_NAME,,}.jtl"
    local DOCKER_LOG="${ROUND_DIR}/docker_stats_${ROUND_NAME,,}.json"

    echo "[RUN] Executando: ${ROUND_NAME} (Rodada $RUN_NUMBER)"

    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": \"${RUN_NUMBER}\"}" \
        "http://${API_HOST}:${MONITOR_PORT}/monitor/start" > /dev/null

    "$JMETER_BIN" -n -t "$JMX_FILE" -l "$JTL_FILE" \
        -JcsvDataFile="${CSV_FILE_PATH}" \
        -JapiHost="$API_HOST" \
        -JnumUsers="$NUM_USERS" \
        -JloopCount="$CURRENT_LOOPS" 

    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": \"${RUN_NUMBER}\"}" \
        "http://${API_HOST}:${MONITOR_PORT}/monitor/stop" > /dev/null

    curl -s -o "$DOCKER_LOG" "http://${API_HOST}:${MONITOR_PORT}/monitor/logs/${ROUND_NAME}/${RUN_NUMBER}"
}

# --- MAIN ---
echo "[RUN] Preparando Rodada $ROUND_ID (JMeter)"
generate_accounts_csv
curl -s -X POST "http://${API_HOST}:${API_PORT}/errors/clear" > /dev/null

# 1. OPEN (Usa consolidado dentro da pasta round)
run_test_and_monitor "$JMX_OPEN" "Open" "$ROUND_ID" "${ROUND_DIR}/open_accounts.csv" "$OPEN_LOOPS"

# 2. QUERY (Usa prefixo da pasta round)
run_test_and_monitor "$JMX_QUERY" "Query" "$ROUND_ID" "${ROUND_DIR}/open_accounts_thread_" "$OPEN_LOOPS"

# 3. TRANSFER (Usa prefixo da pasta round)
run_test_and_monitor "$JMX_TRANSFER" "Transfer" "$ROUND_ID" "${ROUND_DIR}/transfer_accounts_thread_" "$TRANSFER_LOOPS"

echo "[INFO] Rodada $ROUND_ID concluída. Resultados em: ${ROUND_DIR}"
