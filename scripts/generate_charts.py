import os
import sys
import pandas as pd
import matplotlib.pyplot as plt
import glob
import re

def plot_performance(df, output_dir, tool_name):
    """Gera gráficos de TPS e Latência por Rodada"""
    # Garante ordenação
    df = df.sort_values(by="Rodada")
    
    scenarios = df['Scenario'].unique()
    
    # Configurações visuais
    plt.style.use('ggplot')
    
    # 1. Gráfico de TPS
    plt.figure(figsize=(10, 6))
    for scen in scenarios:
        subset = df[df['Scenario'] == scen]
        plt.plot(subset['Rodada'], subset['Throughput (TPS)'], marker='o', label=scen)
    
    plt.title(f'Vazão por Rodada - {tool_name}')
    plt.xlabel('Rodada')
    plt.ylabel('Transações por Segundo (TPS)')
    plt.legend()
    plt.grid(True)
    plt.savefig(os.path.join(output_dir, f'chart_throughput_{tool_name.lower()}.png'))
    plt.close()

    # 2. Gráfico de Latência
    plt.figure(figsize=(10, 6))
    for scen in scenarios:
        subset = df[df['Scenario'] == scen]
        plt.plot(subset['Rodada'], subset['Avg Latency (s)'], marker='s', linestyle='--', label=scen)
    
    plt.title(f'Latência Média por Rodada - {tool_name}')
    plt.xlabel('Rodada')
    plt.ylabel('Latência (segundos)')
    plt.legend()
    plt.grid(True)
    plt.savefig(os.path.join(output_dir, f'chart_latency_{tool_name.lower()}.png'))
    plt.close()
    
    print(f"✅ Gráficos de Desempenho gerados em {output_dir}")

def plot_cpu(cpu_files, output_dir):
    """Lê os logs de CPU e gera gráfico de Média de Uso por Rodada"""
    data = []
    
    for f in cpu_files:
        # Extrai rodada do nome
        match = re.search(r'round_(\d+)', os.path.basename(f))
        round_num = int(match.group(1)) if match else 0
        
        # Calcula média do arquivo
        try:
            # Lê ignorando cabeçalhos complexos, foca na coluna %user
            # Assumindo formato SAR padrão: Hora CPU %user ...
            # Se tiver vírgula, troca por ponto
            df_log = pd.read_csv(f, sep=r'\s+', header=None, comment='L', on_bad_lines='skip')
            
            # Filtra linhas onde a coluna 1 é 'all' (ou ajusta conforme seu sar)
            # Geralmente: Col 0=Hora, Col 1=CPU(all), Col 2=%user
            # Vamos tentar ser flexíveis
            
            # Lendo como texto puro para garantir
            with open(f, 'r') as file:
                vals = []
                for line in file:
                    if "all" in line:
                        parts = line.split()
                        # Pega o valor logo após 'all'
                        try:
                            idx = parts.index("all")
                            user_val = float(parts[idx+1].replace(',', '.'))
                            vals.append(user_val)
                        except:
                            continue
                
                if vals:
                    mean_val = sum(vals) / len(vals)
                    data.append({'Rodada': round_num, 'CPU_User_Avg': mean_val})

        except Exception as e:
            print(f"Erro lendo CPU log {f}: {e}")

    if not data:
        print("⚠️  Sem dados de CPU para gerar gráfico.")
        return

    df = pd.DataFrame(data).sort_values(by="Rodada")
    
    plt.figure(figsize=(10, 6))
    plt.plot(df['Rodada'], df['CPU_User_Avg'], color='purple', marker='^')
    plt.title('Consumo Médio de CPU (%user) por Rodada')
    plt.xlabel('Rodada')
    plt.ylabel('% CPU Usuário')
    plt.ylim(0, 100) # CPU vai de 0 a 100
    plt.grid(True)
    plt.savefig(os.path.join(output_dir, 'chart_host_cpu.png'))
    plt.close()
    print(f"✅ Gráfico de CPU gerado em {output_dir}")

def main():
    if len(sys.argv) < 3:
        print("Uso: python3 generate_charts.py <pasta_dados> <pasta_saida> <tool_name>")
        sys.exit(1)

    input_dir = sys.argv[1]
    output_dir = sys.argv[2]
    tool_name = sys.argv[3] # "JMeter" ou "Caliper"

    # 1. Lê o CSV consolidado de performance (gerado pelos scripts anteriores)
    # Procura por round_performance_summary.csv na pasta de graficos ou temp
    perf_csv = os.path.join(input_dir, "graphs", "round_performance_summary.csv")
    if not os.path.exists(perf_csv):
        # Tenta na raiz do temp
        perf_csv = os.path.join(input_dir, "round_performance_summary.csv")
    
    if os.path.exists(perf_csv):
        try:
            df = pd.read_csv(perf_csv)
            plot_performance(df, output_dir, tool_name)
        except Exception as e:
            print(f"Erro ao plotar desempenho: {e}")
    else:
        print(f"⚠️  CSV de desempenho não encontrado: {perf_csv}")

    # 2. Lê logs de CPU para gerar gráfico
    cpu_files = glob.glob(os.path.join(input_dir, "host_cpu_round_*.log"))
    if cpu_files:
        plot_cpu(cpu_files, output_dir)

if __name__ == "__main__":
    main()