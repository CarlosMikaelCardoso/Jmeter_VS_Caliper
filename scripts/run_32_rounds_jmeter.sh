#!/bin/bash

# Configurações Gerais
TOTAL_ROUNDS=32
WORKERS=5 
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Caminhos
RESULTS_DIR="${PROJECT_ROOT}/results/jmeter_runs"
HOST_MONITOR_DIR="${RESULTS_DIR}/host_monitor"
SETUP_NETWORK_SCRIPT="${SCRIPT_DIR}/setup_fabric_network.sh" # Confirme se o caminho está correto
GENERATE_GRAPHS_SCRIPT="${SCRIPT_DIR}/generateGraphs.py"

mkdir -p "${HOST_MONITOR_DIR}"

echo ">>> INICIANDO BATERIA DE $TOTAL_ROUNDS RODADAS (JMeter) <<<"
echo ">>> Workers definidos: $WORKERS"

for (( i=1; i<=TOTAL_ROUNDS; i++ ))
do
    echo ""
    echo "=================================================================="
    echo "   RODADA $i de $TOTAL_ROUNDS"
    echo "=================================================================="

    # # 1. RESET DA REDE FABRIC
    # # Isso é crucial para garantir que a rodada começa limpa
    # if [ -f "$SETUP_NETWORK_SCRIPT" ]; then
    #     echo ">>> [Passo 0] Reiniciando Rede Fabric..."
    #     "$SETUP_NETWORK_SCRIPT"
    #     # Aguarda um pouco para garantir que os containers estão saudáveis
    #     sleep 10 
    # else
    #     echo "❌ ERRO: Script de setup da rede não encontrado em: $SETUP_NETWORK_SCRIPT"
    #     exit 1
    # fi

    # 2. INICIAR MONITORAMENTO CPU DO HOST (sar)
    HOST_LOG="${HOST_MONITOR_DIR}/host_cpu_round_${i}.log"
    echo ">>> [Passo 1] Iniciando monitoramento de Host CPU em: $HOST_LOG"
    # Coleta a cada 1 segundo em background
    sar -u 1 > "$HOST_LOG" &
    MONITOR_PID=$!

    # 3. EXECUTAR OS TESTES JMeter (Chama o Executor)
    echo ">>> [Passo 2] Executando JMeter..."
    # Passamos $i como argumento para que o executor saiba qual é a rodada atual
    ./run_jmeter_api.sh $WORKERS $i

    # 4. PARAR MONITORAMENTO
    kill $MONITOR_PID
    echo ">>> [Passo 3] Monitoramento parado."

    # Mover log de CPU para a pasta da rodada
    ROUND_FOLDER="${RESULTS_DIR}/round_${i}"
    if [ -d "$ROUND_FOLDER" ] && [ -f "$HOST_LOG" ]; then
        mv "$HOST_LOG" "${ROUND_FOLDER}/"
    fi

    # 5. GERAR GRÁFICOS (COM DEBUG)
    echo ">>> [Passo 4] Gerando gráficos exclusivos desta rodada..."
    
    if [ ! -f "$GENERATE_GRAPHS_SCRIPT" ]; then
        echo "❌ ERRO: Script Python não encontrado em: $GENERATE_GRAPHS_SCRIPT"
    elif [ ! -d "$ROUND_FOLDER" ]; then
        echo "❌ ERRO: Pasta da rodada não encontrada: $ROUND_FOLDER"
    else
        # Executa e captura erro se houver
        if python3 "$GENERATE_GRAPHS_SCRIPT" "${ROUND_FOLDER}"; then
            echo "📊 Gráficos gerados com sucesso em: ${ROUND_FOLDER}/graphs"
        else
            echo "❌ FALHA na geração dos gráficos. Verifique se o 'pandas' está instalado."
        fi
    fi

    # 5. PAUSA / RESFRIAMENTO
    echo ">>> Rodada $i finalizada. Aguardando 10s para estabilização..."
    sleep 10
done

echo ">>> BATERIA DE TESTES CONCLUÍDA <<<"
echo "Para gerar o comparativo final, execute: ./generate_final_report.sh"