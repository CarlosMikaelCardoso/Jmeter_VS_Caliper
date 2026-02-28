#!/bin/bash

# Configurações Gerais
TOTAL_ROUNDS=32
WORKERS=25 
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Caminhos
RESULTS_DIR="${PROJECT_ROOT}/results/jmeter_runs"
HOST_MONITOR_DIR="${RESULTS_DIR}/host_monitor"
SETUP_NETWORK_SCRIPT="${SCRIPT_DIR}/setup_fabric_network.sh"
GENERATE_GRAPHS_SCRIPT="${SCRIPT_DIR}/generateGraphs.py"

mkdir -p "${HOST_MONITOR_DIR}"

echo "[RUN] INICIANDO BATERIA DE $TOTAL_ROUNDS RODADAS (JMeter)"
echo "[INFO] Workers definidos: $WORKERS"
start_time=$(date +%s%3N) # Monitora o tempo de execução da bateria de testes.

for (( i=1; i<=TOTAL_ROUNDS; i++ ))
do
    echo ""
    echo "=================================================================="
    echo "   RODADA $i de $TOTAL_ROUNDS"
    echo "=================================================================="

    # # 1. RESET DA REDE FABRIC
    # # Isso é crucial para garantir que a rodada comece limpa
    # if [ -f "$SETUP_NETWORK_SCRIPT" ]; then
    #     echo "[INFO] Reiniciando Rede Fabric..."
    #     "$SETUP_NETWORK_SCRIPT"
    #     # Aguarda um pouco para garantir que os containers estão saudáveis
    #     sleep 10 
    # else
    #     echo "[ERRO] Script de setup da rede não encontrado em: $SETUP_NETWORK_SCRIPT"
    #     exit 1
    # fi

    # 2. INICIAR MONITORAMENTO CPU DO HOST (sar)
    HOST_LOG="${HOST_MONITOR_DIR}/host_cpu_round_${i}.log"
    echo "[INFO] Iniciando monitoramento de Host CPU em: $HOST_LOG"
    # Coleta a cada 1 segundo em background
    sar -u 1 > "$HOST_LOG" &
    MONITOR_PID=$!

    # 2. EXECUTAR OS TESTES JMeter (Chama o Executor)
    echo "[RUN] Executando JMeter..."
    ROUND_FOLDER="${RESULTS_DIR}/round_${i}"
    mkdir -p "$ROUND_FOLDER"
    # Passamos $i como argumento para que o executor saiba qual é a rodada atual
    ./run_jmeter_api.sh "$ROUND_FOLDER/api.log" $WORKERS $i 

    # 3. PARAR MONITORAMENTO
    kill $MONITOR_PID
    echo "[INFO] Monitoramento parado."

    # Mover log de CPU para a pasta da rodada
    
    if [ -d "$ROUND_FOLDER" ] && [ -f "$HOST_LOG" ]; then
        mv "$HOST_LOG" "${ROUND_FOLDER}/"
    fi

    # 4. GERAR GRÁFICOS (COM DEBUG)
    echo "[INFO] Gerando gráficos exclusivos desta rodada..."
    
    if [ ! -f "$GENERATE_GRAPHS_SCRIPT" ]; then
        echo "[ERRO] Script Python não encontrado em: $GENERATE_GRAPHS_SCRIPT"
    elif [ ! -d "$ROUND_FOLDER" ]; then
        echo "[ERRO] Pasta da rodada não encontrada: $ROUND_FOLDER"
    else
        # Executa e captura erro se houver
        if python3 "$GENERATE_GRAPHS_SCRIPT" "${ROUND_FOLDER}"; then
            echo "[INFO] Gráficos gerados com sucesso em: ${ROUND_FOLDER}/graphs"
        else
            echo "[INFO] FALHA na geração dos gráficos. Verifique se o 'pandas' está instalado."
        fi
    fi
    
    PID_FILE="${PROJECT_ROOT}/api_pid.txt"
    if [ -f "$PID_FILE" ]; then
        echo "[INFO] Encerrando API da rodada $i (PID: $(cat "$PID_FILE"))..."
        kill -9 $(cat "$PID_FILE") 2>/dev/null
        rm "$PID_FILE"
        sleep 2 # Tempo para o SO liberar a porta
    fi

    # 6. PAUSA / RESFRIAMENTO
    echo "[INFO] Rodada $i finalizada. Aguardando 10s para estabilização..."
    sleep 10
done

end_time=$(date +%s%3N)
duracao=$((end_time - start_time))
minutos=$(awk "BEGIN {print $duracao/60000}")
echo "[INFO] BATERIA JMETER CONCLUÍDA EM $minutos" MINUTOS
echo "[INFO] Para gerar o comparativo final, execute: ./generateFinalReport.sh"
