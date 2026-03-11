import sys
import os
import pandas as pd
import glob
import re

def main():
    if len(sys.argv) < 3:
        print("Uso: python3 gen_table_perf_jmeter.py <input_dir> <output_dir>")
        sys.exit(1)

    input_dir = sys.argv[1]
    output_dir = sys.argv[2]
    
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    print(f"--- [JMeter] Extraindo Métricas de {input_dir} ---")
    
    # Busca todos os JTLs individuais copiados
    files = glob.glob(os.path.join(input_dir, "results_*.jtl"))
    
    all_data = []
    
    for f in files:
        try:
            # Lê CSV do JMeter. Ignora linhas ruins.
            # Seu arquivo tem header: timeStamp,elapsed,label,responseCode... success
            df = pd.read_csv(f, on_bad_lines='skip')
            
            filename = os.path.basename(f)
            # Ex: results_open_run_1.jtl
            match = re.search(r'results_(.*)_run_(\d+)', filename)
            
            if match:
                scenario = match.group(1)
                round_num = int(match.group(2))
            else:
                continue

            if not df.empty and 'timeStamp' in df.columns:
                # 1. Contagem de Sucesso/Erro
                if 'success' in df.columns:
                    # O JTL usa "true" (texto) ou boolean. O Pandas converte.
                    success_count = df['success'].astype(str).str.lower().eq('true').sum()
                    error_count = len(df) - success_count
                else:
                    success_count = len(df)
                    error_count = 0

                # 2. TPS (Total Samples / Duration)
                duration_ms = df['timeStamp'].max() - df['timeStamp'].min()
                duration_sec = duration_ms / 1000.0
                tps = len(df) / duration_sec if duration_sec > 0 else 0
                
                # 3. Latência (elapsed é em ms, converter para segundos)
                avg_lat = (df['elapsed'].mean() / 1000.0) if 'elapsed' in df.columns else 0
                p99_lat = (df['elapsed'].quantile(0.99) / 1000.0) if 'elapsed' in df.columns else 0 # Nova métrica

                all_data.append({
                    'Scenario': scenario,
                    'Rodada': round_num,
                    'Samples': len(df),
                    'Successful': success_count,
                    'Failed': error_count,
                    'Throughput (TPS)': round(tps, 2),
                    'Avg Latency (s)': round(avg_lat, 4),
                    'P99 Latency (s)': round(p99_lat, 4)
                })
        except Exception as e:
            pass # Ignora arquivos corrompidos

    if all_data:
        df_all = pd.DataFrame(all_data)
        # Salva na pasta 'graphs' dentro do temp, pois é onde o shell script espera
        output_csv = os.path.join(output_dir, "round_performance_summary.csv")
        df_all.to_csv(output_csv, index=False)
        print(f"✅ CSV Intermediário JMeter Gerado: {output_csv}")
    else:
        print("⚠️  Nenhum dado JMeter extraído.")

if __name__ == "__main__":
    main()
