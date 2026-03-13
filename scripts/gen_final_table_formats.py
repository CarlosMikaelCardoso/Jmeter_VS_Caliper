import sys
import os
import pandas as pd
import matplotlib.pyplot as plt

def main():
    if len(sys.argv) < 3:
        print("Uso: python3 gen_final_table_formats.py <input_csv> <output_dir>")
        return

    input_csv = sys.argv[1]
    output_dir = sys.argv[2]
    
    if not os.path.exists(input_csv):
        print(f"⚠️ Erro: Arquivo de entrada {input_csv} não encontrado.")
        return

    try:
        # Detecta automaticamente se o separador é vírgula ou ponto-e-vírgula
        df = pd.read_csv(input_csv, sep=None, engine='python')
        if df.empty:
            print("⚠️ Erro: O arquivo de entrada está vazio.")
            return

        # 1. IDENTIFICAÇÃO DE OUTLIERS (Método IQR)
        outliers_list = []
        # Normaliza nomes de colunas para evitar erros de espaços
        df.columns = [c.strip() for c in df.columns]
        
        scenarios = df['Scenario'].unique() if 'Scenario' in df.columns else ['Geral']
        
        for tool in scenarios:
            subset = df[df['Scenario'] == tool] if 'Scenario' in df.columns else df
            # Verifica as duas métricas principais para outliers
            for metric in ['Throughput (TPS)', 'Avg Latency (s)']:
                if metric in subset.columns:
                    q1 = subset[metric].quantile(0.25)
                    q3 = subset[metric].quantile(0.75)
                    iqr = q3 - q1
                    lower = q1 - 1.5 * iqr
                    upper = q3 + 1.5 * iqr
                    
                    outs = subset[(subset[metric] < lower) | (subset[metric] > upper)]
                    for _, row in outs.iterrows():
                        outliers_list.append({
                            'Cenário': tool,
                            'Rodada': row.get('Rodada', 'N/A'),
                            'Métrica': metric,
                            'Valor': row[metric],
                            'Limites': f"[{round(lower, 2)}, {round(upper, 2)}]"
                        })

        # 2. AGREGAÇÃO ESTATÍSTICA DINÂMICA
        agg_config = {}
        targets = ['Throughput (TPS)', 'Avg Latency (s)', 'P99 Latency (s)']
        
        for m in targets:
            if m in df.columns:
                agg_config[m] = ['mean', 'median', 'std', 'min', 'max']

        if agg_config:
            stats_summary = df.groupby('Scenario').agg(agg_config).round(4)
        else:
            print("⚠️ Nenhuma métrica encontrada para gerar estatística descritiva.")
            return

        # 3. TEXTO DE RESUMO PARA O ARTIGO
        resumo_texto = "Análise estatística concluída."
        if 'Throughput (TPS)' in df.columns:
            tps_mean = df.groupby('Scenario')['Throughput (TPS)'].mean()
            resumo_texto = (
                f"A análise das rodadas identifica o cenário {tps_mean.idxmax()} com maior média de TPS ({tps_mean.max():.2f}). "
                f"Foram detectados {len(outliers_list)} registros discrepantes via método IQR."
            )

        # 4. EXPORTAÇÃO DOS 3 ARQUIVOS (Garantia de saída)
        os.makedirs(output_dir, exist_ok=True)
        
        # Arquivo 1: Estatística Descritiva
        stats_summary.to_csv(os.path.join(output_dir, "estatistica_descritiva.csv"))
        
        # Arquivo 2: Outliers (mesmo que vazio, gera o cabeçalho)
        pd.DataFrame(outliers_list).to_csv(os.path.join(output_dir, "outliers_identificados.csv"), index=False)
        
        # Arquivo 3: Texto para o Artigo
        pd.DataFrame({'Resumo_Artigo': [resumo_texto]}).to_csv(os.path.join(output_dir, "texto_resultados_artigo.csv"), index=False)

        print(f"✅ Sucesso: 3 arquivos gerados em {output_dir}")

    except Exception as e:
        print(f"❌ Erro crítico no processamento final: {e}")

if __name__ == "__main__":
    main()
