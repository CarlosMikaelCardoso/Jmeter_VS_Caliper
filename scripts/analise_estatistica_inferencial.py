import pandas as pd
import os
import sys
from scipy import stats

def executar_analise_inferencial(input_csv, output_dir):
    if not os.path.exists(input_csv):
        print(f"⚠️ Arquivo {input_csv} não encontrado.")
        return

    df = pd.read_csv(input_csv)
    if df.empty: return

    resultados_normalidade = []
    scenarios = df['Scenario'].unique()

    # Nível de significância (Alpha) padrão acadêmico
    ALPHA = 0.05

    for scenario in scenarios:
        subset = df[df['Scenario'] == scenario]
        
        # Analisamos as duas métricas principais: TPS e Latência Média
        for metrica in ['Throughput (TPS)', 'Avg Latency (s)']:
            dados = subset[metrica].dropna()
            
            # Requisito estatístico: Shapiro-Wilk precisa de pelo menos 3 amostras
            if len(dados) < 3: continue

            # Execução do Teste de Shapiro-Wilk
            shapiro_stat, p_valor = stats.shapiro(dados)
            
            # Decisão de Normalidade
            is_normal = p_valor > ALPHA
            
            # Recomendação de Teste de Hipótese
            # Se normal -> Paramétrico (T-Test)
            # Se não normal -> Não Paramétrico (Mann-Whitney U)
            decisao_teste = "Paramétrico (Student's T-test)" if is_normal else "Não Paramétrico (Mann-Whitney U)"
            
            resultados_normalidade.append({
                'Cenário': scenario,
                'Métrica': metrica,
                'W_Statistic': round(shapiro_stat, 4),
                'p_valor': round(p_valor, 6),
                'Distribuição': 'Normal (Gaussiana)' if is_normal else 'Não Normal',
                'Recomendação_Teste': decisao_teste
            })

    # Exportação dos Resultados
    df_normalidade = pd.DataFrame(resultados_normalidade)
    output_path = os.path.join(output_dir, "relatorio_normalidade.csv")
    df_normalidade.to_csv(output_path, index=False)
    
    # Gerar parágrafo de documentação da decisão para o artigo
    gerar_documentacao_decisao(df_normalidade, output_dir)

    print(f"✅ Análise de Normalidade concluída: {output_path}")

def gerar_documentacao_decisao(df, output_dir):
    # Verifica a tendência geral para recomendar o teste global
    nao_normais = len(df[df['Distribuição'] == 'Não Normal'])
    total = len(df)
    
    resumo = (
        f"DOCUMENTAÇÃO DE ABORDAGEM ESTATÍSTICA\n"
        f"-------------------------------------\n"
        f"Total de testes de normalidade realizados: {total}\n"
        f"Amostras com distribuição não-normal: {nao_normais}\n\n"
        f"DECISÃO CRÍTICA:\n"
    )
    
    if nao_normais > 0:
        resumo += (
            "Considerando que foram identificadas métricas com distribuição não-normal "
            "(p-valor < 0.05), a abordagem estatística adotada para a comparação entre "
            "as ferramentas deve ser NÃO PARAMÉTRICA. Recomenda-se a utilização do teste "
            "de Mann-Whitney U para comparar as medianas de desempenho."
        )
    else:
        resumo += (
            "Como todas as distribuições passaram no teste de Shapiro-Wilk (p-valor > 0.05), "
            "adota-se a abordagem PARAMÉTRICA. Recomenda-se a utilização do teste T de Student "
            "para comparação das médias de desempenho."
        )

    # Salvando como CSV para ser capturado pelo script de relatório final
    pd.DataFrame({'Documentacao_Decisao': [resumo]}).to_csv(
        os.path.join(output_dir, "decisao_estatistica.csv"), index=False
    )

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Uso: python3 analise_estatistica_inferencial.py <input.csv> <output_dir>")
    else:
        executar_analise_inferencial(sys.argv[1], sys.argv[2])