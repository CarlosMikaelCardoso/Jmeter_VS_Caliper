import os
import sys
import pandas as pd
import glob
import re

def parse_cpu_log(filepath):
    """
    Lê log do SAR. Formato esperado:
    HH:MM:SS all %user %nice %system ...
    Trata vírgula como decimal.
    """
    data = []
    try:
        with open(filepath, 'r') as f:
            for line in f:
                # Ignora cabeçalhos e linhas em branco
                if not line.strip() or "Linux" in line or "CPU" in line or "Average" in line or "Média" in line:
                    continue
                
                parts = line.split()
                # Valida se é uma linha de dados da CPU 'all'
                if len(parts) > 3 and parts[1] == "all":
                    # Coluna %user é geralmente o índice 2 (0=Hora, 1=CPU, 2=%user)
                    user_str = parts[2].replace(',', '.')
                    try:
                        val = float(user_str)
                        data.append(val)
                    except ValueError:
                        continue
        
        if not data:
            return None

        s = pd.Series(data)
        return {
            "mean": s.mean(),
            "max": s.max(),
            "std": s.std()
        }
    except Exception as e:
        print(f"Erro lendo {filepath}: {e}")
        return None

def main():
    if len(sys.argv) < 3:
        print("Uso: python3 gen_table_host_cpu.py <pasta_entrada> <arquivo_saida_csv>")
        sys.exit(1)

    input_dir = sys.argv[1]
    output_csv = sys.argv[2]
    
    # Busca arquivos copiados pelo shell script
    files = glob.glob(os.path.join(input_dir, "host_cpu_round_*.log"))
    
    if not files:
        print(f"⚠️  Nenhum log de CPU encontrado em {input_dir}")
        return

    results = []
    print(f"--- Processando {len(files)} logs de CPU... ---")

    for f in files:
        # Tenta extrair o número do round do nome do arquivo
        match = re.search(r'round_(\d+)', os.path.basename(f))
        round_num = int(match.group(1)) if match else 0
        
        stats = parse_cpu_log(f)
        if stats:
            results.append({
                "Rodada": round_num,
                "User_Mean": round(stats['mean'], 2),
                "User_Max": round(stats['max'], 2),
                "User_Std": round(stats['std'], 2)
            })

    if results:
        df = pd.DataFrame(results)
        df = df.sort_values(by="Rodada")
        
        # Salva CSV
        df.to_csv(output_csv, index=False)
        print(f"✅ CSV salvo: {output_csv}")
        
        # Gera Tabela LaTeX (útil para seu artigo)
        output_tex = output_csv.replace(".csv", ".tex")
        
        latex_content = df.to_latex(
            index=False,
            caption=f"Consumo de CPU (%user) do Host - {len(results)} Rodadas",
            label="tab:cpu_usage",
            column_format="c c c c"
        )
        
        with open(output_tex, "w") as f:
            f.write(latex_content)
        print(f"✅ LaTeX salvo: {output_tex}")
        
        # Exibe resumo rápido
        print("\nResumo Geral CPU (%user):")
        print(f"Média das Médias: {df['User_Mean'].mean():.2f}%")
        print(f"Pico Máximo Registrado: {df['User_Max'].max():.2f}%")
        
    else:
        print("⚠️  Nenhum dado válido extraído.")

if __name__ == "__main__":
    main()