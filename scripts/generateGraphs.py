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

def parse_jmeter_jtl(jtl_file, round_name, run_number, backend_errors_df):
    """ Lê arquivo JTL e calcula métricas principais. """
    try:
        df = pd.read_csv(jtl_file)
    except Exception as e:
        print(f"  -> Erro leitura JTL {os.path.basename(jtl_file)}: {e}")
        return None

    if df.empty: return None

    jmeter_success = df['success'].sum()
    jmeter_fail = len(df) - jmeter_success
    
    # Latência em segundos
    avg_latency_s = df['elapsed'].mean() / 1000.0
    p99_latency_s = df['elapsed'].quantile(0.99) / 1000.0

    # Throughput
    start_time_ms = df['timeStamp'].min()
    end_time_ms = (df['timeStamp'] + df['elapsed']).max()
    duration_s = (end_time_ms - start_time_ms) / 1000.0
    throughput_tps = jmeter_success / duration_s if duration_s > 0 else 0

    # Erros do Backend
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

    return {
        'Round': round_name, 'Run': run_number,
        'Succ': jmeter_success, 'JMeter_Fail': jmeter_fail,
        'Backend_Fail': backend_fail_count, 'Fail': jmeter_fail + backend_fail_count,
        'Avg Latency (s)': avg_latency_s, 'P99 Latency (s)': p99_latency_s,
        'Throughput (TPS)': throughput_tps
    }

def analyze_docker_stats(stats_file):
    """ Lê log Docker (JSON ou CSV) com proteção contra arquivos vazios. """
    try:
        if not os.path.exists(stats_file) or os.stat(stats_file).st_size == 0:
            return None

        try:
            df = pd.read_json(stats_file)
        except ValueError:
            try: df = pd.read_csv(stats_file)
            except: return None
        
        if df.empty: return None

        # Limpeza de unidades (se necessário)
        for col in ['cpu', 'mem']:
            if col in df.columns and df[col].dtype == object:
                df[col] = df[col].astype(str).str.replace('%', '').str.replace('MiB', '').str.replace('KB', '').str.replace('B', '')
                df[col] = pd.to_numeric(df[col], errors='coerce').fillna(0)
        
        return df
    except: return None

def plot_summary_table(summary_data, title, output_path):
    """ Gera Tabela de Resumo como Imagem PNG. """
    if not summary_data: return

    # Prepara os dados para a tabela
    metrics = [
        ['Total Amostras', f"{int(summary_data['Total'])}"],
        ['Sucesso (Real)', f"{int(summary_data['Succ'])}"],
        ['Falhas (Total)', f"{int(summary_data['Fail'])}"],
        ['Latência Média', f"{summary_data['Avg Latency (s)']:.3f} s"],
        ['Latência P99',   f"{summary_data['P99 Latency (s)']:.3f} s"],
        ['Throughput (TPS)', f"{summary_data['Throughput (TPS)']:.2f}"]
    ]
    
    df = pd.DataFrame(metrics, columns=['Métrica', 'Valor'])

    fig, ax = plt.subplots(figsize=(5, 3))
    ax.axis('tight')
    ax.axis('off')
    
    # Cria a tabela
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

    # Calcula a média por container
    summary = df.groupby('container')[resource].mean().sort_values()
    
    # Define cores
    colors = [NODE_COLORS.get(c, '#555') for c in summary.index]

    plt.figure(figsize=(8, 5))
    bars = plt.bar(summary.index, summary.values, color=colors, alpha=0.9)
    
    plt.title(f'Média de Uso: {resource.upper()} - {title}')
    plt.ylabel(unit)
    plt.xlabel('Container')
    plt.xticks(rotation=45, ha='right')
    plt.grid(axis='y', linestyle='--', alpha=0.3)
    
    # Adiciona valores no topo das barras
    plt.bar_label(bars, fmt='%.1f', padding=3)
    
    plt.tight_layout()
    plt.savefig(os.path.join(output_path, f"bar_{resource}_{title.lower()}.png"), dpi=150)
    plt.close()

def main():
    if len(sys.argv) < 2:
        print("Uso: python generateGraphs.py <pasta_da_rodada>")
        sys.exit(1)

    results_dir = sys.argv[1]
    graphs_dir = os.path.join(results_dir, "graphs")
    os.makedirs(graphs_dir, exist_ok=True)
    print(f"--- Gerando gráficos simplificados em: {graphs_dir} ---")

    rounds = ["Open", "Query", "Transfer"]
    
    # Carrega erros de backend se existir
    backend_err_path = os.path.join(os.path.dirname(results_dir), 'backend_errors.log')
    backend_errors_df = pd.DataFrame()
    if os.path.exists(backend_err_path):
        try: backend_errors_df = pd.read_csv(backend_err_path, names=['round', 'run', 'count', 'details'])
        except: pass

    for round_name in rounds:
        # 1. Performance (JTL)
        jtl_pattern = os.path.join(results_dir, f"results_{round_name.lower()}*.jtl")
        jtl_files = glob.glob(jtl_pattern)
        
        all_perf = []
        if jtl_files:
            print(f"  -> Processando Performance: {round_name}")
            for f in jtl_files:
                match = re.search(r'run_(\d+)', f)
                run_num = int(match.group(1)) if match else 1
                perf = parse_jmeter_jtl(f, round_name, run_num, backend_errors_df)
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
            # Consolida dados (usa o primeiro ou média)
            d = all_perf[0]
            # Correção de TPS (Backend Failures)
            succ_http = d['Succ']
            fail_back = d['Backend_Fail']
            succ_real = max(0, succ_http - fail_back)
            factor = (succ_real / succ_http) if succ_http > 0 else 0
            tps_real = d['Throughput (TPS)'] * factor

            summary_data = {
                'Total': d['Succ'] + d['JMeter_Fail'],
                'Succ': succ_real,
                'Fail': d['JMeter_Fail'] + fail_back,
                'Avg Latency (s)': d['Avg Latency (s)'],
                'P99 Latency (s)': d['P99 Latency (s)'],
                'Throughput (TPS)': tps_real
            }
            plot_summary_table(summary_data, round_name, graphs_dir)

        if all_docker:
            full_df = pd.concat(all_docker, ignore_index=True)
            # Apenas os 2 gráficos pedidos
            plot_resource_bar(full_df, round_name, 'cpu', '% CPU', graphs_dir)
            plot_resource_bar(full_df, round_name, 'mem', 'MiB Mem', graphs_dir)

    print("Concluído.")

if __name__ == "__main__":
    main()