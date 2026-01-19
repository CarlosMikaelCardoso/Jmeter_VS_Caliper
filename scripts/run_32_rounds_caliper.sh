#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Configurações
TOTAL_ROUNDS=32
WORKERS=5 
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="${PROJECT_ROOT}/results/caliper_runs"
CLIENT_MONITOR_DIR="${PROJECT_ROOT}/results/client_monitor"

# Garante diretórios
mkdir -p "${RESULTS_DIR}"
mkdir -p "${CLIENT_MONITOR_DIR}"

echo ">>> INICIANDO BATERIA DE $TOTAL_ROUNDS RODADAS <<<"

for (( i=1; i<=TOTAL_ROUNDS; i++ ))
do
    echo ""
    echo "=================================================================="
    echo "   RODADA $i de $TOTAL_ROUNDS"
    echo "=================================================================="

    # ______________________________________________________________________
    # MODIFICADO: Removido o cleanLedger.js. 
    # A unicidade dos dados é garantida pelo prefixo da rodada no simple-state.js
    # ______________________________________________________________________

    # 1. MONITORAMENTO DE HARDWARE (CLIENTE)
    echo ">>> [Passo 1] Iniciando monitoramento de CPU do Cliente..."
    CLIENT_LOG="${CLIENT_MONITOR_DIR}/client_cpu_round_${i}.log"
    # Coleta em background a cada 1s
    sar -u 1 > "${CLIENT_LOG}" &
    MONITOR_PID=$!

    # 2. EXECUÇÃO DO TESTE
    echo ">>> [Passo 2] Executando Caliper..."
    cd "${SCRIPT_DIR}"
    
    # Executa o script de teste passando WORKERS e o ID da RODADA
    ./run_caliper.sh $WORKERS $i

    # 3. PARAR MONITORAMENTO
    kill $MONITOR_PID || true
    echo ">>> Monitoramento do Cliente salvo em: ${CLIENT_LOG}"

    # 4. VALIDAÇÃO (SANITY CHECK - CLIENTE)
    # Verifica se o 'idle' caiu abaixo de 10% (Uso > 90%)
    LOW_IDLE=$(grep -v "Average" "${CLIENT_LOG}" | awk '{if($NF < 10.00) print $0}' | wc -l)
    
    if [ "$LOW_IDLE" -gt 0 ]; then
        echo "⚠️  AVISO: A CPU do Cliente ultrapassou 90% de uso em ${LOW_IDLE} momentos nesta rodada!"
        echo "   Verifique o arquivo ${CLIENT_LOG}"
    else
        echo "✅ CPU do Cliente OK (<90%)."
    fi

    # 5. ORGANIZAÇÃO DE ARTEFATOS
    # Renomeia os relatórios HTML para evitar sobrescrita
    mv "${RESULTS_DIR}/report-open.html" "${RESULTS_DIR}/report_open_round_${i}.html" || true
    mv "${RESULTS_DIR}/report-query.html" "${RESULTS_DIR}/report_query_round_${i}.html" || true
    mv "${RESULTS_DIR}/report-transfer.html" "${RESULTS_DIR}/report_transfer_round_${i}.html" || true

    echo "✅ Rodada $i concluída."
    sleep 5 # Pausa para resfriamento/estabilização
done

echo ">>> BATERIA DE TESTES FINALIZADA <<<"