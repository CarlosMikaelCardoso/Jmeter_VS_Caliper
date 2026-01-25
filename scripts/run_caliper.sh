#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# --- DEFINIÇÃO DE CAMINHOS ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

NETWORK_DIR="${PROJECT_ROOT}/network/test-network"
BENCHMARK_DIR="${PROJECT_ROOT}/benchmarks/caliper_fabric"
RESULTS_DIR="${PROJECT_ROOT}/results/caliper_runs"
GENERATE_GRAPHS_SCRIPT="${SCRIPT_DIR}/generateGraphsCaliper.py"
MONITOR_API_URL="http://localhost:3002"

mkdir -p "${RESULTS_DIR}"

# --- FUNÇÃO DE LIMPEZA ---
# (Desativada para permitir acumular relatórios de várias rodadas)
cleanup() {
    echo "[INFO] Limpando relatórios antigos em ${RESULTS_DIR}"
    rm -rf "${RESULTS_DIR}"
    mkdir -p "${RESULTS_DIR}"
}

# --- SETUP DO CALIPER ---
caliper_setup() {
    echo "[INFO] Verificando instalação do Caliper"
    cd "${PROJECT_ROOT}"
    
    # 1. Verifica se a CLI do Caliper já existe
    if ! npx --no-install caliper --version > /dev/null 2>&1; then
        echo "[INFO] Instalando @hyperledger/caliper-cli..."
        npm install --save-dev @hyperledger/caliper-cli
    else
        echo "[INFO] Caliper CLI já instalado."
    fi

    # 2. Verifica se o SDK do Fabric já está vinculado (Bind)
    # Verifica se a pasta do módulo existe para evitar 'npm install' desnecessário
    if [ ! -d "node_modules/@hyperledger/fabric-gateway" ]; then
        echo "[INFO] Realizando Bind do Caliper para Fabric 2.5..."
        npx caliper bind --caliper-bind-sut fabric:2.5
    else
        echo "[INFO] Bind do Fabric detectado (node_modules). Pulando instalação."
    fi
}


# --- CÁLCULO DE TRANSAÇÕES ---
calculate_tx_params() {
    local WORKERS=$1
    local LOOPS_PER_WORKER
    
    if [ "$WORKERS" -eq 5 ]; then
        LOOPS_PER_WORKER=200;
    elif [ "$WORKERS" -eq 10 ]; then
        LOOPS_PER_WORKER=100;
    elif [ "$WORKERS" -eq 25 ]; then
        LOOPS_PER_WORKER=40;
    elif [ "$WORKERS" -eq 50 ]; then
        LOOPS_PER_WORKER=20;
    else
        LOOPS_PER_WORKER=200;
    fi
    
    # Base Total (para Open e Query)
    TOTAL_TX=$((WORKERS * LOOPS_PER_WORKER))
    
    echo "[INFO] Configuração Base"
    echo "[INFO] Workers: ${WORKERS} | Base Total Tx: ${TOTAL_TX}"
}

# --- EXECUÇÃO DO TESTE ---
run_caliper_test() {
    local ROUND_NAME=$1
    local CONFIG_FILE="${BENCHMARK_DIR}/$2"
    local TEMP_CONFIG_FILE="${BENCHMARK_DIR}/temp-${2}"
    local RUN_NUMBER=$3
    local ROUND_LABEL_LOWER=$(echo "$ROUND_NAME" | tr '[:upper:]' '[:lower:]')
    local LOG_FILE="${RESULTS_DIR}/caliper_log_${ROUND_LABEL_LOWER}_run_${RUN_NUMBER}.txt"
    
    # Calcula carga base
    calculate_tx_params "${NUM_WORKERS}"
    
    # Escreve o ID da rodada em arquivo físico para o Node.js ler
    echo "${RUN_NUMBER}" > "${BENCHMARK_DIR}/current_round.txt"

    # Reduz carga se for Transfer
    local ACTUAL_TX=${TOTAL_TX}
    
    if [ "$ROUND_NAME" == "Transfer" ]; then
        ACTUAL_TX=$((TOTAL_TX / 2))
        # Garante que seja pelo menos 1
        if [ "$ACTUAL_TX" -lt 1 ]; then ACTUAL_TX=1; fi
        echo "[INFO] Modo TRANSFER detectado: Reduzindo carga para ${ACTUAL_TX} transações."
    fi

    echo "[RUN] [Run ${RUN_NUMBER}] Iniciando Benchmark: ${ROUND_NAME}"
    
    # Substitui Worker e TxNumber (considerando âncoras e normal)
    sed -e "s/number: [0-9]\+/number: ${NUM_WORKERS}/" \
        -e "s/numberOfAccounts: &number-of-accounts [0-9]\+/numberOfAccounts: \&number-of-accounts ${ACTUAL_TX}/" \
        -e "s/txNumber: [0-9]\+/txNumber: ${ACTUAL_TX}/" \
        "${CONFIG_FILE}" > "${TEMP_CONFIG_FILE}"
    
    # Inicia Monitoramento
    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": ${RUN_NUMBER}}" \
        "${MONITOR_API_URL}/monitor/start" || true

    cd "${PROJECT_ROOT}"
    
    echo "[RUN] Executando Caliper... Logs em: ${LOG_FILE}"
    npx caliper launch manager \
        --caliper-workspace "${PROJECT_ROOT}" \
        --caliper-networkconfig "${BENCHMARK_DIR}/network-config.yaml" \
        --caliper-benchconfig "${TEMP_CONFIG_FILE}" \
        --caliper-fabric-gateway-enabled \
        --caliper-report-path "${RESULTS_DIR}/report-${ROUND_LABEL_LOWER}.html" \
        > "${LOG_FILE}" 2>&1

    rm "${TEMP_CONFIG_FILE}"

    # Para Monitoramento
    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": ${RUN_NUMBER}}" \
        "${MONITOR_API_URL}/monitor/stop" || true
        
    curl -s -o "${RESULTS_DIR}/docker_stats_${ROUND_LABEL_LOWER}_run_${RUN_NUMBER}.log" \
        "${MONITOR_API_URL}/monitor/logs/${ROUND_NAME}/${RUN_NUMBER}" || true
}

main() {
    NUM_WORKERS=${1:-5}
    # O segundo argumento agora é o GLOBAL_RUN_ID vindo do orquestrador
    GLOBAL_RUN_ID=${2:-1}

    # cleanup <-- Comentado para preservar histórico
    caliper_setup

    # Passa o GLOBAL_RUN_ID para as funções de teste
    run_caliper_test "Open" "config-open.yaml" ${GLOBAL_RUN_ID}
    run_caliper_test "Query" "config-query.yaml" ${GLOBAL_RUN_ID}
    run_caliper_test "Transfer" "config-transfer.yaml" ${GLOBAL_RUN_ID}

    echo "[INFO] Gerando gráficos consolidados"
    if [ -f "$GENERATE_GRAPHS_SCRIPT" ]; then
        # Pode ajustar para rodar apenas no final de tudo se preferir
        python3 "$GENERATE_GRAPHS_SCRIPT" "${RESULTS_DIR}" 1 || true
    else
        echo "[ERRO] Script de gráficos não encontrado."
    fi
    
    echo "[INFO] Rodada ${GLOBAL_RUN_ID} Concluída! Resultados em: ${RESULTS_DIR}"
}

main "$@"
