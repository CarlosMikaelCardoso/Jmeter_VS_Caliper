import pandas as pd
import matplotlib.pyplot as plt
import os
import sys
import glob
import re

# Cores para os containers do Fabric (copiado do seu script Caliper)
# Estes nomes (ex: peer0.org1) devem corresponder ao que o monitor-api.js
# escreve no arquivo docker_stats_*.log
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

def parse_jmeter_jtl(jtl_file, round_name, run_number, backend_errors_df):
    """
    Lê um ficheiro JTL (CSV) do JMeter, calcula as métricas de performance
    e incorpora erros do backend (se houver).
    """
    try:
        df = pd.read_csv(jtl_file)
    except Exception as e:
        print(f"  -> Erro ao ler o ficheiro JTL {jtl_file}: {e}")
        return None

    if df.empty:
        print(f"  -> Aviso: Ficheiro JTL {os.path.basename(jtl_file)} está vazio.")
        return None

    # 1. Calcular métricas de JMeter
    jmeter_success = df['success'].sum()
    jmeter_fail = len(df) - jmeter_success
    total_samples = len(df)

    # 2. Calcular métricas de latência (em segundos)
    avg_latency_s = df['elapsed'].mean() / 1000.0
    min_latency_s = df['elapsed'].min() / 1000.0
    max_latency_s = df['elapsed'].max() / 1000.0
    p99_latency_s = df['elapsed'].quantile(0.99) / 1000.0

    # 3. Calcular Throughput (amostras / tempo total em segundos)
    # Tempo total = (Timestamp final + duração da última req) - Timestamp inicial
    start_time_ms = df['timeStamp'].min()
    end_time_ms = (df['timeStamp'] + df['elapsed']).max()
    duration_s = (end_time_ms - start_time_ms) / 1000.0
    
    # Nota: Este throughput inicial é baseado no sucesso HTTP (Send Rate)
    throughput_tps = total_samples / duration_s if duration_s > 0 else 0

    # 4. Incorporar erros do Backend
    try:
        backend_fail_count = backend_errors_df[
            (backend_errors_df['round'] == round_name) & 
            (backend_errors_df['run'] == run_number)
        ]['count'].sum()
    except Exception:
        backend_fail_count = 0

    # 5. Compilar resultados
    # 'Succ' (Sucesso) é apenas o que o JMeter reportou como sucesso.
    # 'Fail' (Falha) é a soma das falhas do JMeter + falhas do backend.
    summary_data = {
        'Round': round_name,
        'Run': run_number,
        'Succ': jmeter_success,
        'JMeter_Fail': jmeter_fail,
        'Backend_Fail': backend_fail_count,
        'Fail': jmeter_fail + backend_fail_count,
        'Avg Latency (s)': avg_latency_s,
        'Min Latency (s)': min_latency_s,
        'Max Latency (s)': max_latency_s,
        'P99 Latency (s)': p99_latency_s,
        'Throughput (TPS)': throughput_tps
    }
    return summary_data


def analyze_docker_stats(stats_file):
    """
    Lê um ficheiro de log do Docker (docker_stats_*.log) e retorna um DataFrame.
    Esta função foi copiada do seu script generateGraphsCaliper.py.
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
    Modificado para usar '_jmeter_' no nome do arquivo.
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

    # Adicionado '_jmeter_' ao nome do arquivo
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_jmeter_summary_table_{title.lower()}.png"), bbox_inches='tight', pad_inches=0.1)
    plt.close()
    
def plot_resource_bar_charts(df, title, resource_name, unit, output_path):
    """
    Gera gráficos de barras para o uso médio e máximo de um recurso.
    Modificado para usar '_jmeter_' no nome do arquivo.
    """
    if df.empty:
        print(f"  -> Aviso: DataFrame de recursos vazio para {title}, pulando gráficos de barras de {resource_name}.")
        return

    summary = df.groupby('container')[resource_name].agg(['mean', 'max']).reset_index()
    summary = summary.sort_values(by='container').set_index('container')
    
    # Garante que apenas os containers presentes nos dados sejam plotados
    valid_containers = [c for c in summary.index if c in NODE_COLORS]
    
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
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_jmeter_avg_{resource_name}_usage_{title.lower()}.png"))
    plt.close()

    plt.figure(figsize=(10, 6))
    bars = plt.bar(summary.index, summary['max'], color=colors)
    plt.title(f'Uso Máximo de {resource_name.upper()} por Nó - {title}')
    plt.ylabel(f'Uso Máximo ({unit})')
    plt.xlabel('Nó')
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    plt.bar_label(bars, fmt='%.2f')
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_jmeter_max_{resource_name}_usage_{title.lower()}.png"))
    plt.close()

def plot_resource_line_chart(df, title, column, y_label, output_path):
    """
    Função para gerar gráficos de linha para Rede e Disco.
    Modificado para usar '_jmeter_' no nome do arquivo.
    """
    if df.empty:
        print(f"  -> Aviso: DataFrame de recursos vazio para {title}, pulando gráfico de linha de {column}.")
        return
        
    plt.figure(figsize=(15, 7))
    
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
    plt.savefig(os.path.join(output_path, f"CONSOLIDATED_jmeter_{column}_usage_{title.lower()}.png"))
    plt.close()

def main():
    if len(sys.argv) < 2:
        print("Uso: python generateGraphs.py <diretório_de_resultados_jmeter>")
        sys.exit(1)

    results_dir = sys.argv[1]
    # As rodadas são definidas no run_jmeter_api.sh
    rounds = ["Open", "Query", "Transfer"]
    
    print(f"\n--- Gerando gráficos consolidados para os resultados JMeter em: {results_dir} ---")

    all_perf_data = []
    all_docker_dfs = []

    # 1. Carregar erros do Backend
    backend_errors_file = os.path.join(results_dir, 'backend_errors.log')
    backend_errors_df = pd.DataFrame(columns=['round', 'run', 'count', 'details'])
    if os.path.exists(backend_errors_file):
        try:
            backend_errors_df = pd.read_csv(backend_errors_file, names=['round', 'run', 'count', 'details'])
            print(f"Ficheiro de erros do backend ({backend_errors_file}) carregado.")
        except Exception as e:
            print(f"  -> Aviso: Não foi possível ler {backend_errors_file}: {e}")


    for round_name in rounds:
        print(f"\n--- Processando Rodada: {round_name} ---")
        
        # 2. Processar Logs de Performance (results_*.jtl)
        jtl_files = glob.glob(os.path.join(results_dir, f"results_{round_name.lower()}_run_*.jtl"))
        if not jtl_files:
            print(f"Aviso: Nenhum ficheiro de log de performance (results_*.jtl) encontrado para '{round_name}'.")
        
        for f in jtl_files:
            # Extrai o número da execução (run) do nome do ficheiro
            match = re.search(r'run_(\d+)\.jtl', f)
            if not match:
                print(f"  -> Aviso: Não foi possível extrair o 'run number' de {f}, pulando...")
                continue
            run_number = int(match.group(1))
            
            perf_summary = parse_jmeter_jtl(f, round_name, run_number, backend_errors_df)
            if perf_summary is not None:
                all_perf_data.append(perf_summary)

        # 3. Processar Logs de Recursos (docker_stats_*.log)
        stats_files = glob.glob(os.path.join(results_dir, f"docker_stats_{round_name.lower()}_run_*.log"))
        if not stats_files:
            print(f"Aviso: Nenhum ficheiro de estatísticas do Docker (docker_stats_*.log) encontrado para '{round_name}'.")

        for f in stats_files:
            docker_df = analyze_docker_stats(f)
            if docker_df is not None:
                docker_df['round'] = round_name 
                all_docker_dfs.append(docker_df)

    # 4. Consolidar e Plotar Performance
    if all_perf_data:
        consolidated_perf_df = pd.DataFrame(all_perf_data)

        # Agrega os resultados de performance (média das médias das N execuções)
        agg_rules = {
            'Succ': 'sum', 'JMeter_Fail': 'sum', 'Backend_Fail': 'sum', 'Fail': 'sum',
            'Avg Latency (s)': 'mean', 'Min Latency (s)': 'mean',
            'Max Latency (s)': 'mean', 'P99 Latency (s)': 'mean',
            'Throughput (TPS)': 'mean'
        }
        final_perf_summary = consolidated_perf_df.groupby('Round').agg(agg_rules).reset_index().set_index('Round')
        # Reordena as rodadas
        final_perf_summary = final_perf_summary.reindex(rounds)

        print("\n--- Resumo de Performance Consolidado (JMeter) ---")
        # Imprime o resumo antes da correção final, para debug
        print(final_perf_summary.to_string(float_format="%.2f"))

        # Gera tabelas de resumo para cada rodada com CORREÇÃO DE TPS
        for round_name, row in final_perf_summary.iterrows():
            
            # --- CÁLCULO CORRIGIDO DO TPS REAL ---
            # O 'Throughput Médio' original é o Send Rate (baseado em sucesso HTTP).
            # O 'Sucesso' (row['Succ']) é o sucesso HTTP original.
            # O 'Sucesso Real' é o Sucesso HTTP - Falhas Backend.
            
            sucesso_http = row['Succ']
            falhas_backend = row['Backend_Fail']
            sucesso_real = sucesso_http - falhas_backend
            
            # Calcula o fator de correção: (Sucesso Real / Sucesso HTTP)
            if sucesso_http > 0:
                fator_correcao = sucesso_real / sucesso_http
            else:
                fator_correcao = 0
                
            # Aplica o fator ao TPS médio original para obter o TPS Real (Write Throughput)
            tps_send_rate = row['Throughput (TPS)']
            tps_real_throughput = tps_send_rate * fator_correcao

            # Atualiza também o número total de falhas para o relatório
            total_falhas = row['JMeter_Fail'] + falhas_backend
            total_amostras = row['Succ'] + row['JMeter_Fail'] # Total de requisições feitas

            summary_data = {
                'Métricas': [
                    'Total de Amostras', 'Sucesso (Confirmado)', 'Falha Total', 'Falha (Backend API)', 
                    'Latência Média (s)', 'Latência P99 (s)', 'Latência Mínima (s)', 'Latência Máxima (s)', 
                    'Throughput Real (TPS)'
                ],
                'Valor': [
                    f"{total_amostras:.0f}",
                    f"{sucesso_real:.0f}",     # Valor corrigido
                    f"{total_falhas:.0f}",     # Valor corrigido
                    f"{falhas_backend:.0f}",
                    f"{row['Avg Latency (s)']:.3f}",
                    f"{row['P99 Latency (s)']:.3f}",
                    f"{row['Min Latency (s)']:.3f}",
                    f"{row['Max Latency (s)']:.3f}",
                    f"{tps_real_throughput:.2f}" # TPS Corrigido (Write Throughput)
                ]
            }
            plot_summary_table_from_dict(summary_data, round_name.capitalize(), results_dir)
            print(f"  -> Rodada {round_name}: TPS Send Rate={tps_send_rate:.2f}, TPS Write Throughput={tps_real_throughput:.2f} (Correção: {fator_correcao*100:.1f}%)")

        print("Tabelas de resumo de performance geradas.")

    # 5. Consolidar e Plotar Recursos
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