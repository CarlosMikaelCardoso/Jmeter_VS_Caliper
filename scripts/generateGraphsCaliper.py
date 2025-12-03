import pandas as pd
import matplotlib.pyplot as plt
import os
import sys
import glob
import re

# Cores para os containers do Fabric (baseado nos nomes corrigidos do monitor-api.js)
NODE_COLORS = {
    'orderer': '#1f77b4',      # Azul
    'orderer2': '#17becf',     # Ciano
    'orderer3': '#bcbd22',     # Amarelo
    'orderer4': '#7f7f7f',     # Cinza
    'orderer5': '#ff9896',     # Salmão
    'peer0.org1': '#ff7f0e',   # Laranja
    'peer0.org2': '#2ca02c',   # Verde
    'couchdb0': '#d62728',     # Vermelho
    'couchdb1': '#9467bd',     # Roxo
    # Adicionando cores para Org3 caso exista
    'peer0.org3': '#8c564b',   # Marrom
    'couchdb2': '#e377c2',     # Rosa
}

def parse_caliper_log(log_file, round_name):
    """
    Lê um ficheiro de log de performance (stdout) do Caliper e extrai a tabela de resultados.
    """
    try:
        with open(log_file, 'r') as f:
            content = f.read()
    except Exception as e:
        print(f"  -> Erro ao ler o ficheiro de log {log_file}: {e}")
        return None

    performance_data = []
    # Procura pela tabela de resultados de performance
    perf_match = re.search(r'### Test result ###\s*.*?Name\s*\| Succ.*?\n(.*?)\n\+--[+\-]*--', content, re.S)
    
    if perf_match:
        perf_table_str = perf_match.group(1)
        perf_lines = [line.strip() for line in perf_table_str.strip().split('\n') if '|' in line and '------' not in line]
        for line in perf_lines:
            parts = [p.strip() for p in line.split('|') if p.strip()]
            if len(parts) == 8: 
                # Adiciona o nome da rodada (Open, Query, Transfer) e o label (parts[0])
                performance_data.append([round_name] + parts)
    
    if not performance_data:
        print(f"  -> Aviso: Tabela 'Test result' não encontrada em {os.path.basename(log_file)}")
        return None
        
    perf_df = pd.DataFrame(performance_data, columns=['Round', 'Name', 'Succ', 'Fail', 'Send Rate (TPS)', 'Max Latency (s)', 'Min Latency (s)', 'Avg Latency (s)', 'Throughput (TPS)'])
    
    # Converte colunas para numérico
    for col in perf_df.columns[2:]: 
        perf_df[col] = pd.to_numeric(perf_df[col], errors='coerce')

    return perf_df

def analyze_docker_stats(stats_file):
    """
    Lê um ficheiro de log do Docker (docker_stats_*.log) e retorna um DataFrame.
    Esta função espera um CSV COM cabeçalho, conforme gerado pelo monitor-api.js.
    """
    try:
        # A API escreve um cabeçalho
        df = pd.read_csv(stats_file)
        
        # Limpa os dados
        df['cpu'] = df['cpu'].str.replace('%', '').astype(float)
        df['mem'] = df['mem'].str.replace('MiB', '').astype(float)
        df['net_rx'] = df['net_rx'].str.replace('KB', '').astype(float)
        df['net_tx'] = df['net_tx'].str.replace('KB', '').astype(float)
        df['disk_r'] = df['disk_r'].str.replace('KB', '').astype(float)
        df['disk_w'] = df['disk_w'].str.replace('KB', '').astype(float)
        
        # Adiciona uma coluna de tempo para os gráficos de linha
        df['time'] = df.groupby('container').cumcount() + 1
        return df
    except Exception as e:
        print(f"  -> Erro ao ler o ficheiro de estatísticas do Docker {stats_file}: {e}")
        return None

def plot_summary_table_from_dict(summary_data, title, output_path):
    """
    Gera e guarda uma tabela com métricas de resumo consolidadas a partir de um dicionário.
    """
    summary_df = pd.DataFrame(summary_data)
    
    fig, ax = plt.subplots(figsize=(6, 4))
    ax.axis('tight')
    ax.axis('off')
    table = ax.table(cellText=summary_df.values, colLabels=summary_df.columns, loc='center', cellLoc='center')
    table.auto_set_font_size(False)
    table.set_fontsize(14)
    table.scale(1.2, 1.5)
    plt.title(f'Resumo Consolidado - {title}', fontsize=18, y=0.95)

    # Adicionado '_caliper_' ao nome do arquivo para evitar colisão
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_caliper_summary_table_{title.lower()}.png"), bbox_inches='tight', pad_inches=0.1)
    plt.close()
    
def plot_resource_bar_charts(df, title, resource_name, unit, output_path):
    """
    Gera gráficos de barras para o uso médio e máximo de um recurso.
    """
    if df.empty:
        print(f"  -> Aviso: DataFrame de recursos vazio para {title}, pulando gráficos de barras de {resource_name}.")
        return

    summary = df.groupby('container')[resource_name].agg(['mean', 'max']).reset_index()
    summary = summary.sort_values(by='container').set_index('container')
    
    # Garante que apenas os containers presentes nos dados sejam plotados
    valid_containers = [c for c in summary.index if c in NODE_COLORS]
    
    # Se o summary não contiver nenhum container conhecido, saia
    if not valid_containers:
        print(f"  -> Aviso: Nenhum container conhecido (ex: peer0.org1) encontrado para gráficos de barras de {resource_name} em {title}.")
        return
        
    summary = summary.loc[valid_containers]
    colors = [NODE_COLORS.get(node) for node in summary.index]

    plt.figure(figsize=(10, 6))
    bars = plt.bar(summary.index, summary['mean'], color=colors)
    plt.title(f'Uso Médio de {resource_name.upper()} por Nó - {title}')
    plt.ylabel(f'Uso Médio ({unit})')
    plt.xlabel('Nó')
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    plt.bar_label(bars, fmt='%.2f')
    # Adicionado '_caliper_' ao nome do arquivo
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_caliper_avg_{resource_name}_usage_{title.lower()}.png"))
    plt.close()

    plt.figure(figsize=(10, 6))
    bars = plt.bar(summary.index, summary['max'], color=colors)
    plt.title(f'Uso Máximo de {resource_name.upper()} por Nó - {title}')
    plt.ylabel(f'Uso Máximo ({unit})')
    plt.xlabel('Nó')
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    plt.bar_label(bars, fmt='%.2f')
    # Adicionado '_caliper_' ao nome do arquivo
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_caliper_max_{resource_name}_usage_{title.lower()}.png"))
    plt.close()

def plot_resource_line_chart(df, title, column, y_label, output_path):
    """
    Função para gerar gráficos de linha para Rede e Disco.
    """
    if df.empty:
        print(f"  -> Aviso: DataFrame de recursos vazio para {title}, pulando gráfico de linha de {column}.")
        return
        
    plt.figure(figsize=(15, 7))
    
    # Garante que apenas os containers conhecidos sejam plotados
    valid_containers = sorted([c for c in df['container'].unique() if c in NODE_COLORS])
    
    if not valid_containers:
        print(f"  -> Aviso: Nenhum container conhecido encontrado para gráfico de linha de {column} em {title}.")
        plt.close()
        return

    for container in valid_containers:
        container_df = df[df['container'] == container]
        color = NODE_COLORS.get(container)
        plt.plot(container_df['time'], container_df[column], label=container, color=color, alpha=0.8, marker='.', linestyle='-')
        
    plt.title(f'{y_label} ao Longo do Tempo - {title}')
    plt.xlabel('Tempo (intervalos de 5s)')
    plt.ylabel(y_label)
    plt.grid(True)
    handles, labels = plt.gca().get_legend_handles_labels()
    order = [labels.index(s) for s in valid_containers]
    plt.legend([handles[idx] for idx in order],[labels[idx] for idx in order])
    # Adicionado '_caliper_' ao nome do arquivo
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_caliper_{column}_usage_{title.lower()}.png"))
    plt.close()

def main():
    if len(sys.argv) < 3:
        print("Uso: python generateGraphsCaliper.py <diretório_de_resultados> <numero_de_repeticoes>")
        sys.exit(1)

    results_dir = sys.argv[1]
    num_repetitions = int(sys.argv[2])
    # As rodadas são definidas no run_caliper.sh
    rounds = ["Open", "Query", "Transfer"]
    
    print(f"\n--- Gerando gráficos consolidados para os resultados em: {results_dir} ---")

    all_perf_dfs = []
    all_docker_dfs = []

    for round_name in rounds:
        print(f"\n--- Processando Rodada: {round_name} ---")
        
        # 1. Processar Logs de Performance (caliper_log_*.txt)
        perf_files = glob.glob(os.path.join(results_dir, f"caliper_log_{round_name.lower()}_run_*.txt"))
        if not perf_files:
            print(f"Aviso: Nenhum ficheiro de log de performance (caliper_log_...) encontrado para '{round_name}'.")
        
        for f in perf_files:
            # Passa o NOME DA RODADA (Open, Query, Transfer) para o parser
            perf_df = parse_caliper_log(f, round_name)
            if perf_df is not None:
                all_perf_dfs.append(perf_df)

        # 2. Processar Logs de Recursos (docker_stats_*.log)
        stats_files = glob.glob(os.path.join(results_dir, f"docker_stats_{round_name.lower()}_run_*.log"))
        if not stats_files:
            print(f"Aviso: Nenhum ficheiro de estatísticas do Docker (docker_stats_...) encontrado para '{round_name}'.")

        for f in stats_files:
            docker_df = analyze_docker_stats(f)
            if docker_df is not None:
                # Adiciona o nome da rodada para agrupar depois
                docker_df['round'] = round_name 
                all_docker_dfs.append(docker_df)

    # 3. Consolidar e Plotar Performance
    if all_perf_dfs:
        consolidated_perf_df = pd.concat(all_perf_dfs, ignore_index=True)

        # --- CORREÇÃO DE LÓGICA ---
        # Agrega os resultados de performance (média das médias das N execuções)
        # Agrupamos por 'Round' (Open, Query, Transfer) que nós definimos, 
        # em vez de 'Name' (label) que vem do log e pode estar errado.
        agg_rules = {
            'Succ': 'sum', 'Fail': 'sum', 'Send Rate (TPS)': 'mean',
            'Max Latency (s)': 'mean', 'Min Latency (s)': 'mean',
            'Avg Latency (s)': 'mean', 'Throughput (TPS)': 'mean'
        }
        final_perf_summary = consolidated_perf_df.groupby('Round').agg(agg_rules).reset_index()
        # --- FIM DA CORREÇÃO ---

        print("\n--- Resumo de Performance Consolidado (Total de {} execuções) ---".format(num_repetitions))
        print(final_perf_summary.to_string())

        # Loop corrigido para usar a coluna 'Round'
        for _, row in final_perf_summary.iterrows():
            summary_data = {
                'Métricas': [
                    'Total de Amostras', 'Sucesso', 'Falha', 
                    'Latência Média (s)', 'Latência Mínima (s)', 'Latência Máxima (s)', 
                    'Throughput Médio (TPS)'
                ],
                'Valor': [
                    f"{(row['Succ'] + row['Fail']):.0f}",
                    f"{row['Succ']:.0f}",
                    f"{row['Fail']:.0f}",
                    f"{row['Avg Latency (s)']:.2f}",
                    f"{row['Min Latency (s)']:.2f}",
                    f"{row['Max Latency (s)']:.2f}",
                    f"{row['Throughput (TPS)']:.2f}"
                ]
            }
            # Usa o nome da 'Round' para o título e nome do arquivo
            plot_summary_table_from_dict(summary_data, row['Round'].capitalize(), results_dir)
        print("Tabelas de resumo de performance geradas.")

    # 4. Consolidar e Plotar Recursos
    if all_docker_dfs:
        consolidated_docker_df = pd.concat(all_docker_dfs, ignore_index=True)
        
        # Gera gráficos de recursos para cada rodada
        for round_name in rounds:
            round_docker_data = consolidated_docker_df[consolidated_docker_df['round'] == round_name]
            if not round_docker_data.empty:
                print(f"Gerando gráficos de recursos para a rodada: {round_name}")
                
                # Gráficos de Barras (Médio/Máximo)
                plot_resource_bar_charts(round_docker_data, round_name, 'cpu', '%', results_dir)
                plot_resource_bar_charts(round_docker_data, round_name, 'mem', 'MiB', results_dir)
                
                # Gráficos de Linha (Ao longo do tempo)
                round_docker_data['net_io'] = round_docker_data['net_rx'] + round_docker_data['net_tx']
                plot_resource_line_chart(round_docker_data, round_name, 'net_io', 'I/O de Rede Consolidado (KB/s)', results_dir)
                
                round_docker_data['disk_io'] = round_docker_data['disk_r'] + round_docker_data['disk_w']
                plot_resource_line_chart(round_docker_data, round_name, 'disk_io', 'I/O de Disco Consolidado (KB/s)', results_dir)
        print("Gráficos de recursos gerados.")
    
    print("\nProcesso de geração de gráficos concluído!")

if __name__ == "__main__":
    main()