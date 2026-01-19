#!/usr/bin/env bash
set -o nounset
set -o pipefail

# --- CONFIGURAÇÕES ---
TOTAL_ROUNDS=32
WORKERS=${1:-5} # Passa o numero de workers (Default 5)

# Caminhos
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_BASE_DIR="${PROJECT_ROOT}/results/jmeter_runs"
CLIENT_MONITOR_DIR="${PROJECT_ROOT}/results/client_monitor_jmeter"

# Garante diretórios de log do monitoramento
mkdir -p "${CLIENT_MONITOR_DIR}"

# Verifica se o sysstat (sar) está instalado para monitorar CPU
if ! command -v sar &> /dev/null; then
    echo "❌ O comando 'sar' (sysstat) não foi encontrado."
    echo "   Instale com: sudo apt-get install sysstat -y"
    exit 1
fi

echo ">>> INICIANDO BATERIA DE $TOTAL_ROUNDS RODADAS JMETER (WRAPPER) <<<"

for (( i=1; i<=TOTAL_ROUNDS; i++ ))
do
    echo ""
    echo "=================================================================="
    echo "   RODADA GLOBAL $i de $TOTAL_ROUNDS"
    echo "=================================================================="

    # 1. MONITORAMENTO DE HARDWARE (CLIENTE/HOST)
    # Inicia o sar em background para logar a CPU a cada 1 segundo
    echo ">>> [Monitor] Iniciando monitoramento de CPU do Host..."
    CLIENT_LOG="${CLIENT_MONITOR_DIR}/client_cpu_round_${i}.log"
    sar -u 1 > "${CLIENT_LOG}" &
    MONITOR_PID=$!

    # 2. EXECUÇÃO DO TESTE (Chama o seu script existente)
    # Chamamos o run_jmeter_api.sh pedindo 1 repetição apenas.
    # O loop externo (este script) garante as 32 execuções isoladas.
    echo ">>> [Execução] Chamando run_jmeter_api.sh..."
    
    cd "${SCRIPT_DIR}"
    # $WORKERS = Usuários virtuais
    # 1 = Repetições internas (fazemos apenas 1 por vez para monitorar individualmente)
    if ./run_jmeter_api.sh "$WORKERS" 1; then
        echo "✅ run_jmeter_api.sh finalizou com sucesso."
    else
        echo "❌ Falha na execução do run_jmeter_api.sh na rodada $i"
        kill $MONITOR_PID || true
        exit 1
    fi

    # 3. PARAR MONITORAMENTO
    kill $MONITOR_PID || true
    echo ">>> [Monitor] Log salvo em: ${CLIENT_LOG}"

    # 4. VALIDAÇÃO (SANITY CHECK)
    # Verifica se o Idle da CPU caiu para menos de 10% (Uso > 90%)
    if [ -f "${CLIENT_LOG}" ]; then
        # Pega linhas de dados (ignora cabeçalho/médias), coluna %idle é a última ($NF)
        LOW_IDLE=$(grep -vE "^$|Average|Linux|Média" "${CLIENT_LOG}" | awk '{if($NF < 10.00) print $0}' | wc -l)
        
        if [ "$LOW_IDLE" -gt 0 ]; then
            echo "⚠️  AVISO: A CPU do Host ultrapassou 90% de uso em ${LOW_IDLE} segundos."
        else
            echo "✅ CPU do Host OK (Uso < 90%)."
        fi
    fi

    # 5. ORGANIZAÇÃO DE ARTEFATOS
    # O run_jmeter_api.sh salva tudo em results/jmeter_runs.
    # Precisamos mover isso para uma subpasta da rodada para não sobrescrever na próxima.
    ROUND_DIR="${RESULTS_BASE_DIR}/global_round_${i}"
    mkdir -p "${ROUND_DIR}"
    
    echo ">>> [Organização] Movendo resultados para: ${ROUND_DIR}"
    # Move arquivos CSV, JTL, Logs e pastas de report HTML gerados
    # Ignora erros se arquivos específicos não existirem
    mv "${RESULTS_BASE_DIR}"/*.csv "${ROUND_DIR}/" 2>/dev/null || true
    mv "${RESULTS_BASE_DIR}"/*.jtl "${ROUND_DIR}/" 2>/dev/null || true
    mv "${RESULTS_BASE_DIR}"/*.txt "${ROUND_DIR}/" 2>/dev/null || true
    mv "${RESULTS_BASE_DIR}"/report_* "${ROUND_DIR}/" 2>/dev/null || true

    echo "✅ Rodada Global $i concluída."
    sleep 5 # Pausa para esfriar
done

echo ">>> BATERIA JMETER FINALIZADA <<<"