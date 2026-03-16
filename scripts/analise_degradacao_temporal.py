import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os
import sys
from scipy.stats import spearmanr, pearsonr

# Configurações de estilo acadêmico (Clean White)
plt.rcParams.update({
    "font.family": "serif",
    "axes.facecolor": "white",
    "axes.edgecolor": "black",
    "axes.grid": True,
    "grid.alpha": 0.3,
    "savefig.dpi": 300
})

def analisar_degradacao(jmeter_csv, caliper_csv, output_dir):
    """
    Realiza a análise de correlação entre o avanço das rodadas e o desempenho,
    gerando gráficos de tendência e laudos de estabilidade.
    """
    if not os.path.exists(jmeter_csv) or not os.path.exists(caliper_csv):
        print("⚠️ Arquivos de entrada não encontrados para análise de degradação.")
        return

    # Carregamento e unificação dos dados
    df_j = pd.read_csv(jmeter_csv)
    df_j['Ferramenta'] = 'JMeter'
    
    df_c = pd.read_csv(caliper_csv)
    df_c['Ferramenta'] = 'Caliper'
    # Padronização de nomes de cenários
    df_c['Scenario'] = df_c['Scenario'].str.replace('log_', '').str.lower()
    df_j['Scenario'] = df_j['Scenario'].str.lower()

    df_full = pd.concat([df_j, df_c], ignore_index=True)
    os.makedirs(output_dir, exist_ok=True)

    relatorio_correlacao = []
    scenarios = df_full['Scenario'].unique()

    # 1. GERAÇÃO DE GRÁFICOS DE LINHA (Tendência Temporal)
    metrics = [
        ('Throughput (TPS)', 'Vazão (TPS)', 'tendencia_tps.pdf'),
        ('Avg Latency (s)', 'Latência Média (s)', 'tendencia_latencia.pdf')
    ]

    for col, label, filename in metrics:
        fig, axes = plt.subplots(1, len(scenarios), figsize=(18, 6), sharey=True)
        
        for i, scenario in enumerate(scenarios):
            subset = df_full[df_full['Scenario'] == scenario]
            sns.lineplot(
                ax=axes[i], x='Rodada', y=col, hue='Ferramenta', 
                data=subset, marker='o', markersize=5
            )
            axes[i].set_title(f'Cenário: {scenario.capitalize()}')
            axes[i].set_xlabel('ID da Rodada')
            axes[i].set_ylabel(label if i == 0 else "")
            
            # Cálculo de Correlação para o laudo
            for tool in ['JMeter', 'Caliper']:
                t_data = subset[subset['Ferramenta'] == tool].sort_values('Rodada')
                if len(t_data) > 1:
                    # Usamos Spearman pois a degradação pode não ser linear
                    corr, p_val = spearmanr(t_data['Rodada'], t_data[col])
                    relatorio_correlacao.append({
                        'Ferramenta': tool,
                        'Cenário': scenario,
                        'Métrica': col,
                        'Correlação_Spearman': round(corr, 4),
                        'p-valor': round(p_val, 4),
                        'Tendência': 'Degradação' if (corr > 0.5 and 'Latency' in col) or (corr < -0.5 and 'TPS' in col) else 'Estável'
                    })

        plt.tight_layout()
        plt.savefig(os.path.join(output_dir, filename))
        plt.close()

    # 2. SALVAR RELATÓRIO DE CORRELAÇÃO
    df_corr = pd.DataFrame(relatorio_correlacao)
    df_corr.to_csv(os.path.join(output_dir, "relatorio_correlacao_temporal.csv"), index=False)
    
    # 3. GERAÇÃO DO PARÁGRAFO DE DISCUSSÃO (DOCUMENTAÇÃO)
    gerar_paragrafo_estabilidade(df_corr, output_dir)

def gerar_paragrafo_estabilidade(df_corr, output_dir):
    """Gera um texto qualitativo baseado nas correlações calculadas."""
    degradacoes = df_corr[df_corr['Tendência'] == 'Degradação']
    
    with open(os.path.join(output_dir, "discussao_estabilidade.txt"), "w", encoding='utf-8') as f:
        f.write("DISCUSSÃO SOBRE ESTABILIDADE E SATURAÇÃO DO SISTEMA\n")
        f.write("-" * 50 + "\n\n")
        
        if degradacoes.empty:
            f.write(
                "A análise de correlação de Spearman entre o ID da Rodada e as métricas de desempenho "
                "(TPS e Latência) não identificou tendências de degradação contínua (coeficientes próximos de zero). "
                "Isso confirma a hipótese de estabilidade do ambiente DLT sob a carga aplicada, indicando que "
                "os recursos do sistema (CPU/Memória) foram suficientes para sustentar as 32 rodadas sem "
                "efeitos de saturação ou gargalos progressivos."
            )
        else:
            casos = ", ".join([f"{row['Ferramenta']} ({row['Cenário']})" for _, row in degradacoes.iterrows()])
            f.write(
                f"Foram identificados indícios de degradação de desempenho nos seguintes casos: {casos}. "
                "Nestes cenários, observou-se uma correlação moderada/forte entre o avanço das rodadas e "
                "a variação das métricas, sugerindo um possível acúmulo de estado na ledger ou saturação "
                "gradual de recursos que merece investigação detalhada em testes de longa duração (Longevity Tests)."
            )

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Uso: python3 analise_degradacao_temporal.py <jmeter.csv> <caliper.csv> <output_dir>")
    else:
        analisar_degradacao(sys.argv[1], sys.argv[2], sys.argv[3])

# python3 analise_degradacao_temporal.py \
# "/home/gercom/Jmeter_VS_Caliper/results/jmeter_runs/RELATORIO_FINAL_CONSOLIDADO/round_performance_summary.csv" \
# "/home/gercom/Jmeter_VS_Caliper/results/caliper_runs/RELATORIO_FINAL_CONSOLIDADO/round_performance_summary.csv" \
# "/home/gercom/Jmeter_VS_Caliper/results/analise_estabilidade/"