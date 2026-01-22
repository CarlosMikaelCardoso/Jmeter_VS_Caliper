import pandas as pd
import os
import sys
import glob
import re

def generate_jmeter_table(results_dir, output_dir):
    # [CORREÇÃO] Garante que a pasta de saída existe
    os.makedirs(output_dir, exist_ok=True)
    
    print(f"--- [JMeter] Gerando Tabela de Performance ---")
    
    rounds = ["Open", "Query", "Transfer"]
    summary_list = []

    # Backend errors log
    backend_err_path = os.path.join(os.path.dirname(results_dir), 'backend_errors.log')
    backend_errors = pd.DataFrame()
    if os.path.exists(backend_err_path):
        try: backend_errors = pd.read_csv(backend_err_path, names=['round', 'run', 'count', 'details'])
        except: pass

    for round_name in rounds:
        files = glob.glob(os.path.join(results_dir, f"results_{round_name.lower()}*.jtl"))
        
        for f in files:
            try:
                df = pd.read_csv(f)
                if df.empty: continue

                match = re.search(r'run_(\d+)', f)
                run_id = int(match.group(1)) if match else 1

                total = len(df)
                succ_jmeter = df['success'].sum()
                
                fail_backend = 0
                if not backend_errors.empty:
                    errs = backend_errors[(backend_errors['round'] == round_name) & (backend_errors['run'] == run_id)]
                    if not errs.empty: fail_backend = errs['count'].sum()
                
                succ_real = max(0, succ_jmeter - fail_backend)
                fail_total = (total - succ_jmeter) + fail_backend

                duration = (df['timeStamp'] + df['elapsed']).max() - df['timeStamp'].min()
                duration_s = duration / 1000.0 if duration > 0 else 1
                tps = succ_real / duration_s

                summary_list.append({
                    'Scenario': round_name,
                    'Run': run_id,
                    'Samples': total,
                    'Success': succ_real,
                    'Fail': fail_total,
                    'Avg Latency (s)': df['elapsed'].mean() / 1000.0,
                    'P99 Latency (s)': df['elapsed'].quantile(0.99) / 1000.0,
                    'TPS': tps
                })
            except Exception as e:
                print(f"Erro em {f}: {e}")

    if summary_list:
        df_final = pd.DataFrame(summary_list)
        df_avg = df_final.groupby('Scenario').mean(numeric_only=True).reset_index()
        
        csv_path = os.path.join(output_dir, "jmeter_performance.csv")
        df_avg.to_csv(csv_path, index=False, float_format="%.4f")
        
        tex_path = os.path.join(output_dir, "jmeter_performance.tex")
        latex_code = df_avg.to_latex(
            index=False, 
            float_format="%.3f",
            columns=['Scenario', 'Success', 'Fail', 'Avg Latency (s)', 'TPS'],
            caption="JMeter Performance Summary (Average)",
            label="tab:jmeter_perf"
        )
        with open(tex_path, "w") as f: f.write(latex_code)
        
        print(f"✅ Tabelas salvas em: {output_dir}")
    else:
        print("⚠️  Nenhum dado JMeter encontrado.")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Uso: python gen_table_perf_jmeter.py <input_dir> <output_dir>")
    else:
        generate_jmeter_table(sys.argv[1], sys.argv[2])