#!/usr/bin/env bash
set -o errexit   # Aborta se um comando falhar
set -o nounset   # Aborta se usar variável não definida
set -o pipefail  # Aborta se falhar em pipe
# set -x           # Descomente para debug

# --- DEFINIÇÃO DE CAMINHOS RELATIVOS ---
# Pega o diretório onde o script está (pasta scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Define a raiz do projeto (um nível acima)
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Caminhos da Nova Estrutura
NETWORK_DIR="${PROJECT_ROOT}/network/test-network"
BENCHMARK_DIR="${PROJECT_ROOT}/benchmarks/caliper_fabric"
RESULTS_DIR="${PROJECT_ROOT}/results/caliper_runs"
GENERATE_GRAPHS_SCRIPT="${SCRIPT_DIR}/generateGraphsCaliper.py"

# Configurações da API de Monitoramento (se estiver usando)
MONITOR_API_URL="http://localhost:3002"

# Cria diretório de resultados se não existir
mkdir -p "${RESULTS_DIR}"

# --- FUNÇÃO DE LIMPEZA ---
cleanup() {
    echo "--- Limpando relatórios antigos em ${RESULTS_DIR} ---"
    rm -rf "${RESULTS_DIR}"
    mkdir -p "${RESULTS_DIR}"
}

# --- SETUP DO CALIPER ---
caliper_setup() {
    echo "--- Verificando instalação do Caliper ---"
    # Verifica se estamos na raiz para instalar dependências se necessário
    cd "${PROJECT_ROOT}"
    
    if ! npx --no-install caliper --version > /dev/null 2>&1; then
        echo "Instalando @hyperledger/caliper-cli..."
        npm install --save-dev @hyperledger/caliper-cli
    fi

    echo "Executando 'caliper bind' para Fabric 2.4..."
    npx caliper bind --caliper-bind-sut fabric:2.5
}

# --- EXECUÇÃO DO TESTE ---
# Args: 1.NomeRodada (Ex: Open) 2.ArquivoConfig (Ex: config-open.yaml) 3.NumeroExecucao
run_caliper_test() {
    local ROUND_NAME=$1
    local CONFIG_FILE="${BENCHMARK_DIR}/$2"
    local RUN_NUMBER=$3
    local ROUND_LABEL_LOWER=$(echo "$ROUND_NAME" | tr '[:upper:]' '[:lower:]')
    local LOG_FILE="${RESULTS_DIR}/caliper_log_${ROUND_LABEL_LOWER}_run_${RUN_NUMBER}.txt"

    echo "--- [Run ${RUN_NUMBER}] Iniciando Benchmark: ${ROUND_NAME} ---"
    
    # Inicia Monitoramento (Opcional, se a API estiver rodando)
    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": ${RUN_NUMBER}}" \
        "${MONITOR_API_URL}/monitor/start" || true

    # Executa Caliper
    # IMPORTANTE: Executamos da raiz para que caminhos relativos no network-config funcionem melhor
    cd "${PROJECT_ROOT}"
    
    echo "Executando Caliper... Logs em: ${LOG_FILE}"
    npx caliper launch manager \
        --caliper-workspace "${PROJECT_ROOT}" \
        --caliper-networkconfig "${BENCHMARK_DIR}/network-config.yaml" \
        --caliper-benchconfig "${CONFIG_FILE}" \
        --caliper-fabric-gateway-enabled \
        --caliper-report-path "${RESULTS_DIR}/report-${ROUND_LABEL_LOWER}.html" \
        > "${LOG_FILE}" 2>&1

    # Para Monitoramento
    curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"roundName\": \"${ROUND_NAME}\", \"runNumber\": ${RUN_NUMBER}}" \
        "${MONITOR_API_URL}/monitor/stop" || true
        
    # Baixa logs do Docker (se a API estiver salvando)
    curl -s -o "${RESULTS_DIR}/docker_stats_${ROUND_LABEL_LOWER}_run_${RUN_NUMBER}.log" \
        "${MONITOR_API_URL}/monitor/logs/${ROUND_NAME}/${RUN_NUMBER}" || true
}

main() {
    cleanup
    caliper_setup

    # Executa os testes (1 repetição por padrão)
    local RUN_NUMBER=1
    
    # Ajuste os nomes dos arquivos YAML conforme estão na sua pasta benchmarks/caliper_fabric
    run_caliper_test "Open" "config-open.yaml" ${RUN_NUMBER}
    run_caliper_test "Query" "config-query.yaml" ${RUN_NUMBER}
    run_caliper_test "Transfer" "config-transfer.yaml" ${RUN_NUMBER}

    echo "--- Gerando gráficos consolidados ---"
    if [ -f "$GENERATE_GRAPHS_SCRIPT" ]; then
        python3 "$GENERATE_GRAPHS_SCRIPT" "${RESULTS_DIR}" 1
    else
        echo "Aviso: Script de gráficos não encontrado em $GENERATE_GRAPHS_SCRIPT"
    fi
    
    echo "--- Testes Concluídos! Resultados em: ${RESULTS_DIR} ---"
}

main "$@"