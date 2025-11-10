#!/usr/bin/env bash
set -o errexit   # Aborta a execução se um comando falhar
set -o nounset   # Aborta a execução se uma variável não definida for usada
set -o pipefail  # Aborta se algum comando em um pipeline falhar
set -x           # Modo de depuração

# --- Caminhos ---
BASE_DIR="$(pwd)"
NETWORK_DIR="${BASE_DIR}/network_fabric/test-network"
CHAINCODE_DIR="${BASE_DIR}/chaincode_simple/simple/go"
MONITOR_DIR="${NETWORK_DIR}/prometheus-grafana"
BENCHMARK_DIR="${BASE_DIR}/simple" # Onde os 3 yamls estão

# --- Configurações da API ---
MONITOR_API_URL="http://localhost:3002"
RESULTS_DIR="${BASE_DIR}/caliper_fabric_reports"

# --- Função de Limpeza ---
cleanup() {
    # echo "--- [1/5] Derrubando redes (Fabric e Monitoramento) ---"
    # (cd "${NETWORK_DIR}" && ./network.sh down) || echo "Rede Fabric já estava parada."
    # # Vamos derrubar também o Grafana/Prometheus para garantir um início limpo
    # (cd "${MONITOR_DIR}" && docker-compose down) || echo "Monitores já estavam parados."
    
    # Limpa relatórios antigos
    rm -rf "${RESULTS_DIR}"
    mkdir -p "${RESULTS_DIR}"
    echo "Limpeza concluída."
}

# --- Função de Subir Rede ---
setup_network() {
    # echo "--- [2/5] Subindo rede Fabric (Isso pode demorar) ---"
    # cd "${NETWORK_DIR}"
    # ./network.sh up createChannel -c gercom -s couchdb
    
    # echo "--- [3/5] Fazendo deploy do Chaincode 'simple' ---"
    # ./network.sh deployCC -ccn simple -ccp "${CHAINCODE_DIR}" -ccl go -c gercom
    
    # IMPORTANTE: A stack do Prometheus (que o Grafana usa) DEVE estar no ar
    # para a sua API de monitoramento funcionar, mesmo que o Caliper não a use.
    # Mas como sua API nova usa DOCKERODE, não precisamos do Prometheus.
    # Vamos subir apenas o Grafana/Prometheus se o usuário quiser ver.
    
    # echo "--- [4/5] Subindo stack de Monitoramento (Prometheus/Grafana) ---"
    # (cd "${MONITOR_DIR}" && docker-compose up -d)
    # echo "Aguardando 10s para o Prometheus iniciar..."
    # sleep 10
    
    echo "--- [4/5] Rede Pronta ---"
    cd "${BASE_DIR}" # Voltar para a raiz de 'testes_fabric'
}

# --- Função de Teste ---
# Argumentos: 1.NomeDaRodada (ex: open) 2.ArquivoConfig (ex: config-open.yaml) 3.RunNumber (ex: 1)
run_caliper_test() {
    local ROUND_NAME=$1
    local CONFIG_FILE=$2
    local RUN_NUMBER=$3
    local ROUND_LABEL_LOWER=$(echo "$ROUND_NAME" | tr '[:upper:]' '[:lower:]')

    # --- ADICIONADO: Define o caminho do log de performance ---
    local CALIPER_PERF_LOG="${RESULTS_DIR}/caliper_log_${ROUND_LABEL_LOWER}_run_${RUN_NUMBER}.txt"

    echo "--- Iniciando Monitoramento para: ${ROUND_NAME} (Run ${RUN_NUMBER}) ---"
    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": ${RUN_NUMBER}}" \
        "${MONITOR_API_URL}/monitor/start"

    echo "--- Executando Caliper para: ${ROUND_NAME} ---"
    # --- ADICIONADO: Informa onde o log de performance será salvo ---
    echo "--- Log de performance sendo salvo em: ${CALIPER_PERF_LOG} ---"
    
    # --- MODIFICADO: Adicionado redirecionamento de stdout/stderr para o arquivo de log ---
    npx caliper launch manager \
        --caliper-workspace ./ \
        --caliper-networkconfig fabric/test-network.yaml \
        --caliper-benchconfig "${BENCHMARK_DIR}/${CONFIG_FILE}" \
        --caliper-fabric-gateway-enabled \
        --caliper-report-path "${RESULTS_DIR}/report-${ROUND_LABEL_LOWER}.html" \
        > "${CALIPER_PERF_LOG}" 2>&1
    # --- FIM DA MODIFICAÇÃO ---
    
    echo "--- Parando Monitoramento para: ${ROUND_NAME} (Run ${RUN_NUMBER}) ---"
    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": ${RUN_NUMBER}}" \
        "${MONITOR_API_URL}/monitor/stop"
        
    echo "--- Baixando Logs de Monitoramento para: ${ROUND_NAME} ---"
    curl -s -o "${RESULTS_DIR}/docker_stats_${ROUND_LABEL_LOWER}_run_${RUN_NUMBER}.log" \
        "${MONITOR_API_URL}/monitor/logs/${ROUND_NAME}/${RUN_NUMBER}"
        
    echo "--- Rodada ${ROUND_NAME} concluída ---"
}


# --- Função Principal ---
main() {
    # 1. Limpa tudo (incluindo o ledger sujo que causou as 1000 falhas)
    cleanup
    
    # 2. Sobe a rede Fabric
    setup_network

    echo "--- [5/5] Executando Benchmarks do Caliper em sequência ---"
    echo "IMPORTANTE: Certifique-se que a API de Monitoramento (monitor_api.js) está rodando na porta ${MONITOR_API_URL}"
    sleep 5 # Pausa para o usuário ler

    # 3. Executa os testes um por um
    # (Assumindo 1 repetição, como no script original)
    local RUN_NUMBER=1
    run_caliper_test "Open" "config-open.yaml" ${RUN_NUMBER}
    run_caliper_test "Query" "config-query.yaml" ${RUN_NUMBER}
    run_caliper_test "Transfer" "config-transfer.yaml" ${RUN_NUMBER}

    echo "--- Benchmarks concluídos! ---"
    echo "Relatórios e logs de monitoramento salvos em: ${RESULTS_DIR}"
    
    # --- ADICIONADO: Chamada ao novo script de geração de gráficos ---
    echo "--- Gerando gráficos consolidados dos resultados ---"
    # Passa o diretório de resultados e o número de repetições (hardcoded como 1)
    python3 "${BASE_DIR}/generateGraphsCaliper.py" "${RESULTS_DIR}" 1
    echo "--- Gráficos gerados com sucesso! ---"
    # --- FIM DA MODIFICAÇÃO ---
}

# Executa o script
main "$@"