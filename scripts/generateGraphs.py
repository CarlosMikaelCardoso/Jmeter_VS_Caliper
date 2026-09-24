import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.cm as cm
import matplotlib
import numpy as np
import os
import sys
import glob
import re

# Tenta usar estilo científico sem exigir instalação do TeX/LaTeX no SO
try:
    import scienceplots
    plt.style.use(['science', 'no-latex', 'ieee', 'high-vis'])
except Exception:
    plt.style.use('seaborn-v0_8-paper')
plt.rcParams['text.usetex'] = False

# --- CONFIGURAÇÕES VISUAIS ---
NODE_COLORS = {
    'orderer': '#1f77b4', 'orderer2': '#17becf', 'orderer3': '#bcbd22',
    'peer0.org1': '#ff7f0e', 'peer0.org2': '#2ca02c', 'peer0.org3': '#8c564b',
    'couchdb0': '#d62728', 'couchdb1': '#9467bd', 'couchdb2': '#e377c2'
}

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

def parse_jmeter_jtl(jtl_file, round_name, run_number, backend_errors_df):
    try:
        df = pd.read_csv(jtl_file)
    except: return None
    if df.empty: return None

    jmeter_success = df['success'].sum()
    jmeter_fail = len(df) - jmeter_success
    
    avg_latency_s = df['elapsed'].mean() / 1000.0
    p99_latency_s = df['elapsed'].quantile(0.99) / 1000.0

    start_time = df['timeStamp'].min()
    end_time = (df['timeStamp'] + df['elapsed']).max()
    duration_s = (end_time - start_time) / 1000.0
    throughput_tps = jmeter_success / duration_s if duration_s > 0 else 0

    backend_fail_count = 0
    if not backend_errors_df.empty:
        try:
            matches = backend_errors_df[
                (backend_errors_df['round'] == round_name) & 
                (backend_errors_df['run'] == run_number)
            ]
            if not matches.empty:
                backend_fail_count = matches['count'].sum()
        except: pass

    # Ajuste final
    succ_real = max(0, jmeter_success - backend_fail_count)
    fail_total = jmeter_fail + backend_fail_count
    
    # Recalcula TPS baseado no sucesso real
    tps_real = succ_real / duration_s if duration_s > 0 else 0

    return {
        'Scenario': round_name,
        'Samples': len(df),
        'Success': int(succ_real),
        'Fail': int(fail_total),
        'Avg Latency (s)': avg_latency_s,
        'TPS': tps_real
    }

import logging
logging.getLogger('matplotlib.font_manager').setLevel(logging.ERROR)

def analyze_docker_stats(stats_file):
    try:
        if not os.path.exists(stats_file) or os.stat(stats_file).st_size == 0: return None
        
        df = None
        # Verifica se o arquivo é CSV mesmo com extensão .json
        try:
            with open(stats_file, 'r', errors='ignore') as f:
                first_line = f.readline().strip()
            if 'container' in first_line.lower() or ',' in first_line:
                df = pd.read_csv(stats_file)
        except Exception:
            pass

        if df is None and stats_file.endswith('.json'):
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
    except Exception as e:
        print(f"⚠️ [WARN] Falha ao analisar {stats_file}: {e}")
        return None

def plot_performance_charts(summary_list, output_path):
    """ Gera Gráficos de Desempenho (Throughput TPS e Latência) em PNG e PDF """
    if not summary_list: return
    df = pd.DataFrame(summary_list)
    
    colors = ['#1f77b4', '#2ca02c', '#ff7f0e', '#d62728'][:len(df)]
    
    # 1. Gráfico de Throughput (TPS)
    plt.figure(figsize=(7, 4.5))
    bars = plt.bar(df['Scenario'], df['TPS'], color=colors, alpha=0.9, edgecolor='black', linewidth=0.5)
    plt.ylabel('Throughput (TPS)')
    plt.title('Vazão (TPS) por Cenário')
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    max_tps = df['TPS'].max() if not df['TPS'].empty else 0
    plt.ylim(0, max_tps * 1.25 if max_tps > 0 else 10)
    plt.bar_label(bars, labels=[f"{v:.2f}" for v in df['TPS']], padding=3, fontsize=9)
    plt.tight_layout()
    plt.savefig(os.path.join(output_path, "chart_throughput.png"), bbox_inches='tight', dpi=150)
    plt.savefig(os.path.join(output_path, "chart_throughput.pdf"), bbox_inches='tight')
    plt.close()
    print("  -> Gráfico gerado: chart_throughput.png / .pdf")

    # 2. Gráfico de Latência Média (s)
    plt.figure(figsize=(7, 4.5))
    bars = plt.bar(df['Scenario'], df['Avg Latency (s)'], color=colors, alpha=0.9, edgecolor='black', linewidth=0.5)
    plt.ylabel('Latência Média (s)')
    plt.title('Latência Média por Cenário')
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    max_lat = df['Avg Latency (s)'].max() if not df['Avg Latency (s)'].empty else 0
    plt.ylim(0, max_lat * 1.25 if max_lat > 0 else 1)
    plt.bar_label(bars, labels=[f"{v:.3f}s" for v in df['Avg Latency (s)']], padding=3, fontsize=9)
    plt.tight_layout()
    plt.savefig(os.path.join(output_path, "chart_latency.png"), bbox_inches='tight', dpi=150)
    plt.savefig(os.path.join(output_path, "chart_latency.pdf"), bbox_inches='tight')
    plt.close()
    print("  -> Gráfico gerado: chart_latency.png / .pdf")

def plot_combined_table(summary_list, output_path):
    """ Gera Tabela Unificada (PNG, CSV, LaTeX) """
    if not summary_list: return

    df = pd.DataFrame(summary_list)
    
    # 1. Salva CSV
    csv_file = os.path.join(output_path, "round_performance_summary.csv")
    df.to_csv(csv_file, index=False, float_format="%.4f")
    
    # 2. Salva LaTeX
    try:
        latex_code = df.to_latex(index=False, float_format="%.3f", caption="Round Performance Summary", label="tab:round_perf")
        with open(os.path.join(output_path, "round_performance_summary.tex"), "w") as f: f.write(latex_code)
    except Exception as e:
        print(f"[WARN] Falha ao gerar LaTeX (round_performance_summary.tex): {e}")

    # 3. Salva PNG (Bonito)
    fig, ax = plt.subplots(figsize=(8, 3))
    ax.axis('tight')
    ax.axis('off')
    
    # Formata valores para exibição
    cell_text = []
    for row in df.values:
        fmt_row = [
            str(row[0]), # Scenario
            str(int(row[1])), # Samples
            str(int(row[2])), # Success
            str(int(row[3])), # Fail
            f"{row[4]:.3f}",  # Latency
            f"{row[5]:.2f}"   # TPS
        ]
        cell_text.append(fmt_row)

    table = ax.table(cellText=cell_text, colLabels=df.columns, loc='center', cellLoc='center')
    table.auto_set_font_size(False)
    table.set_fontsize(10)
    table.scale(1.2, 1.5)
    
    plt.title("Resumo de Desempenho (Rodada)", fontsize=14, weight='bold')
    table_img = os.path.join(output_path, "round_performance_summary.png")
    plt.savefig(table_img, bbox_inches='tight', dpi=150)
    plt.close()
    print(f"  -> Tabela gerada: round_performance_summary.png / .csv / .tex")

def plot_resource_charts(df, scenario, output_path):
    """ Gera Gráficos de Recursos V2 (Estilo Consolidado) em PNG e PDF """
    if df.empty: return

    summary = df.groupby('container')[['cpu', 'mem']].mean()
    valid_indices = [c for c in summary.index if any(x in c.lower() for x in ['orderer', 'peer', 'couch'])]
    if not valid_indices:
        valid_indices = list(summary.index)
    if not valid_indices:
        return
        
    summary = summary.loc[valid_indices]
    
    # Ordenação Inteligente
    summary['sort_key'] = summary.index.map(natural_sort_key)
    summary = summary.sort_values('sort_key')
    
    num_bars = len(summary)
    try: cmap = matplotlib.colormaps['tab20']
    except: cmap = plt.get_cmap('tab20')
    colors = cmap(np.linspace(0, 1, max(num_bars, 2)))[:num_bars]

    # CPU
    plt.figure(figsize=(8, 5))
    bars = plt.bar(summary.index, summary['cpu'], color=colors, alpha=0.9, edgecolor='black', linewidth=0.5)
    plt.ylabel('CPU Média (%)'); plt.title(f'Uso de CPU - {scenario}')
    plt.xticks(rotation=45, ha='right', fontsize=9); plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.ylim(0, summary['cpu'].max() * 1.3 if summary['cpu'].max() > 0 else 10)
    plt.bar_label(bars, labels=[f"{v:.2f}%" for v in summary['cpu']], padding=3, fontsize=8)
    plt.tight_layout()
    plt.savefig(os.path.join(output_path, f"bar_cpu_{scenario.lower()}.pdf"), bbox_inches='tight')
    plt.savefig(os.path.join(output_path, f"bar_cpu_{scenario.lower()}.png"), bbox_inches='tight', dpi=150)
    plt.close()
    print(f"  -> Gráfico gerado: bar_cpu_{scenario.lower()}.png / .pdf")

    # Memória
    plt.figure(figsize=(8, 5))
    bars = plt.bar(summary.index, summary['mem'], color=colors, alpha=0.9, edgecolor='black', linewidth=0.5)
    plt.ylabel('Memória Média (MiB)'); plt.title(f'Uso de Memória - {scenario}')
    plt.xticks(rotation=45, ha='right', fontsize=9); plt.grid(axis='y', linestyle='--', alpha=0.3)
    plt.ylim(0, summary['mem'].max() * 1.3 if summary['mem'].max() > 0 else 100)
    plt.bar_label(bars, labels=[f"{v:.1f}" for v in summary['mem']], padding=3, fontsize=8)
    plt.tight_layout()
    plt.savefig(os.path.join(output_path, f"bar_mem_{scenario.lower()}.pdf"), bbox_inches='tight')
    plt.savefig(os.path.join(output_path, f"bar_mem_{scenario.lower()}.png"), bbox_inches='tight', dpi=150)
    plt.close()
    print(f"  -> Gráfico gerado: bar_mem_{scenario.lower()}.png / .pdf")

def main():
    if len(sys.argv) < 2:
        print("Uso: python generateGraphs.py <pasta_da_rodada>")
        sys.exit(1)

    results_dir = sys.argv[1]
    graphs_dir = os.path.join(results_dir, "graphs")
    os.makedirs(graphs_dir, exist_ok=True)
    print(f"--- Processando JMeter em: {graphs_dir} ---")

    rounds = ["Open", "Query", "Transfer"]
    
    # Carrega erros backend
    backend_err_path = os.path.join(os.path.dirname(results_dir), 'backend_errors.log')
    backend_errors_df = pd.DataFrame()
    if os.path.exists(backend_err_path):
        try: backend_errors_df = pd.read_csv(backend_err_path, names=['round', 'run', 'count', 'details'])
        except: pass

    summary_list = []

    for round_name in rounds:
        # 1. Performance
        jtl_files = glob.glob(os.path.join(results_dir, f"results_{round_name.lower()}*.jtl"))
        if jtl_files:
            for f in jtl_files:
                match = re.search(r'run_(\d+)', f)
                run_num = int(match.group(1)) if match else 1
                perf = parse_jmeter_jtl(f, round_name, run_num, backend_errors_df)
                if perf: summary_list.append(perf)

        # 2. Recursos
        stats_files = glob.glob(os.path.join(results_dir, f"docker_stats_{round_name.lower()}*"))
        docker_dfs = []
        for f in stats_files:
            df = analyze_docker_stats(f)
            if df is not None: docker_dfs.append(df)
        
        if docker_dfs:
            full_df = pd.concat(docker_dfs, ignore_index=True)
            plot_resource_charts(full_df, round_name, graphs_dir)
        else:
            print(f"⚠️  [Aviso] Nenhum dado de docker stats encontrado para o cenário: {round_name}")

    # Gera Tabela Consolidada e Gráficos da Rodada
    if summary_list:
        plot_combined_table(summary_list, graphs_dir)
        plot_performance_charts(summary_list, graphs_dir)
        print("✅ Tabelas e Gráficos gerados com sucesso.")
    else:
        print("⚠️  Nenhum dado de desempenho encontrado.")

if __name__ == "__main__":
    main()