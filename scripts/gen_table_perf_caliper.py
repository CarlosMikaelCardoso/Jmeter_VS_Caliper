import sys
import os
import pandas as pd
import glob
import re

def parse_caliper_log(filepath):
    """Extrai dados incluindo P99 se disponível no log"""
    tps, lat, p99, suc, fail = 0.0, 0.0, 0.0, 0, 0
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        # Regex atualizada: procura a tabela de resultados que contém o P99
        # Padrão esperado: | Name | Succ | Fail | Send Rate | Max | Min | Avg | P99 (ou similar) | TPS |
        # Nota: Ajustamos para capturar o valor antes do TPS que costuma ser o P99 em relatórios detalhados
        pattern = r'\|\s*(\w+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|.*?\|.*?\|.*?\|\s*([\d\.]+)\s*\|\s*([\d\.]+)\s*\|\s*([\d\.]+)\s*\|'
        
        match = re.search(pattern, content)
        if match:
            suc = int(match.group(2))
            fail = int(match.group(3))
            lat = float(match.group(4))  # Avg Latency
            p99 = float(match.group(5))  # P99 Latency (Capturado da nova coluna)
            tps = float(match.group(6))  # TPS
            return suc, fail, tps, lat, p99
    except Exception: pass
    return suc, fail, tps, lat, p99


def main():
    if len(sys.argv) < 3:
        print("Uso: python3 gen_table_perf_caliper.py <input_dir> <output_dir>")
        sys.exit(1)

    input_dir = sys.argv[1]
    output_dir = sys.argv[2]
    
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    print(f"--- [Caliper] Extraindo Métricas de {input_dir} ---")
    files = glob.glob(os.path.join(input_dir, "caliper_*.txt")) + glob.glob(os.path.join(input_dir, "caliper_*.log"))
    
    all_data = []

    for f in files:
        filename = os.path.basename(f)
        # Tenta extrair cenário e rodada do nome do arquivo
        match = re.search(r'caliper_(.*)_run_(\d+)', filename)
        
        if match:
            scenario = match.group(1)
            round_num = int(match.group(2))
            
            suc, fail, tps, lat, p99 = parse_caliper_log(f)
            
            if suc > 0 or fail > 0:
                all_data.append({
                    'Scenario': scenario,
                    'Rodada': round_num,
                    'Samples': suc + fail,
                    'Successful': suc,
                    'Failed': fail,
                    'Throughput (TPS)': round(tps, 2),
                    'Avg Latency (s)': round(lat, 4),
                    'P99 Latency (s)': round(p99, 4)
                })

    if all_data:
        df_all = pd.DataFrame(all_data)
        output_csv = os.path.join(output_dir, "round_performance_summary.csv")
        df_all.to_csv(output_csv, index=False)
        print(f"✅ CSV Intermediário Caliper Gerado: {output_csv}")
    else:
        print("⚠️  Nenhum dado Caliper extraído (Verifique se os logs tem a tabela final).")

if __name__ == "__main__":
    main()
