import pandas as pd
import matplotlib.pyplot as plt
import os
import sys
import glob
# Tente importar scienceplots, se falhar usa o padrão
try:
    import scienceplots
    plt.style.use(['science', 'ieee', 'high-vis']) # high-vis é ótimo para contraste
except:
    print("Aviso: SciencePlots não instalado. Usando estilo padrão.")
    plt.style.use('ggplot')

def generate_article_assets(results_dir):
    print(f"--- Gerando Ativos para Artigo em: {results_dir} ---")
    
    # 1. Carregar Dados Consolidados (Exemplo: procurando os CSVs gerados ou logs)
    # Aqui vou assumir que você quer gerar gráficos dos dados de CPU que já tem nos CSVs ou Logs
    # Se tiver os CSVs de 'docker_stats_*.csv' ou similar
    
    # Exemplo: Converter os JSONs/Logs de estatísticas em Gráficos de Linha Bonitos
    stats_files = glob.glob(os.path.join(results_dir, "docker_stats_*.json"))
    
    for f in stats_files:
        try:
            df = pd.read_json(f)
            # Limpeza rápida
            for col in ['cpu', 'mem']:
                if df[col].dtype == object:
                    df[col] = df[col].str.replace('%','').str.replace('MiB','').astype(float)
            
            df['time'] = df.groupby('container').cumcount() + 1
            
            # --- GRÁFICO DE CPU (Estilo Artigo) ---
            plt.figure(figsize=(3.5, 2.5)) # Tamanho típico de meia coluna IEEE
            
            containers = df['container'].unique()
            for container in containers:
                if 'orderer' in container or 'peer' in container: # Filtra só os importantes
                    subset = df[df['container'] == container]
                    plt.plot(subset['time'], subset['cpu'], label=container, linewidth=0.8)
            
            plt.xlabel('Tempo (s)')
            plt.ylabel('Uso de CPU (%)')
            plt.title('Consumo de Recursos')
            plt.legend(fontsize=6, loc='upper right')
            plt.grid(True, linestyle='--', alpha=0.5)
            
            # Salva em PDF (Vetorial)
            base_name = os.path.basename(f).replace('.json', '')
            plt.savefig(os.path.join(results_dir, f"ARTIGO_{base_name}_cpu.pdf"), format='pdf', bbox_inches='tight')
            plt.close()
            print(f"  -> Gráfico PDF gerado: ARTIGO_{base_name}_cpu.pdf")
            
        except Exception as e:
            print(f"Erro em {f}: {e}")

    # 2. Gerar Tabelas LaTeX dos JTLs (Resultados Finais)
    jtl_files = glob.glob(os.path.join(results_dir, "results_*.jtl"))
    summary_list = []
    
    for jtl in jtl_files:
        try:
            df = pd.read_csv(jtl)
            name = os.path.basename(jtl).replace('results_', '').replace('.jtl', '')
            
            summary_list.append({
                'Scenario': name.capitalize(),
                'Samples': len(df),
                'Avg Latency (s)': df['elapsed'].mean()/1000,
                'P99 (s)': df['elapsed'].quantile(0.99)/1000,
                'TPS': len(df) / ((df['timeStamp'].max() - df['timeStamp'].min())/1000)
            })
        except: pass
        
    if summary_list:
        df_final = pd.DataFrame(summary_list)
        latex = df_final.to_latex(index=False, float_format="%.2f", caption="Performance Summary", label="tab:perf_summary")
        
        with open(os.path.join(results_dir, "ARTIGO_tabela_resumo.tex"), "w") as f:
            f.write(latex)
        print("  -> Tabela LaTeX gerada: ARTIGO_tabela_resumo.tex")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Uso: python generateArticleAssets.py <pasta_dos_resultados>")
    else:
        generate_article_assets(sys.argv[1])