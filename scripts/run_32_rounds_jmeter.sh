#!/usr/bin/env bash
set -o nounset
set -o pipefail

# --- CONFIGURAÇÕES ---
TOTAL_ROUNDS=32
WORKERS=${1:-5}

# Caminhos
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_BASE_DIR="${PROJECT_ROOT}/results/jmeter_runs"
CLIENT_MONITOR_DIR="${PROJECT_ROOT}/results/client_monitor_jmeter"
BACKEND_ERRORS_LOG="${RESULTS_BASE_DIR}/backend_errors.log"
GENERATE_GRAPHS_SCRIPT="${SCRIPT_DIR}/generateGraphsCaliper.py" # Ou generateGraphs.py, verifique qual usa para JMeter

# Garante diretórios
mkdir -p "${CLIENT_MONITOR_DIR}"
mkdir -p "${RESULTS_BASE_DIR}"

# ---------------------------------------------------------
# [FIX 1] LIMPEZA DE ESTADO SUJO ANTES DE COMEÇAR
# ---------------------------------------------------------
echo ">>> LIMPANDO ARTEFATOS ANTIGOS..."
rm -f "${BACKEND_ERRORS_LOG}" # Remove os 1000 erros antigos
# Remove pastas antigas para garantir que o gráfico comece do zero
rm -rf "${RESULTS_BASE_DIR}/global_round_"* rm -f "${RESULTS_BASE_DIR}/CONSOLIDATED_"*

# Verifica API
echo ">>> Verificando API (localhost:3000)..."
if ! command -v nc &> /dev/null || ! nc -z localhost 3000; then
    # Fallback simples
    if ! (echo > /dev/tcp/localhost/3000) >/dev/null 2>&1; then
        echo "❌ API Offline. Inicie 'npm start' no middleware."
        exit 1
    fi
fi
echo "✅ API Online."

echo ">>> INICIANDO BATERIA DE $TOTAL_ROUNDS RODADAS JMETER <<<"

for (( i=1; i<=TOTAL_ROUNDS; i++ ))
do
    echo ""
    echo "=================================================================="
    echo "   RODADA GLOBAL $i de $TOTAL_ROUNDS"
    echo "=================================================================="

    # 1. MONITORAMENTO
    CLIENT_LOG="${CLIENT_MONITOR_DIR}/client_cpu_round_${i}.log"
    sar -u 1 > "${CLIENT_LOG}" &
    MONITOR_PID=$!

    # 2. EXECUÇÃO DO TESTE (run_jmeter_api.sh)
    echo ">>> [Execução] Rodando Testes..."
    cd "${SCRIPT_DIR}"
    
    # Executa o executor. Se falhar, mata o monitor e sai.
    if ! ./run_jmeter_api.sh "$WORKERS" "$i"; then
        echo "❌ Falha na execução da rodada $i"
        kill $MONITOR_PID || true
        exit 1
    fi

    # 3. PARAR MONITORAMENTO
    kill $MONITOR_PID || true

    # 4. ORGANIZAÇÃO DE ARTEFATOS
    # Cria a pasta da rodada
    ROUND_DIR="${RESULTS_BASE_DIR}/global_round_${i}"
    mkdir -p "${ROUND_DIR}"
    
    echo ">>> [Organização] Movendo resultados para: ${ROUND_DIR}"
    
    # Move os resultados do JMeter (JTL, CSV, HTML, TXT)
    mv "${RESULTS_BASE_DIR}"/*.csv "${ROUND_DIR}/" 2>/dev/null || true
    mv "${RESULTS_BASE_DIR}"/*.jtl "${ROUND_DIR}/" 2>/dev/null || true
    mv "${RESULTS_BASE_DIR}"/*.txt "${ROUND_DIR}/" 2>/dev/null || true
    # Move pastas de relatório HTML se existirem
    mv "${RESULTS_BASE_DIR}"/report_* "${ROUND_DIR}/" 2>/dev/null || true
    
    # [FIX] Copia o log de monitoramento do cliente para a pasta da rodada também
    cp "${CLIENT_LOG}" "${ROUND_DIR}/"

    # [FIX] Manter o backend_errors.log na raiz para acumular?
    # O Python script geralmente varre as subpastas OU lê um arquivo central.
    # Se o seu script Python espera ler "backend_errors.log" para contar erros,
    # ele precisa estar lá. Como a API faz append, ele já está lá.
    # Vamos fazer um backup dele dentro da rodada por segurança.
    if [ -f "${BACKEND_ERRORS_LOG}" ]; then
        cp "${BACKEND_ERRORS_LOG}" "${ROUND_DIR}/backend_errors_snapshot.log"
    fi

    # 5. [FIX 2] GERAÇÃO DE GRÁFICOS E TABELAS (ATUALIZAÇÃO)
    echo ">>> [Gráficos] Atualizando tabelas e gráficos consolidados..."
    # Chamamos o script Python apontando para a pasta BASE. 
    # Ele deve ser capaz de ler as subpastas global_round_X
    if [ -f "${GENERATE_GRAPHS_SCRIPT}" ]; then
        # Assumindo que o script aceita: python script.py <pasta_resultados> <workers>
        python3 "${GENERATE_GRAPHS_SCRIPT}" "${RESULTS_BASE_DIR}" "$WORKERS" || echo "⚠️ Erro ao gerar gráficos (não fatal)"
    else
        # Tenta o outro nome comum
        python3 "${SCRIPT_DIR}/generateGraphs.py" "${RESULTS_BASE_DIR}" "$WORKERS" || echo "⚠️ Erro ao gerar gráficos (não fatal)"
    fi

    echo "✅ Rodada Global $i concluída."
    sleep 5
done

echo ">>> BATERIA JMETER FINALIZADA <<<"