#!/bin/bash

# Configurações
TOTAL_ROUNDS=32
WORKERS=5 
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Caminhos
RESULTS_DIR="${PROJECT_ROOT}/results/caliper_runs"
HOST_MONITOR_DIR="${RESULTS_DIR}/host_monitor"
SETUP_NETWORK_SCRIPT="${SCRIPT_DIR}/setup_fabric_network.sh" 
GENERATE_GRAPHS_SCRIPT="${SCRIPT_DIR}/generateGraphsCaliper.py"

# Garante diretórios iniciais
mkdir -p "${RESULTS_DIR}"
mkdir -p "${HOST_MONITOR_DIR}"

echo ">>> INICIANDO BATERIA DE $TOTAL_ROUNDS RODADAS (Caliper) <<<"

for (( i=1; i<=TOTAL_ROUNDS; i++ ))
do
    echo ""
    echo "=================================================================="
    echo "   RODADA $i de $TOTAL_ROUNDS"
    echo "=================================================================="

    # (Reinicialização da rede desativada conforme solicitado)
    # if [ -f "$SETUP_NETWORK_SCRIPT" ]; then ... fi

    # 1. MONITORAMENTO DE HARDWARE (Host)
    HOST_LOG="${HOST_MONITOR_DIR}/host_cpu_round_${i}.log"
    echo ">>> [Passo 1] Iniciando monitoramento..."
    sar -u 1 > "$HOST_LOG" &
    MONITOR_PID=$!

    # 2. EXECUTAR CALIPER
    # O script run_caliper.sh vai verificar dependências e pular instalação se já existirem
    ./run_caliper.sh $WORKERS $i

    # 3. FINALIZAR MONITORAMENTO
    kill $MONITOR_PID
    echo ">>> [Passo 3] Monitoramento parado."

    # --- ORGANIZAÇÃO DE PASTAS ---
    echo ">>> [Passo 4] Organizando arquivos da rodada $i..."
    
    # Define e cria a pasta da rodada
    ROUND_FOLDER="${RESULTS_DIR}/round_${i}"
    mkdir -p "${ROUND_FOLDER}"

    # Move os relatórios HTML
    mv "${RESULTS_DIR}"/report-*.html "${ROUND_FOLDER}/" 2>/dev/null || true
    
    # Move os logs de execução e stats do Docker
    mv "${RESULTS_DIR}"/*.log "${ROUND_FOLDER}/" 2>/dev/null || true
    mv "${RESULTS_DIR}"/*.json "${ROUND_FOLDER}/" 2>/dev/null || true

    # (Opcional) Move o log de CPU do host para ficar junto
    if [ -f "$HOST_LOG" ]; then
        mv "$HOST_LOG" "${ROUND_FOLDER}/"
    fi

    echo "✅ Arquivos movidos para: ${ROUND_FOLDER}"

    # --- GERAÇÃO DE GRÁFICOS DA RODADA (NOVIDADE) ---
    echo ">>> [Passo 5] Gerando gráficos exclusivos desta rodada..."
    if [ -f "$GENERATE_GRAPHS_SCRIPT" ]; then
        # Passamos APENAS a pasta desta rodada para o script Python
        python3 "$GENERATE_GRAPHS_SCRIPT" "${ROUND_FOLDER}"
        echo "📊 Gráficos gerados em: ${ROUND_FOLDER}/graphs"
    fi

    sleep 2
done

echo ">>> BATERIA CALIPER CONCLUÍDA <<<"
echo "Para gerar o comparativo final, execute: ./generate_final_report.sh"