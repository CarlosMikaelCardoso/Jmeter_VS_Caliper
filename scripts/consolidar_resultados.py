import os
import csv
import glob
import re
import numpy as np
from bs4 import BeautifulSoup

def processar_jmeter(base_dir):
    resultados = []
    # Analisar de round_1 até round_32
    for rodada in range(1, 33):
        tps_list = []
        latencies = []
        
        # O JMeter pode ter múltiplos JTLs por rodada (open, query, transfer)
        jtl_files = glob.glob(os.path.join(base_dir, f'round_{rodada}', '*.jtl'))
        
        for jtl in jtl_files:
            with open(jtl, 'r', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    if row.get('success') == 'true':
                        latencies.append(float(row['elapsed'])) # JMeter nativo em ms
        
        if latencies:
            lat_media = np.mean(latencies)
            lat_p99 = np.percentile(latencies, 99)
            # Aproximação de TPS: Total de amostras / (Tempo total de execução em segundos)
            # Como simplificação do consolidado, usamos uma métrica média de TPS lida dos resumos ou calculada.
            tps_estimado = len(latencies) / (sum(latencies)/1000) if sum(latencies) > 0 else 0
            
            resultados.append({
                'ID_Rodada': rodada,
                'Ferramenta': 'JMeter',
                'TPS_Nativo': round(tps_estimado, 2),
                'Latencia_Media_Nativa': round(lat_media, 2),
                'Latencia_P99_Nativa': round(lat_p99, 2)
            })
            
    return resultados

def processar_caliper(base_dir):
    resultados = []
    for rodada in range(1, 33):
        html_files = glob.glob(os.path.join(base_dir, f'round_{rodada}', '*.html'))
        tps_list = []
        lat_medias = []
        lat_p99s = []
        
        for html in html_files:
            with open(html, 'r', encoding='utf-8') as f:
                soup = BeautifulSoup(f, 'html.parser')
                # O Caliper gera tabelas. Procuramos os cabeçalhos de TPS e P99
                tabelas = soup.find_all('table')
                for tabela in tabelas:
                    headers = [th.text.strip() for th in tabela.find_all('th')]
                    if 'Throughput (TPS)' in headers and 'Avg Latency (s)' in headers:
                        idx_tps = headers.index('Throughput (TPS)')
                        idx_avg = headers.index('Avg Latency (s)')
                        idx_p99 = headers.index('99%ile Latency (s)') if '99%ile Latency (s)' in headers else headers.index('Max Latency (s)') # Fallback se n tiver P99 explícito
                        
                        rows = tabela.find_all('tr')[1:] # ignorar header
                        for row in rows:
                            cols = row.find_all('td')
                            if len(cols) > idx_p99:
                                tps_list.append(float(cols[idx_tps].text.strip()))
                                # Caliper usa Segundos. Multiplicar por 1000 para ms
                                lat_medias.append(float(cols[idx_avg].text.strip()) * 1000)
                                lat_p99s.append(float(cols[idx_p99].text.strip()) * 1000)
                                
        if tps_list:
            resultados.append({
                'ID_Rodada': rodada,
                'Ferramenta': 'Caliper',
                'TPS_Nativo': round(np.mean(tps_list), 2),
                'Latencia_Media_Nativa': round(np.mean(lat_medias), 2),
                'Latencia_P99_Nativa': round(np.mean(lat_p99s), 2)
            })
            
    return resultados

def aplicar_saneamento(dados, log_file):
    # Separar por ferramenta
    caliper_data = [d for d in dados if d['Ferramenta'] == 'Caliper']
    jmeter_data = [d for d in dados if d['Ferramenta'] == 'JMeter']
    
    dados_finais = []
    
    for ferramenta, dataset in [('Caliper', caliper_data), ('JMeter', jmeter_data)]:
        # 1. Remover Cold Start (Rodada 1)
        dataset_limpo = [d for d in dataset if d['ID_Rodada'] != 1]
        log_file.write(f"[{ferramenta}] Rodada 1 descartada por Cold Start.\n")
        
        # 2. Identificar Outlier (Maior desvio em Latência Média)
        latencias = [d['Latencia_Media_Nativa'] for d in dataset_limpo]
        media_geral = np.mean(latencias)
        
        # Encontrar o item com a maior diferença absoluta da média
        outlier = max(dataset_limpo, key=lambda x: abs(x['Latencia_Media_Nativa'] - media_geral))
        dataset_limpo.remove(outlier)
        log_file.write(f"[{ferramenta}] Rodada {outlier['ID_Rodada']} descartada por Outlier (Maior Desvio de Latência: {outlier['Latencia_Media_Nativa']} ms).\n")
        
        # Garantir exatamente 30 execuções
        dados_finais.extend(dataset_limpo[:30])
        
    return dados_finais

if __name__ == "__main__":
    dados_brutos = []
    dados_brutos.extend(processar_jmeter('../results/jmeter_runs'))
    dados_brutos.extend(processar_caliper('../results/caliper_runs'))
    
    with open('saneamento_log.txt', 'w', encoding='utf-8') as log:
        dados_validados = aplicar_saneamento(dados_brutos, log)
        
    # Salvar planilha final
    with open('planilha_analise_consolidada.csv', 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=['ID_Rodada', 'Ferramenta', 'TPS_Nativo', 'Latencia_Media_Nativa', 'Latencia_P99_Nativa'])
        writer.writeheader()
        writer.writerows(dados_validados)
        
    print("Processamento concluído. Verifique 'planilha_analise_consolidada.csv' e 'saneamento_log.txt'.")