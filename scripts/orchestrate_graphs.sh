#!/bin/bash

# Diretórios Base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
JMETER_RESULTS="${PROJECT_ROOT}/results/jmeter_runs"
CALIPER_RESULTS="${PROJECT_ROOT}/results/caliper_runs"

# Scripts Python
SCRIPT_TABLE_JMETER="${SCRIPT_DIR}/gen_table_perf_jmeter.py"
SCRIPT_TABLE_CALIPER="${SCRIPT_DIR}/gen_table_perf_caliper.py"
SCRIPT_CHART_RESOURCES="${SCRIPT_DIR}/gen_chart_resources.py"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "==========================================================="
echo "   ORQUESTRADOR DE ATIVOS PARA ARTIGO (Tabelas & Gráficos)"
echo "==========================================================="

# 1. Verifica Dependências Python
echo -n ">>> Verificando Pandas... "
if python3 -c "import pandas" 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}ERRO: Biblioteca 'pandas' não instalada.${NC}"
    exit 1
fi

# Função de Processamento
process_folder() {
    local TOOL_NAME=$1
    local INPUT_DIR=$2
    local OUTPUT_DIR="${INPUT_DIR}/article_assets"

    if [ -z "$INPUT_DIR" ] || [ ! -d "$INPUT_DIR" ]; then 
        echo -e "${RED}Aviso: Diretório inválido ou não encontrado: '$INPUT_DIR'${NC}"
        return
    fi

    echo -e "\n>> Processando $TOOL_NAME em: $INPUT_DIR"
    mkdir -p "$OUTPUT_DIR"

    echo "   -> Gerando Tabela de Performance..."
    if [ "$TOOL_NAME" == "JMeter" ]; then
        python3 "$SCRIPT_TABLE_JMETER" "$INPUT_DIR" "$OUTPUT_DIR"
    else
        python3 "$SCRIPT_TABLE_CALIPER" "$INPUT_DIR" "$OUTPUT_DIR"
    fi
    
    echo "   -> Gerando Gráficos de Recursos..."
    python3 "$SCRIPT_CHART_RESOURCES" "$INPUT_DIR" "$OUTPUT_DIR"
    
    echo -e "${GREEN}   -> Ativos salvos em: $OUTPUT_DIR${NC}"
}

# --- Consolidação de Arquivos ---
consolidate_files() {
    local BASE_DIR=$1
    local TEMP_DIR="${BASE_DIR}/CONSOLIDATED_FINAL"
    
    mkdir -p "$TEMP_DIR"
    echo "   -> Coletando arquivos de $BASE_DIR..." >&2
    
    # 1. COPIA ARQUIVOS DA RAIZ (Para arquivos que não foram movidos, ex: caliper logs .txt)
    # Procura arquivos que tenham 'run_' no nome para garantir que são de teste
    find "$BASE_DIR" -maxdepth 1 -type f -name "*run_*.txt" -o -name "*run_*.log" | while read f; do
        cp -f "$f" "${TEMP_DIR}/"
    done
    
    # 2. COPIA ARQUIVOS DAS PASTAS round_*
    count=0
    for round_dir in "$BASE_DIR"/round_*; do
        if [ -d "$round_dir" ]; then
            round_num=$(basename "$round_dir" | grep -oE '[0-9]+')
            
            # JMETER (.jtl, .csv)
            find "$round_dir" -maxdepth 1 -name "*.jtl" -o -name "*.csv" | while read f; do
                filename=$(basename "$f"); ext="${filename##*.}"
                name_only="${filename%.*}"
                cp -f "$f" "${TEMP_DIR}/${name_only}_run_${round_num}.${ext}"
            done

            # CALIPER LOGS (.log, .txt)
            find "$round_dir" -maxdepth 1 -name "*.log" -o -name "*.txt" | while read f; do
                filename=$(basename "$f"); ext="${filename##*.}"
                name_only="${filename%.*}"
                cp -f "$f" "${TEMP_DIR}/${name_only}_run_${round_num}.${ext}"
            done

            # DOCKER STATS (.json, .log)
            find "$round_dir" -maxdepth 1 -name "docker_stats_*.json" -o -name "docker_stats_*.log" | while read f; do
                filename=$(basename "$f"); ext="${filename##*.}"
                name_only="${filename%.*}"
                cp -f "$f" "${TEMP_DIR}/${name_only}_run_${round_num}.${ext}"
            done
            count=$((count+1))
        fi
    done
    echo "      (Processadas $count pastas de rodadas + arquivos da raiz)" >&2
    echo "$TEMP_DIR"
}

# --- EXECUÇÃO ---
if [ ! -z "$1" ]; then
    ROUND_NUM=$1
    echo -e "\n${YELLOW}--- Modo Rodada Única: $ROUND_NUM ---${NC}"
    process_folder "JMeter" "${JMETER_RESULTS}/round_${ROUND_NUM}"
    process_folder "Caliper" "${CALIPER_RESULTS}/round_${ROUND_NUM}"
    exit 0
fi

echo -e "\n${YELLOW}--- Iniciando Consolidação JMeter ---${NC}"
TEMP_JMETER=$(consolidate_files "$JMETER_RESULTS")
process_folder "JMeter" "$TEMP_JMETER"

echo -e "\n${YELLOW}--- Iniciando Consolidação Caliper ---${NC}"
TEMP_CALIPER=$(consolidate_files "$CALIPER_RESULTS")
process_folder "Caliper" "$TEMP_CALIPER"

echo ""
echo "✅ Processo Finalizado."