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
    
    # Agregação Final (Média das 32 rodadas)
    summary = df.groupby('Scenario').agg({
        'Samples': 'sum',
        'Successful': 'sum',
        'Failed': 'sum',
        'Throughput (TPS)': ['mean'],
        'Avg Latency (s)': ['mean']
    }).reset_index()

    summary.columns = ['Scenario', 'Total Samples', 'Total Success', 'Total Failed', 
                       'TPS (Avg)', 'Latency (Avg)(s)']

    # Arredondamentos
    summary['TPS (Avg)'] = summary['TPS (Avg)'].round(2)
    summary['Latency (Avg)(s)'] = summary['Latency (Avg)(s)'].round(4)

    # 1. Exporta CSV
    summary.to_csv(os.path.join(output_dir, "summary_table_final.csv"), index=False)

    # 2. Exporta LaTeX
    latex_df = summary.copy()
    latex_df['Throughput (TPS)'] = latex_df.apply(lambda x: f"{x['TPS (Avg)']}", axis=1)
    latex_df['Latency (s)'] = latex_df.apply(lambda x: f"{x['Latency (Avg)(s)']}", axis=1)
    latex_df = latex_df[['Scenario', 'Total Samples', 'Total Success', 'Total Failed', 'Throughput (TPS)', 'Latency (s)']]
    
    with open(os.path.join(output_dir, "summary_table_final.tex"), "w") as f:
        f.write(latex_df.to_latex(index=False, caption="Resultados Consolidados", escape=False))

    # 3. Exporta PDF
    fig, ax = plt.subplots(figsize=(12, 3))
    ax.axis('tight')
    ax.axis('off')
    table = ax.table(cellText=summary.values, colLabels=summary.columns, loc='center', cellLoc='center')
    table.auto_set_font_size(False)
    table.set_fontsize(9)
    table.scale(1.2, 1.2)
    
    # Cabeçalho colorido
    for (i, j), cell in table.get_celld().items():
        if i == 0:
            cell.set_text_props(weight='bold', color='white')
            cell.set_facecolor('#4a4a4a')

    plt.title("Resumo Final (32 Rodadas)", weight='bold')
    plt.savefig(os.path.join(output_dir, "summary_table_final.pdf"), bbox_inches='tight')
    plt.close()
    
    print(f"✅ Tabela Final Gerada (PDF/CSV/TeX) em: {output_dir}")

if __name__ == "__main__":
    main()