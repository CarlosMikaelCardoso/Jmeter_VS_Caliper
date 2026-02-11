import os
import sys
import pandas as pd
import matplotlib.pyplot as plt
import glob
import re

def plot_cpu(input_dir, output_dir):
    """Lê os logs de CPU e gera gráfico de Média de Uso por Rodada"""
    files = glob.glob(os.path.join(input_dir, "host_cpu_*.log"))
    
    if not files:
        print("⚠️  Sem logs de CPU para gerar gráfico.")
        return

    data = []
    
    for f in files:
        # Extrai rodada do nome (ex: host_cpu_round_5.log)
        match = re.search(r'round_(\d+)', os.path.basename(f))
        round_num = int(match.group(1)) if match else 0
        
        try:
            # Lê o arquivo linha a linha para achar a média da CPU 'all'
            vals = []
            with open(f, 'r') as file:
                for line in file:
                    if "all" in line and "Average" not in line and "Média" not in line:
                        parts = line.split()
                        try:
                            # Tenta achar a coluna %user (geralmente índice 2 ou 3)
                            # Formato: Hora CPU %user ...
                            idx_all = parts.index("all")
                            # Pega o próximo valor
                            user_val = float(parts[idx_all+1].replace(',', '.'))
                            vals.append(user_val)
                        except:
                            continue
            
            if vals:
                mean_val = sum(vals) / len(vals)
                data.append({'Rodada': round_num, 'CPU_User_Avg': mean_val})

        except Exception as e:
            print(f"Erro lendo {f}: {e}")

    if not data:
        return

    df = pd.DataFrame(data).sort_values(by="Rodada")
    
    # Plota o gráfico
    plt.style.use('ggplot')
    plt.figure(figsize=(10, 6))
    plt.plot(df['Rodada'], df['CPU_User_Avg'], color='#e67e22', marker='o', linewidth=2)
    
    plt.title('Consumo Médio de CPU (%user) ao longo das 32 Rodadas')
    plt.xlabel('Número da Rodada')
    plt.ylabel('% de Uso da CPU (User)')
    plt.ylim(0, 100)
    plt.grid(True)
    
    output_file = os.path.join(output_dir, 'grafico_cpu_consolidado.png')
    plt.savefig(output_file)
    plt.close()
    print(f"✅ Gráfico de CPU gerado: {output_file}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Uso: python3 generate_cpu_chart.py <input_dir> <output_dir>")
        sys.exit(1)
    
    plot_cpu(sys.argv[1], sys.argv[2])