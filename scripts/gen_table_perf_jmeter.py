import pandas as pd
import os
import sys
import glob
import re

def generate_jmeter_table(results_dir, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    print(f"--- [JMeter] Gerando Tabela Consolidada (SOMA de Amostras / MÉDIA de TPS) ---")
    
    rounds = ["Open", "Query", "Transfer"]
    summary_list = []

    # Carrega erros de backend
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
                    'Samples': total,
                    'Success': succ_real,
                    'Fail': fail_total,
                    'Avg Latency (s)': df['elapsed'].mean() / 1000.0,
                    'TPS': tps
                })
            except: pass

    if summary_list:
        df_final = pd.DataFrame(summary_list)
        
        # [MUDANÇA CRUCIAL] Agregação Híbrida:
        # - Contagens (Samples, Success, Fail) -> SOMA (sum)
        # - Performance (Latência, TPS) -> MÉDIA (mean)
        agg_rules = {
            'Samples': 'sum',
            'Success': 'sum',
            'Fail': 'sum',
            'Avg Latency (s)': 'mean',
            'TPS': 'mean'
        }
        
        df_consolidated = df_final.groupby('Scenario').agg(agg_rules).reset_index()
        
        # Salva CSV
        df_consolidated.to_csv(os.path.join(output_dir, "jmeter_performance.csv"), index=False, float_format="%.4f")
        
        # Salva LaTeX (Formatado com inteiros para contagens e floats para tempo)
        latex_code = df_consolidated.to_latex(
            index=False, 
            float_format="%.3f",
            formatters={
                'Samples': "{:.0f}".format, 
                'Success': "{:.0f}".format, 
                'Fail': "{:.0f}".format
            },
            caption=f"JMeter Consolidated Results (Total of {len(summary_list)//3} rounds)",
            label="tab:jmeter_perf_total"
        )
        with open(os.path.join(output_dir, "jmeter_performance.tex"), "w") as f: f.write(latex_code)
        
        print(f"✅ Tabela JMeter gerada.")
        print(f"   Exemplo Open: Samples={df_consolidated.loc[df_consolidated['Scenario']=='Open', 'Samples'].values[0]} (Esperado: ~32000)")
    else:
        print("⚠️  Nenhum dado JMeter encontrado.")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Uso: python gen_table_perf_jmeter.py <input_dir> <output_dir>")
    else:
        generate_jmeter_table(sys.argv[1], sys.argv[2])