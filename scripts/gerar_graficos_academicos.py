import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os
import sys

# Configuração de Estilo Acadêmico
plt.rcParams.update({
    "font.family": "serif",
    "font.size": 12,
    "axes.labelsize": 12,
    "axes.titlesize": 14,
    "xtick.labelsize": 10,
    "ytick.labelsize": 10,
    "legend.fontsize": 10,
    "figure.titlesize": 16,
    "savefig.dpi": 300,
    "axes.grid": True,
    "grid.alpha": 0.3,
    "axes.facecolor": "white"
})

def gerar_visualizacoes(jmeter_csv, caliper_csv, output_dir):
    if not os.path.exists(jmeter_csv) or not os.path.exists(caliper_csv):
        print("⚠️ Arquivos de entrada não encontrados.")
        return

    # Carregamento e identificação da fonte
    df_j = pd.read_csv(jmeter_csv)
    df_j['Tool'] = 'JMeter'
    
    df_c = pd.read_csv(caliper_csv)
    df_c['Tool'] = 'Caliper'
    df_c['Scenario'] = df_c['Scenario'].str.replace('log_', '').str.lower()

    # Combinação dos dados para comparação direta
    df_full = pd.concat([df_j, df_c], ignore_index=True)
    df_full['Scenario'] = df_full['Scenario'].str.capitalize()

    os.makedirs(output_dir, exist_ok=True)

    metrics = [
        ('Throughput (TPS)', 'Vazão (TPS)', 'boxplot_tps.pdf'),
        ('Avg Latency (s)', 'Latência Média (s)', 'boxplot_latencia.pdf')
    ]

    # 1. GERAÇÃO DE BOXPLOTS (Comparação de Dispersão)
    for col, label, filename in metrics:
        plt.figure(figsize=(10, 6))
        sns.boxplot(x='Scenario', y=col, hue='Tool', data=df_full, palette='Greys')
        
        plt.title(f'Análise Comparativa: {label}')
        plt.xlabel('Cenário Experimental')
        plt.ylabel(label)
        plt.legend(title='Ferramenta', frameon=True)
        
        plt.tight_layout()
        plt.savefig(os.path.join(output_dir, filename))
        plt.savefig(os.path.join(output_dir, filename.replace('.pdf', '.png')), dpi=300)
        plt.close()

    # 2. GERAÇÃO DE GRÁFICOS DE SÉRIE TEMPORAL (Distribuição pelas Rodadas)
    for col, label, filename in metrics:
        plt.figure(figsize=(12, 6))
        for tool in ['JMeter', 'Caliper']:
            subset = df_full[df_full['Tool'] == tool]
            for scenario in subset['Scenario'].unique():
                sc_data = subset[subset['Scenario'] == scenario].sort_values('Rodada')
                plt.plot(sc_data['Rodada'], sc_data[col], label=f'{tool} - {scenario}', alpha=0.7, marker='o', markersize=4)

        plt.title(f'Distribuição de Desempenho em 32 Rodadas: {label}')
        plt.xlabel('Número da Rodada')
        plt.ylabel(label)
        plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left', fontsize=8)
        
        plt.tight_layout()
        plt.savefig(os.path.join(output_dir, "dispersão temporal_" + filename))
        plt.close()

    print(f"✅ Gráficos acadêmicos gerados com sucesso em: {output_dir}")

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Uso: python3 gerar_graficos_academicos.py <jmeter.csv> <caliper.csv> <output_dir>")
    else:
        gerar_visualizacoes(sys.argv[1], sys.argv[2], sys.argv[3])


# python3 gerar_graficos_academicos.py \
# "/home/gercom/Jmeter_VS_Caliper/results/jmeter_runs/RELATORIO_FINAL_CONSOLIDADO/round_performance_summary.csv" \
# "/home/gercom/Jmeter_VS_Caliper/results/caliper_runs/RELATORIO_FINAL_CONSOLIDADO/round_performance_summary.csv" \
# "/home/gercom/Jmeter_VS_Caliper/results/comparativo_final/"
