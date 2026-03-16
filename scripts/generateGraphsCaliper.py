import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.cm as cm
import matplotlib
import numpy as np
import os
import sys
import glob
import re

try:
    import scienceplots
    plt.style.use(['science', 'ieee', 'high-vis'])
except:
    plt.style.use('seaborn-v0_8-paper')

def clean_metric(val):
    if isinstance(val, (int, float)): return val
    try: return float(str(val).replace('%', '').replace('MiB', '').replace('KB', '').replace('B', ''))
    except: return 0.0

def natural_sort_key(name):
    name = str(name).lower()
    if 'orderer' in name: priority = 0
    elif 'peer' in name:  priority = 1
    elif 'couch' in name: priority = 2
    else: priority = 3
    numbers = tuple(int(s) for s in re.findall(r'\d+', name))
    return (priority, numbers, name)

def remove_ansi_colors(text):
    ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    return ansi_escape.sub('', text)

def parse_caliper_log(log_file, round_name):
    try:
        with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
            content = remove_ansi_colors(f.read())
        
        target_name = round_name.lower()
        for line in content.splitlines():
            line_lower = line.lower()
            if f"| {target_name} " in line_lower or f"|{target_name}|" in line_lower:
                parts = [p.strip() for p in line.split('|')]
                if len(parts) >= 9:
                    try:
                        # Limpa caracteres não numéricos
                        def get_num(s): return float(re.sub(r'[^\d\.]', '', s) or 0)
                        
                        return {
                            'Scenario': round_name,
                            'Samples': int(get_num(parts[2]) + get_num(parts[3])), # Succ + Fail
                            'Success': int(get_num(parts[2])),
                            'Fail': int(get_num(parts[3])),
                            'Avg Latency (s)': get_num(parts[7]),
                            'TPS': get_num(parts[8])
                        }
                    except: pass
    except: pass
    return None

def analyze_docker_stats(stats_file):
    try:
        if not os.path.exists(stats_file) or os.stat(stats_file).st_size == 0: return None
        df = None
        if stats_file.endswith('.json'):
            try: df = pd.read_json(stats_file)
            except ValueError:
                try: df = pd.read_json(stats_file, lines=True)
                except: pass
        if df is None:
            try: df = pd.read_csv(stats_file)
            except: return None
        if df is None or df.empty: return None

        df.columns = df.columns.str.lower()
        rename_map = {'cpu %': 'cpu', 'mem usage': 'mem', 'memory': 'mem', 'name': 'container'}
        df.rename(columns=rename_map, inplace=True)
        if 'cpu' in df.columns and 'mem' in df.columns:
            df['cpu'] = df['cpu'].apply(clean_metric)
            df['mem'] = df['mem'].apply(clean_metric)
            return df
    except: return None

def plot_combined_table(summary_list, output_path):
    if not summary_list: return
    df = pd.DataFrame(summary_list)
    
    df.to_csv(os.path.join(output_path, "round_performance_summary.csv"), index=False, float_format="%.4f")
    
    latex_code = df.to_latex(index=False, float_format="%.3f", caption="Caliper Performance Summary", label="tab:caliper_round")
    with open(os.path.join(output_path, "round_performance_summary.tex"), "w") as f: f.write(latex_code)

    fig, ax = plt.subplots(figsize=(8, 3))
    ax.axis('tight'); ax.axis('off')
    
    cell_text = []
    for row in df.values:
        cell_text.append([str(row[0]), str(int(row[1])), str(int(row[2])), str(int(row[3])), f"{row[4]:.3f}", f"{row[5]:.2f}"])

    table = ax.table(cellText=cell_text, colLabels=df.columns, loc='center', cellLoc='center')
    table.auto_set_font_size(False); table.set_fontsize(10); table.scale(1.2, 1.5)
    plt.title("Resumo de Desempenho (Rodada)", fontsize=14, weight='bold')
    plt.savefig(os.path.join(output_path, "round_performance_summary.png"), bbox_inches='tight', dpi=150)
    plt.close()

def plot_resource_charts(df, scenario, output_path):
    if df.empty: return
    summary = df.groupby('container')[['cpu', 'mem']].mean()
    valid_indices = [c for c in summary.index if any(x in c.lower() for x in ['orderer', 'peer', 'couch'])]
    if not valid_indices: return
    summary = summary.loc[valid_indices]
    
    summary['sort_key'] = summary.index.map(natural_sort_key)
    summary = summary.sort_values('sort_key')
    
    num_bars = len(summary)
    try: cmap = matplotlib.colormaps['tab20']
    except: cmap = plt.get_cmap('tab20')
    colors = cmap(np.linspace(0, 1, max(num_bars, 2)))[:num_bars]

    # CPU
    plt.figure(figsize=(8, 5))
    bars = plt.bar(summary.index, summary['cpu'], color=colors, alpha=0.9, edgecolor='black', linewidth=0.5)
    plt.ylabel('CPU Média (Porcentagem)'); plt.title(f'Uso de CPU - {scenario}')
    plt.xticks(rotation=45, ha='right', fontsize=9); plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.ylim(0, summary['cpu'].max() * 1.3 if summary['cpu'].max() > 0 else 10)
    plt.bar_label(bars, labels=[f"{v:.2f}%" for v in summary['cpu']], padding=3, fontsize=8)
    plt.tight_layout()
    plt.savefig(os.path.join(output_path, f"bar_cpu_{scenario.lower()}.pdf")) # PDF
    plt.close()

    # Memória
    plt.figure(figsize=(8, 5))
    bars = plt.bar(summary.index, summary['mem'], color=colors, alpha=0.9, edgecolor='black', linewidth=0.5)
    plt.ylabel('Memória Média (MiB)'); plt.title(f'Uso de Memória - {scenario}')
    plt.xticks(rotation=45, ha='right', fontsize=9); plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.ylim(0, summary['mem'].max() * 1.3 if summary['mem'].max() > 0 else 100)
    plt.bar_label(bars, labels=[f"{v:.1f}" for v in summary['mem']], padding=3, fontsize=8)
    plt.tight_layout()
    plt.savefig(os.path.join(output_path, f"bar_mem_{scenario.lower()}.pdf"))
    plt.close()

def main():
    if len(sys.argv) < 2:
        print("Uso: python generateGraphsCaliper.py <pasta_da_rodada>")
        sys.exit(1)

    results_dir = sys.argv[1]
    graphs_dir = os.path.join(results_dir, "graphs")
    os.makedirs(graphs_dir, exist_ok=True)
    print(f"--- Processando Caliper em: {graphs_dir} ---")

    rounds = ["Open", "Query", "Transfer"]
    summary_list = []

    for round_name in rounds:
        # 1. Performance
        files = glob.glob(os.path.join(results_dir, f"caliper*{round_name.lower()}*.log"))
        files += glob.glob(os.path.join(results_dir, f"caliper*{round_name.lower()}*.txt"))
        if not files: # Busca fallback
            files = glob.glob(os.path.join(results_dir, f"*run_*.txt"))
            files += glob.glob(os.path.join(results_dir, f"*run_*.log"))

        for f in files:
            perf = parse_caliper_log(f, round_name)
            if perf: 
                summary_list.append(perf)
                break # Pega apenas o primeiro arquivo válido por rodada para não duplicar

        # 2. Recursos
        stats_files = glob.glob(os.path.join(results_dir, f"docker_stats_{round_name.lower()}*"))
        docker_dfs = []
        for f in stats_files:
            df = analyze_docker_stats(f)
            if df is not None: docker_dfs.append(df)
        
        if docker_dfs:
            full_df = pd.concat(docker_dfs, ignore_index=True)
            plot_resource_charts(full_df, round_name, graphs_dir)

    if summary_list:
        plot_combined_table(summary_list, graphs_dir)
        print("✅ Tabelas e Gráficos Caliper gerados com sucesso.")
    else:
        print("⚠️  Nenhum dado Caliper encontrado.")

if __name__ == "__main__":
    main()