import pandas as pd
import matplotlib.pyplot as plt
import os
import sys
import glob
import re

# Cores para os containers
NODE_COLORS = {
    'orderer': '#1f77b4', 'orderer2': '#17becf', 'orderer3': '#bcbd22', 'orderer4': '#7f7f7f', 'orderer5': '#e377c2',
    'peer0.org1': '#ff7f0e', 'peer0.org2': '#2ca02c', 
    'couchdb0': '#d62728', 'couchdb1': '#9467bd',
}

def parse_caliper_log(log_file, round_name):
    """ Lê log de texto do Caliper e extrai tabela via Regex. """
    try:
        with open(log_file, 'r') as f: content = f.read()
    except: return None

    # Regex para capturar linha de valores da tabela do Caliper
    regex = r"\|\s*" + re.escape(round_name) + r"\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*([\d\.]+)\s*TPS\s*\|\s*([\d\.]+)\s*s\s*\|\s*([\d\.]+)\s*s\s*\|\s*([\d\.]+)\s*s\s*\|\s*([\d\.]+)\s*s"
    match = re.search(regex, content, re.IGNORECASE)

    if match:
        return {
            'Succ': int(match.group(1)),
            'Fail': int(match.group(2)),
            'Avg Latency (s)': float(match.group(6)),
            'Throughput (TPS)': float(match.group(7)) # Pega a última coluna (Throughput)
        }
    return None

def analyze_docker_stats(stats_file):
    """ Lê log Docker (JSON/CSV) com proteção contra arquivos vazios. """
    try:
        if not os.path.exists(stats_file) or os.stat(stats_file).st_size == 0:
            return None
        
        try: df = pd.read_json(stats_file)
        except ValueError:
            try: df = pd.read_csv(stats_file)
            except: return None
            
        if df.empty: return None

        # Limpeza
        for col in ['cpu', 'mem']:
            if col in df.columns and df[col].dtype == object:
                df[col] = df[col].astype(str).str.replace('%', '').str.replace('MiB', '').str.replace('KB', '').str.replace('B', '')
                df[col] = pd.to_numeric(df[col], errors='coerce').fillna(0)
        
        return df
    except: return None

def plot_summary_table(summary_data, title, output_path):
    """ Gera Tabela de Resumo como Imagem PNG. """
    if not summary_data: return

    metrics = [
        ['Sucesso', f"{int(summary_data['Succ'])}"],
        ['Falhas', f"{int(summary_data['Fail'])}"],
        ['Latência Média', f"{summary_data['Avg Latency (s)']:.3f} s"],
        ['Throughput (TPS)', f"{summary_data['Throughput (TPS)']:.2f}"]
    ]
    
    df = pd.DataFrame(metrics, columns=['Métrica', 'Valor'])
    
    fig, ax = plt.subplots(figsize=(5, 3))
    ax.axis('tight')
    ax.axis('off')
    
    table = ax.table(cellText=df.values, colLabels=df.columns, loc='center', cellLoc='left')
    table.scale(1.2, 1.5)
    table.auto_set_font_size(False)
    table.set_fontsize(11)
    
    plt.title(f"Resumo - {title}", fontsize=13, weight='bold')
    plt.savefig(os.path.join(output_path, f"summary_table_{title.lower()}.png"), bbox_inches='tight', dpi=150)
    plt.close()

def plot_resource_bar(df, title, resource, unit, output_path):
    """ Gera Gráfico de Barras para CPU ou Memória. """
    if df.empty or resource not in df.columns: return

    summary = df.groupby('container')[resource].mean().sort_values()
    colors = [NODE_COLORS.get(c, '#555') for c in summary.index]

    plt.figure(figsize=(8, 5))
    bars = plt.bar(summary.index, summary.values, color=colors, alpha=0.9)
    
    plt.title(f'Média de Uso: {resource.upper()} - {title}')
    plt.ylabel(unit)
    plt.xlabel('Container')
    plt.xticks(rotation=45, ha='right')
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.bar_label(bars, fmt='%.1f', padding=3)
    
    plt.tight_layout()
    plt.savefig(os.path.join(output_path, f"bar_{resource}_{title.lower()}.png"), dpi=150)
    plt.close()

def main():
    if len(sys.argv) < 2:
        print("Uso: python generateGraphsCaliper.py <pasta_da_rodada>")
        sys.exit(1)

    results_dir = sys.argv[1]
    graphs_dir = os.path.join(results_dir, "graphs")
    os.makedirs(graphs_dir, exist_ok=True)
    print(f"--- Gerando gráficos Caliper simplificados em: {graphs_dir} ---")

    rounds = ["Open", "Query", "Transfer"]
    
    for round_name in rounds:
        # 1. Performance (Logs Caliper)
        log_pattern = os.path.join(results_dir, f"caliper_{round_name.lower()}*.log")
        log_files = glob.glob(log_pattern)
        
        all_perf = []
        if log_files:
            print(f"  -> Processando Performance: {round_name}")
            for f in log_files:
                perf = parse_caliper_log(f, round_name)
                if perf: all_perf.append(perf)

        # 2. Recursos (Docker Stats)
        stats_pattern = os.path.join(results_dir, f"docker_stats_{round_name.lower()}*")
        stats_files = glob.glob(stats_pattern)
        
        all_docker = []
        if stats_files:
            # print(f"  -> Processando Recursos: {round_name}")
            for f in stats_files:
                df = analyze_docker_stats(f)
                if df is not None: all_docker.append(df)

        # 3. Gerar Saídas (Apenas Summary e CPU/Mem)
        if all_perf:
            # Caliper geralmente é um arquivo só por rodada, pegamos o primeiro
            plot_summary_table(all_perf[0], round_name, graphs_dir)

        if all_docker:
            full_df = pd.concat(all_docker, ignore_index=True)
            plot_resource_bar(full_df, round_name, 'cpu', '% CPU', graphs_dir)
            plot_resource_bar(full_df, round_name, 'mem', 'MiB Mem', graphs_dir)

    print("Concluído.")

if __name__ == "__main__":
    main()