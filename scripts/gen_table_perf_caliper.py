import pandas as pd
import os
import sys
import glob
import re

def remove_ansi_colors(text):
    ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    return ansi_escape.sub('', text)

def extract_number(text):
    try:
        clean = re.sub(r'[^\d\.]', '', text)
        return float(clean) if clean else 0.0
    except: return 0.0

def generate_caliper_table(results_dir, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    print(f"--- [Caliper] Gerando Tabela Consolidada (SOMA de Amostras / MÉDIA de TPS) ---")
    
    rounds = ["Open", "Query", "Transfer"]
    summary_list = []

    for round_name in rounds:
        files = glob.glob(os.path.join(results_dir, f"caliper*{round_name.lower()}*.log"))
        files += glob.glob(os.path.join(results_dir, f"caliper*{round_name.lower()}*.txt"))
        if not files:
            files = glob.glob(os.path.join(results_dir, f"*run_*.txt"))
            files += glob.glob(os.path.join(results_dir, f"*run_*.log"))

        for f in files:
            try:
                with open(f, 'r', encoding='utf-8', errors='ignore') as log: 
                    clean_content = remove_ansi_colors(log.read())
                
                target_name = round_name.lower()
                for line in clean_content.splitlines():
                    line_lower = line.lower()
                    if f"| {target_name} " in line_lower or f"|{target_name}|" in line_lower:
                        parts = [p.strip() for p in line.split('|')]
                        if len(parts) >= 9:
                            try:
                                succ = int(extract_number(parts[2]))
                                fail = int(extract_number(parts[3]))
                                avg_lat = extract_number(parts[7])
                                tps = extract_number(parts[8])
                                
                                if succ == 0 and fail == 0 and tps == 0: continue 

                                summary_list.append({
                                    'Scenario': round_name,
                                    'Samples': succ + fail, # Caliper não dá total explicito, somamos
                                    'Success': succ,
                                    'Fail': fail,
                                    'Avg Latency (s)': avg_lat,
                                    'TPS': tps
                                })
                                break 
                            except: pass
            except: pass

    if summary_list:
        df_final = pd.DataFrame(summary_list)
        
        # [MUDANÇA CRUCIAL] Agregação Híbrida
        agg_rules = {
            'Samples': 'sum',
            'Success': 'sum',
            'Fail': 'sum',
            'Avg Latency (s)': 'mean',
            'TPS': 'mean'
        }
        
        df_consolidated = df_final.groupby('Scenario').agg(agg_rules).reset_index()
        
        df_consolidated.to_csv(os.path.join(output_dir, "caliper_performance.csv"), index=False, float_format="%.4f")
        
        latex_code = df_consolidated.to_latex(
            index=False,
            float_format="%.3f",
            formatters={
                'Samples': "{:.0f}".format, 
                'Success': "{:.0f}".format, 
                'Fail': "{:.0f}".format
            },
            caption=f"Caliper Consolidated Results (Total of {len(summary_list)//3} rounds)",
            label="tab:caliper_perf_total"
        )
        with open(os.path.join(output_dir, "caliper_performance.tex"), "w") as f: f.write(latex_code)
        
        print(f"✅ Tabela Caliper gerada.")
        print(f"   Exemplo Open: Samples={df_consolidated.loc[df_consolidated['Scenario']=='Open', 'Samples'].values[0]} (Esperado: ~32000)")
    else:
        print("⚠️  Nenhum dado Caliper encontrado.")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Uso: python gen_table_perf_caliper.py <input_dir> <output_dir>")
    else:
        generate_caliper_table(sys.argv[1], sys.argv[2])