#!/bin/bash

# Configurações
TOTAL_ROUNDS=32
WORKERS=5 
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Caminhos
RESULTS_DIR="${PROJECT_ROOT}/results/caliper_runs"
HOST_MONITOR_DIR="${RESULTS_DIR}/host_monitor"
GENERATE_GRAPHS_SCRIPT="${SCRIPT_DIR}/generateGraphsCaliper.py"

mkdir -p "${RESULTS_DIR}"
mkdir -p "${HOST_MONITOR_DIR}"

echo "[INFO] INICIANDO BATERIA DE $TOTAL_ROUNDS RODADAS (Caliper)"
start_time=$(date +%s%3N) # Monitora o tempo de execução da bateria de testes.

for (( i=1; i<=TOTAL_ROUNDS; i++ ))
do
    echo "=================================================================="
    echo "   RODADA $i de $TOTAL_ROUNDS"
    echo "=================================================================="

    HOST_LOG="${HOST_MONITOR_DIR}/host_cpu_round_${i}.log"
    sar -u 1 > "$HOST_LOG" &
    MONITOR_PID=$!

    ./run_caliper.sh $WORKERS $i

    kill $MONITOR_PID

    # --- ORGANIZAÇÃO DE PASTAS (CORRIGIDO) ---
    ROUND_FOLDER="${RESULTS_DIR}/round_${i}"
    mkdir -p "${ROUND_FOLDER}"

    mv "${RESULTS_DIR}"/report-*.html "${ROUND_FOLDER}/" 2>/dev/null || true
    
    # [CORREÇÃO] Move tanto .log quanto .txt
    mv "${RESULTS_DIR}"/*.log "${ROUND_FOLDER}/" 2>/dev/null || true
    mv "${RESULTS_DIR}"/*.txt "${ROUND_FOLDER}/" 2>/dev/null || true
    mv "${RESULTS_DIR}"/*.json "${ROUND_FOLDER}/" 2>/dev/null || true

    if [ -f "$HOST_LOG" ]; then
        mv "$HOST_LOG" "${ROUND_FOLDER}/"
    fi

    # Gera gráficos da rodada individual
    if [ -f "$GENERATE_GRAPHS_SCRIPT" ]; then
        python3 "$GENERATE_GRAPHS_SCRIPT" "${ROUND_FOLDER}"
    fi

    sleep 2
done

end_time=$(date +%s%3N)

duracao=$((end_time - start_time))
minutos=$(awk "BEGIN {print $duracao/60000}")
echo "[INFO] BATERIA CALIPER CONCLUÍDA EM $minutos" MINUTOS
