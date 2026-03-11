import sys
import os
import pandas as pd
import glob
import re

def parse_caliper_log(filepath):
    """Extrai dados da tabela markdown do log do Caliper (8 colunas)"""
    tps, lat, suc, fail = 0.0, 0.0, 0, 0
    try:
        with open(filepath, 'r') as f:
            content = f.read()
            
        # Regex corrigida para: Name | Succ | Fail | Send Rate | Max | Min | Avg | TPS
        # Capturamos: Name(1), Succ(2), Fail(3), Avg Lat(4), TPS(5)
        pattern = r'\|\s*(\w+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|.*?\|.*?\|.*?\|\s*([\d\.]+)\s*\|\s*([\d\.]+)\s*\|'
        
        match = re.search(pattern, content)
        if match:
            suc = int(match.group(2))
            fail = int(match.group(3))
            lat = float(match.group(4)) # Avg Latency
            tps = float(match.group(5)) # TPS (Agora na posição correta)
            return suc, fail, tps, lat
    except Exception as e:
        print(f"Erro lendo {filepath}: {e}")
    
    return suc, fail, tps, lat


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
            
            suc, fail, tps, lat = parse_caliper_log(f)
            
            if suc > 0 or fail > 0:
                all_data.append({
                    'Scenario': scenario,
                    'Rodada': round_num,
                    'Samples': suc + fail,
                    'Successful': suc,
                    'Failed': fail,
                    'Throughput (TPS)': round(tps, 2),
                    'Avg Latency (s)': round(lat, 4),
                    'P99 Latency (s)': 0.0 # O log de texto não provê P99, setamos 0.0 para manter compatibilidade
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
