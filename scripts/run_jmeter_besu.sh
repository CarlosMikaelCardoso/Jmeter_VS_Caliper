#!/bin/bash
# --- Script de execução do JMeter para Besu ---
# Baseado no run_jmeter_api.sh (Fabric), adaptado para os endpoints
# assíncronos da API Besu (/open-async, /transfer-async, /query/:id)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/config.sh"

# Caminhos Base
BENCHMARK_DIR="${JMETER_DIR}"
BASE_RESULTS_DIR="${RESULTS_DIR}/jmeter_runs"
GENERATE_GRAPHS_SCRIPT="${SCRIPT_DIR}/generateGraphs.py"

# Configuração JMeter
JMETER_HOME="${PROJECT_ROOT}/apache-jmeter-${JMETER_VERSION}"
JMETER_BIN="${JMETER_HOME}/bin/jmeter"
JMETER_URL="https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz"

# Java Config
JAVA_DIR_NAME="jdk-${JAVA_VERSION}"
JAVA_TAR_GZ="jdk-${JAVA_VERSION}_linux-x64_bin.tar.gz"
JAVA_URL="https://download.oracle.com/java/21/archive/${JAVA_TAR_GZ}"
export JAVA_HOME="${PROJECT_ROOT}/${JAVA_DIR_NAME}"

# API Besu Config
BESU_HOST="${API_HOST}"
BESU_PORT="${BESU_API_PORT}"

# Recebe argumentos
LOG_OUTPUT="${1:-api.log}"
NUM_USERS=${2:-5}
ROUND_ID=${3:-1}

ROUND_DIR="${BASE_RESULTS_DIR}/round_${ROUND_ID}"
mkdir -p "${ROUND_DIR}"

echo "[INFO] Configurando saída para: ${ROUND_DIR}"

# --- SETUP ---
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

# --- INICIAR API BESU ---
echo "Iniciando API Besu..."
echo "Logs serão salvos em: $LOG_OUTPUT"

cd "${PROJECT_ROOT}/api-besu"
nohup env \
    BESU_RPC_URL="${BESU_RPC_URL}" \
    BESU_DEPLOYER_PRIVATE_KEY="${BESU_DEPLOYER_PRIVATE_KEY}" \
    BESU_CONTRACT_ADDRESS="${BESU_CONTRACT_ADDRESS}" \
    BESU_API_PORT="${BESU_PORT}" \
    node api_single_node.js > "$LOG_OUTPUT" 2>&1 &

API_PID=$!
echo "API Besu iniciada com PID: $API_PID"
echo "$API_PID" > "${PROJECT_ROOT}/api_pid.txt"

# Aguarda a API ficar acessível
for _ in {1..30}; do
    curl -fsS "http://${BESU_HOST}:${BESU_PORT}/health" >/dev/null 2>&1 && break
    sleep 1
done
curl -fsS "http://${BESU_HOST}:${BESU_PORT}/health" >/dev/null 2>&1 || {
    echo "[ERRO] API Besu não respondeu na porta ${BESU_PORT}"
    exit 1
}
echo "[OK] API Besu respondendo em http://${BESU_HOST}:${BESU_PORT}"

# --- JMX ---
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

    for (( thread=1; thread<=NUM_USERS; thread++ ))
    do
        local OPEN_THREAD_FILE="${ROUND_DIR}/open_accounts_thread_${thread}.csv"
        local TRANSFER_THREAD_FILE="${ROUND_DIR}/transfer_accounts_thread_${thread}.csv"
        local THREAD_PREFIX="r${ROUND_ID}_user${thread}_"

        awk -v prefix="$THREAD_PREFIX" -v loops="$OPEN_LOOPS" 'BEGIN {
            for(i=1; i<=loops; i++) { print prefix i ",10000" }
        }' > "${OPEN_THREAD_FILE}"

        awk -v prefix="$THREAD_PREFIX" -v acc_limit="$OPEN_LOOPS" -v tx_loops="$TRANSFER_LOOPS" 'BEGIN {
            srand();
            for(i=1; i<=tx_loops; i++) {
                src = int(1 + rand() * acc_limit);
                dst = int(1 + rand() * acc_limit);
                while(src == dst) { dst = int(1 + rand() * acc_limit); }
                print prefix src "," prefix dst ",100"
            }
        }' > "${TRANSFER_THREAD_FILE}"
    done

    cat "${ROUND_DIR}"/open_accounts_thread_*.csv > "${ROUND_DIR}/open_accounts.csv"
}

# --- AGUARDAR FILA ASYNC ---
wait_for_queue() {
    echo "[INFO] Aguardando a fila da API Besu esvaziar..."
    local max_wait=300  # 5 minutos max
    local waited=0
    while [ $waited -lt $max_wait ]; do
        local status
        status=$(curl -s "http://${BESU_HOST}:${BESU_PORT}/queue/status" 2>/dev/null)
        local is_idle
        is_idle=$(echo "$status" | grep -o '"isIdle":true' || true)
        if [ -n "$is_idle" ]; then
            echo "[OK] Fila vazia."
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    echo "[WARN] Timeout aguardando fila esvaziar."
}

# --- EXECUÇÃO ---
run_test_and_monitor() {
    local JMX_FILE=$1
    local ROUND_NAME=$2
    local RUN_NUMBER=$3
    local CSV_FILE_PATH=$4
    local CURRENT_LOOPS=$5

    local JTL_FILE="${ROUND_DIR}/results_${ROUND_NAME,,}.jtl"
    local DOCKER_LOG="${ROUND_DIR}/docker_stats_${ROUND_NAME,,}.json"

    echo "[RUN] Executando: ${ROUND_NAME} (Rodada $RUN_NUMBER)"

    # Inicia monitoramento via API Besu
    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": \"${RUN_NUMBER}\"}" \
        "http://${BESU_HOST}:${BESU_PORT}/monitor/start" > /dev/null 2>&1 || true

    "$JMETER_BIN" -n -t "$JMX_FILE" -l "$JTL_FILE" \
        -JcsvDataFile="${CSV_FILE_PATH}" \
        -JapiHost="$BESU_HOST" \
        -JapiPort="$BESU_PORT" \
        -JnumUsers="$NUM_USERS" \
        -JloopCount="$CURRENT_LOOPS"

    # Aguarda fila async esvaziar (open e transfer são async)
    if [ "$ROUND_NAME" != "Query" ]; then
        wait_for_queue
    fi

    # Para monitoramento
    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": \"${RUN_NUMBER}\"}" \
        "http://${BESU_HOST}:${BESU_PORT}/monitor/stop" > /dev/null 2>&1 || true

    curl -s -o "$DOCKER_LOG" "http://${BESU_HOST}:${BESU_PORT}/monitor/logs/${ROUND_NAME}/${RUN_NUMBER}" 2>/dev/null || true
}

# --- MAIN ---
echo "[RUN] Preparando Rodada $ROUND_ID (JMeter - Besu)"
generate_accounts_csv
curl -s -X POST "http://${BESU_HOST}:${BESU_PORT}/errors/clear" > /dev/null 2>&1 || true

# 1. OPEN
run_test_and_monitor "$JMX_OPEN" "Open" "$ROUND_ID" "${ROUND_DIR}/open_accounts.csv" "$OPEN_LOOPS"

# 2. QUERY
run_test_and_monitor "$JMX_QUERY" "Query" "$ROUND_ID" "${ROUND_DIR}/open_accounts_thread_" "$OPEN_LOOPS"

# 3. TRANSFER
run_test_and_monitor "$JMX_TRANSFER" "Transfer" "$ROUND_ID" "${ROUND_DIR}/transfer_accounts_thread_" "$TRANSFER_LOOPS"

echo "[INFO] Rodada $ROUND_ID concluída. Resultados em: ${ROUND_DIR}"
