import pandas as pd
import os
import sys
import numpy as np
from scipy import stats

def calcular_effect_size(u_stat, n1, n2):
    """Calcula o rank-biserial correlation (r) como medida de tamanho do efeito"""
    # r = 1 - (2*U / (n1 * n2))
    r = 1 - (2 * u_stat / (n1 * n2))
    return abs(r)

def interpretar_efeito(r):
    if r < 0.1: return "Insignificante"
    if r < 0.3: return "Pequeno"
    if r < 0.5: return "Médio"
    return "Grande"

def executar_teste_hipotese(jmeter_csv, caliper_csv, output_dir):
    try:
        # Carregamento dos dados com detecção de separador
        df_j = pd.read_csv(jmeter_csv, sep=None, engine='python')
        df_c = pd.read_csv(caliper_csv, sep=None, engine='python')

        # Padronização de nomes de cenários para comparação
        # Mapeia 'log_transfer' para 'transfer', etc.
        df_c['Scenario'] = df_c['Scenario'].str.replace('log_', '').str.lower()
        
        resultados = []
        ALPHA = 0.05
        cenarios = ['open', 'query', 'transfer']

        for cenario in cenarios:
            data_j = df_j[df_j['Scenario'] == cenario]
            data_c = df_c[df_c['Scenario'] == cenario]

            if data_j.empty or data_c.empty: continue

            for metrica in ['Throughput (TPS)', 'Avg Latency (s)']:
                vals_j = data_j[metrica].dropna()
                vals_c = data_c[metrica].dropna()

                # Execução do Teste de Mann-Whitney U
                u_stat, p_valor = stats.mannwhitneyu(vals_c, vals_j, alternative='two-sided')
                
                # Cálculo do Tamanho do Efeito
                r = calcular_effect_size(u_stat, len(vals_c), len(vals_j))
                
                significativo = "Sim" if p_valor < ALPHA else "Não"
                
                resultados.append({
                    'Cenário': cenario,
                    'Métrica': metrica,
                    'p_valor': round(p_valor, 6),
                    'Estatisticamente_Significativo': significativo,
                    'Tamanho_do_Efeito_(r)': round(r, 4),
                    'Magnitude': interpretar_efeito(r),
                    'Melhor_Performance': 'Caliper' if vals_c.median() > vals_j.median() and metrica == 'Throughput (TPS)' else 'JMeter' if vals_j.median() > vals_c.median() and metrica == 'Throughput (TPS)' else 'Caliper' if vals_c.median() < vals_j.median() else 'JMeter'
                })

        # Exportação dos Resultados
        df_final = pd.DataFrame(resultados)
        output_path = os.path.join(output_dir, "comparacao_estatistica_hipotese.csv")
        df_final.to_csv(output_path, index=False)
        
        print(f"✅ Testes de hipótese concluídos: {output_path}")

    except Exception as e:
        print(f"❌ Erro no teste de hipótese: {e}")

if __name__ == "__main__":
    if len(sys.argv) > 3:
        executar_teste_hipotese(sys.argv[1], sys.argv[2], sys.argv[3])
    else:
        print("Uso: python3 teste_hipotese_mann_whitney.py <jmeter.csv> <caliper.csv> <output_dir>")

# python3 teste_hipotese_mann_whitney.py \
# "/home/gercom/Jmeter_VS_Caliper/results/jmeter_runs/RELATORIO_FINAL_CONSOLIDADO/round_performance_summary.csv" \
# "/home/gercom/Jmeter_VS_Caliper/results/caliper_runs/RELATORIO_FINAL_CONSOLIDADO/round_performance_summary.csv" \
# "/home/gercom/Jmeter_VS_Caliper/results/"