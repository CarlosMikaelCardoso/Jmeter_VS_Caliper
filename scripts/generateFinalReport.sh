#!/bin/bash

# --- Configurações ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Diretórios
JMETER_RESULTS_DIR="${PROJECT_ROOT}/results/jmeter_runs"
CALIPER_RESULTS_DIR="${PROJECT_ROOT}/results/caliper_runs"

# Scripts Python
GEN_GRAPH_ORIGINAL="${SCRIPT_DIR}/generateGraphs.py"
GEN_GRAPH_CALIPER="${SCRIPT_DIR}/generateGraphsCaliper.py"
GEN_TABLE_CPU="${SCRIPT_DIR}/gen_table_host_cpu.py"
GEN_CHART_CPU="${SCRIPT_DIR}/generate_cpu_chart.py"
GEN_CHART_DOCKER="${SCRIPT_DIR}/generate_resource_charts.py"
GEN_TABLE_PERF_JMETER="${SCRIPT_DIR}/gen_table_perf_jmeter.py"
GEN_TABLE_PERF_CALIPER="${SCRIPT_DIR}/gen_table_perf_caliper.py"
GEN_FINAL_TABLE="${SCRIPT_DIR}/gen_final_table_formats.py"

SUMMARY_CSV="${temp_dir}/graphs/round_performance_summary.csv"
OUTPUT_GRAPHS="${temp_dir}/graphs/"

echo "========================================================"
echo "   GERADOR DE RELATÓRIO FINAL (CONSOLIDADO ROBUSTO)"
echo "========================================================"

process_consolidation() {
    local TYPE=$1
    local BASE_DIR=$2
    local GRAPH_SCRIPT=$3
    
    if [ ! -d "$BASE_DIR" ]; then
        echo "⚠️  Diretório $TYPE não encontrado."
        return
    fi

    local TEMP_DIR="${BASE_DIR}/temp_consolidation"
    local FINAL_OUTPUT="${BASE_DIR}/RELATORIO_FINAL_CONSOLIDADO"
    
    rm -rf "$TEMP_DIR" "$FINAL_OUTPUT"
    mkdir -p "$TEMP_DIR"
    mkdir -p "${TEMP_DIR}/graphs"

    echo ""
    echo ">>> Processando $TYPE..."
    echo "    1. Coletando arquivos das 32 rodadas..."

    count=0
    for round_dir in "$BASE_DIR"/round_*; do
        if [ -d "$round_dir" ]; then
            dirname=$(basename "$round_dir")
            round_num=$(echo "$dirname" | grep -oE '[0-9]+')
            
            if [ "$TYPE" == "JMeter" ]; then
                # --- CORREÇÃO CRÍTICA PARA JMETER ---
                # Renomeia JTLs para padronizar: results_<cenario>_run_<num>.jtl
                for f in "$round_dir"/results_*.jtl; do
                    if [ -f "$f" ]; then
                        # Pega o nome base (ex: results_open.jtl)
                        base_name=$(basename "$f" .jtl)
                        
                        # Tenta extrair o cenário (open, query, transfer)
                        if [[ "$base_name" == *"open"* ]]; then scenario="open";
                        elif [[ "$base_name" == *"query"* ]]; then scenario="query";
                        elif [[ "$base_name" == *"transfer"* ]]; then scenario="transfer";
                        else scenario="unknown"; fi
                        
                        # Copia com o nome PADRONIZADO que o Python espera
                        cp "$f" "${TEMP_DIR}/results_${scenario}_run_${round_num}.jtl"
                    fi
                done
                
                # Copia JSONs do Docker (com renomeação também)
                for f in "$round_dir"/docker_stats_*.json; do
                    if [ -f "$f" ]; then
                        base_name=$(basename "$f" .json)
                        cp "$f" "${TEMP_DIR}/${base_name}_round_${round_num}.json"
                    fi
                done
            else
                # Caliper (já costuma ser padronizado, mas copiamos tudo)
                cp "$round_dir"/caliper_*.txt "${TEMP_DIR}/" 2>/dev/null
                cp "$round_dir"/caliper_*.log "${TEMP_DIR}/" 2>/dev/null
                cp "$round_dir"/*docker_stats* "${TEMP_DIR}/" 2>/dev/null
            fi
            
            cp "$round_dir"/host_cpu_*.log "${TEMP_DIR}/" 2>/dev/null
            count=$((count+1))
        fi
    done
    
    # Merge JTLs para Gráficos Gerais (Só JMeter)
    if [ "$TYPE" == "JMeter" ]; then
        scenarios=("open" "query" "transfer")
        for scen in "${scenarios[@]}"; do
            # Agora busca pelos nomes padronizados que acabamos de criar
            find "$TEMP_DIR" -name "results_${scen}_run_*.jtl" | sort -V > "${TEMP_DIR}/list_${scen}.txt"
            if [ -s "${TEMP_DIR}/list_${scen}.txt" ]; then
                awk 'FNR==1 && NR!=1{next;}{print}' $(cat "${TEMP_DIR}/list_${scen}.txt") > "${TEMP_DIR}/results_${scen}.jtl"
            fi
        done
    fi

    echo "    2. Gerando Gráficos de Distribuição..."
    if [ -f "$GRAPH_SCRIPT" ]; then
        python3 "$GRAPH_SCRIPT" "$TEMP_DIR" > /dev/null
    fi

    echo "    3. Gerando Gráficos de Recursos..."
    if [ -f "$GEN_TABLE_CPU" ]; then
        python3 "$GEN_TABLE_CPU" "$TEMP_DIR" "${TEMP_DIR}/host_cpu_summary.csv" > /dev/null
        python3 "$GEN_CHART_CPU" "$TEMP_DIR" "${TEMP_DIR}" > /dev/null
    fi
    if [ -f "$GEN_CHART_DOCKER" ]; then
        python3 "$GEN_CHART_DOCKER" "$TEMP_DIR" "${TEMP_DIR}" > /dev/null
    fi

    echo "    4. Extraindo Métricas para Tabela Final..."
    # Executa scripts de extração
    if [ "$TYPE" == "JMeter" ]; then
        python3 "$GEN_TABLE_PERF_JMETER" "$TEMP_DIR" "${TEMP_DIR}/graphs"
    else
        python3 "$GEN_TABLE_PERF_CALIPER" "$TEMP_DIR" "${TEMP_DIR}/graphs"
    fi

    echo "    5. Gerando PDF/LaTeX Final..."
    INPUT_CSV="${TEMP_DIR}/graphs/round_performance_summary.csv"
    if [ -f "$GEN_FINAL_TABLE" ]; then
        python3 "$GEN_FINAL_TABLE" "$INPUT_CSV" "${TEMP_DIR}/graphs"
    fi

    echo "    6. Finalizando..."
    mkdir -p "$FINAL_OUTPUT"
    
    mv "${TEMP_DIR}"/*.png "$FINAL_OUTPUT/" 2>/dev/null
    mv "${TEMP_DIR}"/graphs/*.csv "$FINAL_OUTPUT/" 2>/dev/null
    mv "${TEMP_DIR}"/graphs/*.tex "$FINAL_OUTPUT/" 2>/dev/null
    mv "${TEMP_DIR}"/graphs/*.pdf "$FINAL_OUTPUT/" 2>/dev/null
    
    rm -rf "$TEMP_DIR"
    
    echo "✅ RELATÓRIO $TYPE PRONTO EM: $FINAL_OUTPUT"
}

chmod +x "$SCRIPT_DIR"/*.py
process_consolidation "JMeter" "$JMETER_RESULTS_DIR" "$GEN_GRAPH_ORIGINAL"
process_consolidation "Caliper" "$CALIPER_RESULTS_DIR" "$GEN_GRAPH_CALIPER"
python3 analise_estatistica_inferencial.py "/home/gercom/Jmeter_VS_Caliper/results/jmeter_runs/RELATORIO_FINAL_CONSOLIDADO/round_performance_summary.csv" "/home/gercom/Jmeter_VS_Caliper/results/jmeter_runs/RELATORIO_FINAL_CONSOLIDADO/"
python3 analise_estatistica_inferencial.py "/home/gercom/Jmeter_VS_Caliper/results/caliper_runs/RELATORIO_FINAL_CONSOLIDADO/round_performance_summary.csv" "/home/gercom/Jmeter_VS_Caliper/results/caliper_runs/RELATORIO_FINAL_CONSOLIDADO/"