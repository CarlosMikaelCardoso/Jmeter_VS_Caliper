#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Configurações
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/config.sh"

TOTAL_ROUNDS="${TOTAL_ROUNDS}"
WORKERS="${CALIPER_WORKERS}"

# Caminhos
RESULTS_DIR="${RESULTS_DIR}/caliper_runs"
HOST_MONITOR_DIR="${RESULTS_DIR}/host_monitor"
GENERATE_GRAPHS_SCRIPT="${SCRIPT_DIR}/generateGraphsCaliper.py"

mkdir -p "${RESULTS_DIR}"
mkdir -p "${HOST_MONITOR_DIR}"

MONITOR_PID=""
if ! curl -fsS "http://${MONITOR_HOST}:${MONITOR_PORT}/health" >/dev/null 2>&1; then
    echo "[INFO] Iniciando monitor Docker em segundo plano"
    (cd "${MIDDLEWARE_DIR}" && nohup node monitor-api.js > "${RESULTS_DIR}/monitor.log" 2>&1 & echo $! > "${RESULTS_DIR}/monitor.pid")
    for _ in {1..20}; do
        [[ -f "${RESULTS_DIR}/monitor.pid" ]] && break
        sleep 1
    done
    MONITOR_PID="$(cat "${RESULTS_DIR}/monitor.pid")"
fi
cleanup_monitor() {
    if [[ -n "${MONITOR_PID}" ]] && kill -0 "${MONITOR_PID}" 2>/dev/null; then
        kill "${MONITOR_PID}" 2>/dev/null || true
    fi
}
trap cleanup_monitor EXIT

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

    bash "${SCRIPT_DIR}/run_caliper.sh" "${WORKERS}" "${i}"

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
