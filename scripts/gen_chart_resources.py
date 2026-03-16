import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.cm as cm
import matplotlib 
import numpy as np
import os
import sys
import glob
import re

# Tenta usar estilo científico
try:
    import scienceplots
    plt.style.use(['science', 'ieee', 'high-vis'])
except:
    plt.style.use('seaborn-v0_8-paper')

def clean_metric(val):
    """Remove % e unidades e converte para float"""
    if isinstance(val, (int, float)): return val
    try:
        return float(str(val).replace('%', '').replace('MiB', '').replace('KB', '').replace('B', ''))
    except:
        return 0.0

def natural_sort_key(name):
    """Ordenação: Prioridade -> Números -> Nome"""
    name = str(name).lower()
    
    # Prioridade de Grupo
    if 'orderer' in name: priority = 0
    elif 'peer' in name:  priority = 1
    elif 'couch' in name: priority = 2
    else: priority = 3
    
    # Extrai números como TUPLA (Isso corrige o erro 'unhashable type list')
    numbers = tuple(int(s) for s in re.findall(r'\d+', name))
    
    return (priority, numbers, name)

def generate_resource_charts(input_dir, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    print(f"--- Gerando Gráficos de Recursos (VERSÃO FINAL V2) ---")
    
    files = glob.glob(os.path.join(input_dir, "docker_stats_*.json"))
    files += glob.glob(os.path.join(input_dir, "docker_stats_*.log"))

    if not files:
        print("⚠️  Nenhum arquivo docker_stats encontrado.")
        return

    all_data = []
    for f in files:
        try:
            scenario = "Unknown"
            if "open" in f.lower(): scenario = "Open"
            elif "query" in f.lower(): scenario = "Query"
            elif "transfer" in f.lower(): scenario = "Transfer"

            df = None
            if f.endswith('.json'):
                try: df = pd.read_json(f)
                except ValueError:
                    try: df = pd.read_json(f, lines=True)
                    except: pass
            
            if df is None:
                try: df = pd.read_csv(f)
                except: continue

            if df is None or df.empty: continue

            df.columns = df.columns.str.lower()
            rename_map = {'cpu %': 'cpu', 'mem usage': 'mem', 'memory': 'mem', 'name': 'container'}
            df.rename(columns=rename_map, inplace=True)
            
            if 'cpu' in df.columns and 'mem' in df.columns:
                df['cpu'] = df['cpu'].apply(clean_metric)
                df['mem'] = df['mem'].apply(clean_metric)
                df['Scenario'] = scenario
                all_data.append(df)
        except Exception: pass

    if not all_data:
        print("⚠️  Nenhum dado válido extraído.")
        return

    full_df = pd.concat(all_data, ignore_index=True)

    for scenario in full_df['Scenario'].unique():
        scenario_df = full_df[full_df['Scenario'] == scenario]
        if scenario_df.empty: continue
        
        summary = scenario_df.groupby('container')[['cpu', 'mem']].mean()
        
        valid_indices = [c for c in summary.index if any(x in c.lower() for x in ['orderer', 'peer', 'couch'])]
        if not valid_indices: continue
        summary = summary.loc[valid_indices]
        
        # Ordenação
        summary['sort_key'] = summary.index.map(natural_sort_key)
        summary = summary.sort_values('sort_key')
        
        num_bars = len(summary)
        
        # [CORREÇÃO DO AVISO] Usa a API nova ou velha dependendo da versão
        try:
            # Tenta API nova (Matplotlib 3.6+)
            cmap = matplotlib.colormaps['tab20']
        except AttributeError:
            # Fallback para versão antiga
            cmap = plt.get_cmap('tab20')
            
        colors = cmap(np.linspace(0, 1, max(num_bars, 2)))[:num_bars]

        # --- PLOT CPU ---
        plt.figure(figsize=(9, 5))
        bars = plt.bar(summary.index, summary['cpu'], color=colors, alpha=0.9, edgecolor='black', linewidth=0.5)
        
        plt.ylabel('Uso Médio de CPU (Porcentagem)')
        plt.title(f'Uso de Recursos (CPU) - {scenario}')
        plt.xticks(rotation=45, ha='right', fontsize=9)
        plt.grid(axis='y', linestyle='--', alpha=0.3)
        
        top_val = summary['cpu'].max()
        plt.ylim(0, top_val * 1.3 if top_val > 0 else 10)
        
        # [CORREÇÃO] Força o rótulo com % manualmente
        labels = [f"{val:.2f}%" for val in summary['cpu']]
        plt.bar_label(bars, labels=labels, padding=3, fontsize=8)
        
        plt.tight_layout()
        plt.savefig(os.path.join(output_dir, f"chart_cpu_{scenario.lower()}.pdf"), format='pdf')
        plt.close()

        # --- PLOT MEMÓRIA ---
        plt.figure(figsize=(9, 5))
        bars = plt.bar(summary.index, summary['mem'], color=colors, alpha=0.9, edgecolor='black', linewidth=0.5)
        
        plt.ylabel('Memória Média (MiB)')
        plt.title(f'Uso de Recursos (Memória) - {scenario}')
        plt.xticks(rotation=45, ha='right', fontsize=9)
        plt.grid(axis='y', linestyle='--', alpha=0.3)
        
        top_mem = summary['mem'].max()
        plt.ylim(0, top_mem * 1.3 if top_mem > 0 else 100)

        # Rótulos memória (sem %)
        mem_labels = [f"{val:.1f}" for val in summary['mem']]
        plt.bar_label(bars, labels=mem_labels, padding=3, fontsize=8)
        
        plt.tight_layout()
        plt.savefig(os.path.join(output_dir, f"chart_mem_{scenario.lower()}.pdf"), format='pdf')
        plt.close()

    print(f"✅ Gráficos salvos em: {output_dir}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Uso: python gen_chart_resources.py <input_dir> <output_dir>")
    else:
        generate_resource_charts(sys.argv[1], sys.argv[2])