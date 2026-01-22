#!/bin/bash

# --- Configurações ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Diretórios de Resultados
JMETER_RESULTS_DIR="${PROJECT_ROOT}/results/jmeter_runs"
CALIPER_RESULTS_DIR="${PROJECT_ROOT}/results/caliper_runs"

# Scripts Python (Simplificados)
GEN_GRAPH_JMETER="${SCRIPT_DIR}/generateGraphs.py"
GEN_GRAPH_CALIPER="${SCRIPT_DIR}/generateGraphsCaliper.py"

echo "========================================================"
echo "   GERADOR DE RELATÓRIO FINAL (MÉDIA DE 32 RODADAS)"
echo "========================================================"

# Função para consolidar arquivos de várias pastas numa única para o Python processar
process_consolidation() {
    local TYPE=$1
    local BASE_DIR=$2
    local SCRIPT=$3
    
    if [ ! -d "$BASE_DIR" ]; then
        echo "⚠️  Diretório $TYPE não encontrado: $BASE_DIR"
        return
    fi

    # Pasta temporária para juntar tudo
    local TEMP_DIR="${BASE_DIR}/temp_consolidation"
    local FINAL_OUTPUT="${BASE_DIR}/RELATORIO_FINAL_CONSOLIDADO"
    
    rm -rf "$TEMP_DIR" "$FINAL_OUTPUT"
    mkdir -p "$TEMP_DIR"

    echo ""
    echo ">>> Processando $TYPE..."
    echo "    1. Coletando dados de todas as rodadas..."

    # Varre todas as pastas round_*
    count=0
    for round_dir in "$BASE_DIR"/round_*; do
        if [ -d "$round_dir" ]; then
            # Extrai o número da rodada (ex: round_5 -> 5)
            dirname=$(basename "$round_dir")
            round_num=$(echo "$dirname" | grep -oE '[0-9]+')
            
            # Se não achar número, pula
            if [ -z "$round_num" ]; then continue; fi

            # --- JMETER JTL ---
            # Copia results_open.jtl -> temp/results_open_run_5.jtl
            for f in "$round_dir"/results_*.jtl; do
                if [ -f "$f" ]; then
                    base_name=$(basename "$f" .jtl)
                    # Remove qualquer sufixo _run_X antigo para não duplicar
                    clean_name=$(echo "$base_name" | sed -E 's/_run_[0-9]+//')
                    cp "$f" "${TEMP_DIR}/${clean_name}_run_${round_num}.jtl"
                fi
            done

            # --- CALIPER LOGS ---
            # Copia caliper_open.log -> temp/caliper_open_run_5.log
            for f in "$round_dir"/caliper_*.log; do
                if [ -f "$f" ]; then
                    base_name=$(basename "$f" .log)
                    clean_name=$(echo "$base_name" | sed -E 's/_run_[0-9]+//')
                    cp "$f" "${TEMP_DIR}/${clean_name}_run_${round_num}.log"
                fi
            done

            # --- DOCKER STATS (Comum a ambos) ---
            # Copia docker_stats_open.json -> temp/docker_stats_open_run_5.json
            for f in "$round_dir"/docker_stats_*; do
                if [ -f "$f" ]; then
                    ext="${f##*.}" # json ou log
                    base_name=$(basename "$f" ."$ext")
                    clean_name=$(echo "$base_name" | sed -E 's/_run_[0-9]+//')
                    cp "$f" "${TEMP_DIR}/${clean_name}_run_${round_num}.${ext}"
                fi
            done
            
            count=$((count+1))
        fi
    done

    echo "    -> Dados coletados de $count rodadas."
    
    if [ $count -eq 0 ]; then
        echo "    -> Nenhuma rodada encontrada. Nada a fazer."
        rm -rf "$TEMP_DIR"
        return
    fi

    echo "    2. Gerando gráficos unificados (Média Geral)..."
    if [ -f "$SCRIPT" ]; then
        # Executa o script Python na pasta temporária cheia de arquivos
        # O script vai ler run_1, run_2... run_32 e tirar a média de tudo
        python3 "$SCRIPT" "$TEMP_DIR" > /dev/null
        
        # Move a pasta 'graphs' gerada para o destino final
        if [ -d "${TEMP_DIR}/graphs" ]; then
            mv "${TEMP_DIR}/graphs" "$FINAL_OUTPUT"
            echo "✅ RELATÓRIO $TYPE GERADO EM: $FINAL_OUTPUT"
        else
            echo "❌ Erro: O script Python não gerou a pasta 'graphs'."
        fi
    else
        echo "❌ Script Python não encontrado: $SCRIPT"
    fi

    # Limpa a sujeira
    rm -rf "$TEMP_DIR"
}

# Executa para JMeter
process_consolidation "JMeter" "$JMETER_RESULTS_DIR" "$GEN_GRAPH_JMETER"

# Executa para Caliper
process_consolidation "Caliper" "$CALIPER_RESULTS_DIR" "$GEN_GRAPH_CALIPER"

echo ""
echo "========================================================"
echo "   CONSOLIDAÇÃO CONCLUÍDA"
echo "========================================================"