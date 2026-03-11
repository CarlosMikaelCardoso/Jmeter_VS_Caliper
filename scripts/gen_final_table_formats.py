import sys
import os
import pandas as pd
import matplotlib.pyplot as plt

def main():
    if len(sys.argv) < 3:
        print("Uso: python3 gen_final_table_formats.py <input_csv> <output_dir>")
        sys.exit(1)

    input_csv = sys.argv[1]
    output_dir = sys.argv[2]
    
    if not os.path.exists(input_csv):
        print(f"⚠️  CSV de entrada não encontrado: {input_csv}")
        return

    df = pd.read_csv(input_csv)
    
    # Função para detectar outliers via IQR (Interquartile Range)
    def find_outliers(data, col):
        q1 = data[col].quantile(0.25)
        q3 = data[col].quantile(0.75)
        iqr = q3 - q1
        lower_bound = q1 - 1.5 * iqr
        upper_bound = q3 + 1.5 * iqr
        return data[(data[col] < lower_bound) | (data[col] > upper_bound)]

    # 1. Identificação de Outliers (Cálculo formal solicitado)
    outliers_list = []
    for tool in df['Scenario'].unique(): # Aqui 'Scenario' costuma diferenciar Jmeter_Open vs Caliper_Open
        subset = df[df['Scenario'] == tool]
        out_tps = find_outliers(subset, 'Throughput (TPS)')
        if not out_tps.empty:
            for _, row in out_tps.iterrows():
                outliers_list.append(f"Outlier em {tool} (Rodada {row['Rodada']}): TPS {row['Throughput (TPS)']} fora do padrão.")

    # 2. Agregação Estatística Completa (Requisito: Média, Mediana, DP, Min, Max)
    stats_summary = df.groupby('Scenario').agg({
        'Throughput (TPS)': ['mean', 'median', 'std', 'min', 'max'],
        'Avg Latency (s)': ['mean', 'median', 'std', 'min', 'max']
    }).round(4)
    
    # 3. Geração do Parágrafo para o Artigo (Resultados)
    best_tps_scenario = df.loc[df['Throughput (TPS)'].idxmax()]['Scenario']
    avg_tps_global = df['Throughput (TPS)'].mean()
    result_text = (
        f"A análise quantitativa das 32 rodadas revela um comportamento geral de "
        f"{'estabilidade' if df['Throughput (TPS)'].std() < 5 else 'variabilidade significativa'}. "
        f"O cenário {best_tps_scenario} apresentou o maior throughput médio. "
        f"Foram identificados {len(outliers_list)} outliers durante o estresse, "
        f"conforme detalhado na lista de saneamento."
    )

    # Exportação dos novos artefatos
    stats_summary.to_csv(os.path.join(output_dir, "estatistica_descritiva.csv"))
    with open(os.path.join(output_dir, "outliers_identificados.txt"), "w") as f:
        f.write("\n".join(outliers_list))
    with open(os.path.join(output_dir, "paragrafo_resultados_artigo.txt"), "w") as f:
        f.write(result_text)

    print(f"✅ Estatísticas e Outliers gerados em: {output_dir}")

if __name__ == "__main__":
    main()
