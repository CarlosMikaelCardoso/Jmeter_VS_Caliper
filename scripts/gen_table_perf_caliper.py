import pandas as pd
import os
import sys
import glob
import re

def remove_ansi_colors(text):
    """Remove códigos de cor ANSI que poluem o log"""
    ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    return ansi_escape.sub('', text)

def extract_number(text):
    """Extrai apenas números e pontos"""
    try:
        # Remove tudo que não for dígito ou ponto
        clean = re.sub(r'[^\d\.]', '', text)
        return float(clean) if clean else 0.0
    except:
        return 0.0

def generate_caliper_table(results_dir, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    print(f"--- [Caliper] Gerando Tabela de Performance (Case Insensitive) ---")
    
    rounds = ["Open", "Query", "Transfer"]
    summary_list = []

    for round_name in rounds:
        # Busca arquivos
        files = glob.glob(os.path.join(results_dir, f"caliper*{round_name.lower()}*.log"))
        files += glob.glob(os.path.join(results_dir, f"caliper*{round_name.lower()}*.txt"))
        
        if not files:
            files = glob.glob(os.path.join(results_dir, f"*run_*.txt"))
            files += glob.glob(os.path.join(results_dir, f"*run_*.log"))

        for f in files:
            try:
                with open(f, 'r', encoding='utf-8', errors='ignore') as log: 
                    raw_content = log.read()
                
                clean_content = remove_ansi_colors(raw_content)
                
                # [CORREÇÃO] Define o alvo em minúsculas para comparação segura
                target_name = round_name.lower() 

                for line in clean_content.splitlines():
                    # Converte a linha para minúsculas antes de checar
                    line_lower = line.lower()
                    
                    # Procura "| open " ou "|open|"
                    if f"| {target_name} " in line_lower or f"|{target_name}|" in line_lower:
                        
                        parts = [p.strip() for p in line.split('|')]
                        
                        # Estrutura esperada do Caliper:
                        # ['', 'open', '1000', '0', '50.3', '8.04', '0.26', '3.65', '42.2', '']
                        # 1=Name, 2=Succ, 3=Fail, 7=Avg Lat, 8=Throughput
                        
                        if len(parts) >= 9:
                            try:
                                succ = int(extract_number(parts[2]))
                                fail = int(extract_number(parts[3]))
                                avg_lat = extract_number(parts[7])
                                tps = extract_number(parts[8])
                                
                                # Verifica sanidade (evita pegar cabeçalho se algo der errado)
                                if succ == 0 and fail == 0 and tps == 0:
                                    continue 

                                summary_list.append({
                                    'Scenario': round_name, # Usa o nome bonito (Title Case)
                                    'Success': succ,
                                    'Fail': fail,
                                    'Avg Latency (s)': avg_lat,
                                    'TPS': tps
                                })
                                # Achou a linha, pode parar de ler este arquivo
                                break 
                            except: pass
            
            except Exception as e:
                print(f"Erro ao ler arquivo {f}: {e}")

    if summary_list:
        df_final = pd.DataFrame(summary_list)
        # Agrupa e tira média
        df_avg = df_final.groupby('Scenario').mean(numeric_only=True).reset_index()
        
        # Salva CSV
        df_avg.to_csv(os.path.join(output_dir, "caliper_performance.csv"), index=False, float_format="%.4f")
        
        # Salva LaTeX
        tex_path = os.path.join(output_dir, "caliper_performance.tex")
        latex_code = df_avg.to_latex(
            index=False,
            float_format="%.3f",
            caption="Caliper Performance Summary (Average)",
            label="tab:caliper_perf"
        )
        with open(tex_path, "w") as f: f.write(latex_code)
        
        print(f"✅ Tabelas Caliper salvas em: {output_dir}")
        print(f"   (Dados extraídos de {len(summary_list)} arquivos)")
    else:
        print("⚠️  Nenhum dado Caliper encontrado.")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Uso: python gen_table_perf_caliper.py <input_dir> <output_dir>")
    else:
        generate_caliper_table(sys.argv[1], sys.argv[2])