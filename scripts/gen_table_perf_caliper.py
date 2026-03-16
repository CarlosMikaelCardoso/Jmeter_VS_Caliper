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
                })

    if all_data:
        df = pd.DataFrame(all_data)
        
        # Padronização de nomes e ordenação rigorosa
        df['Scenario'] = df['Scenario'].str.replace('log_', '')
        df = df.sort_values(by=['Scenario', 'Rodada'])

        # Salva o CSV organizado (Delimitador padrão para compatibilidade)
        csv_path = os.path.join(output_dir, "round_performance_summary.csv")
        df.to_csv(csv_path, index=False, sep=',')
        print(f"✅ CSV Intermediário Caliper Organizado: {csv_path}")

        # Geração do LaTeX detalhado (Padrão Unificado: todas as rodadas + linha de resumo plana)
        tex_path = os.path.join(output_dir, "round_performance_summary.tex")
        with open(tex_path, 'w') as f:
            f.write("\\begin{table}[ht]\n\\centering\n")
            f.write("\\caption{Resumo Detalhado de Desempenho das Rodadas - Caliper}\n")
            f.write("\\label{tab:caliper_detailed_rounds}\n")
            f.write("\\begin{tabular}{lrrrrr}\n\\toprule\n")
            f.write("Cenário & Amostras & Sucesso & Falha & Latência Média (s) & TPS \\\\\n\\midrule\n")

            for scenario in df['Scenario'].unique():
                sub = df[df['Scenario'] == scenario]
                
                # 1. Escreve as 32 rodadas individuais
                for _, row in sub.iterrows():
                    f.write(f"{row['Scenario']} & {int(row['Samples'])} & {int(row['Successful'])} & "
                            f"{int(row['Failed'])} & {row['Avg Latency (s)']:.3f} & {row['Throughput (TPS)']:.2f} \\\\\n")
                
                # 2. Cálculo do resumo: SOMA das transações e MÉDIA das taxas
                total_samples = sub['Samples'].sum()
                total_succ = sub['Successful'].sum()
                total_fail = sub['Failed'].sum()
                mean_lat = sub['Avg Latency (s)'].mean()
                mean_tps = sub['Throughput (TPS)'].mean()

                # 3. Insere a linha de Resumo plana (sem bold ou midrule extra conforme solicitado)
                f.write(f"{scenario} & {int(total_samples)} & {int(total_succ)} & "
                        f"{int(total_fail)} & {mean_lat:.3f} & {mean_tps:.3f} \\\\\n")
                
                # Adiciona um divisor apenas entre blocos de diferentes cenários, se houver próximo
                f.write("\\midrule\n")

            f.write("\\bottomrule\n\\end{tabular}\n\\end{table}\n")
        
        print(f"✅ Tabela LaTeX Caliper Gerada: {tex_path}")
    else:
        print("⚠️ Nenhum dado Caliper extraído para gerar tabelas.")

if __name__ == "__main__":
    main()
