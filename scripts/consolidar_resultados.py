import os
import csv
import glob
import re
import numpy as np
import pandas as pd # Adicionado pandas para facilitar a leitura de JTLs grandes
from bs4 import BeautifulSoup
from datetime import datetime

def processar_jmeter(base_dir):
    resultados = []
    for rodada in range(1, 33):
        latencies = []
        df_list = []
        
        # Overhead da API (Mantido conforme sua captura de logs)
        api_log_path = os.path.join(base_dir, f'round_{rodada}', 'api.log')
        overhead_medio, overhead_variancia = 0, 0
        
        if os.path.exists(api_log_path):
            req_ts = {}
            with open(api_log_path, 'r', encoding='utf-8') as f:
                for line in f:
                    ts_m = re.search(r'\[(.*?)\] ReqID:(\w+)', line)
                    if ts_m:
                        ts = datetime.strptime(ts_m.group(1)[:23], '%Y-%m-%dT%H:%M:%S.%f')
                        rid = ts_m.group(2)
                        if rid not in req_ts: req_ts[rid] = [None, None]
                        if 'Recebido' in line: req_ts[rid][0] = ts
                        elif 'Enviado' in line: req_ts[rid][1] = ts
            
            deltas = [(t[1]-t[0]).total_seconds()*1000 for t in req_ts.values() if t[0] and t[1]]
            if deltas:
                overhead_medio = round(np.mean(deltas), 4)
                overhead_variancia = round(np.var(deltas), 4)

        # Processamento do JTL para TPS Real
        jtl_files = glob.glob(os.path.join(base_dir, f'round_{rodada}', '*.jtl'))
        for jtl in jtl_files:
            try:
                df = pd.read_csv(jtl)
                # Filtrar apenas sucessos para o cálculo de TPS e Latência
                df_success = df[df['success'] == True].copy()
                if not df_success.empty:
                    df_list.append(df_success)
                    latencies.extend(df_success['elapsed'].tolist())
            except Exception as e:
                print(f"Erro ao ler {jtl}: {e}")

        if df_list:
            df_full = pd.concat(df_list)
            # --- [CÁLCULO TPS REAL JMETER] ---
            # Tempo total = (Último início + sua duração) - Primeiro início
            tempo_total_ms = (df_full['timeStamp'].max() + df_full['elapsed'].max()) - df_full['timeStamp'].min()
            tps_real = len(df_full) / (tempo_total_ms / 1000.0) if tempo_total_ms > 0 else 0
            
            lat_media = np.mean(latencies)
            lat_p99 = np.percentile(latencies, 99)
            
            resultados.append({
                'ID_Rodada': rodada,
                'Ferramenta': 'JMeter',
                'TPS_Nativo': round(tps_real, 2), # TPS Real calculado
                'Latencia_Media_Nativa': round(lat_media, 2),
                'Latencia_P99_Nativa': round(lat_p99, 2),
                'Overhead_Medio_ms': overhead_medio,
                'Overhead_Variancia': overhead_variancia
            })
            
    return resultados

def processar_caliper(base_dir):
    resultados = []
    for rodada in range(1, 33):
        html_files = glob.glob(os.path.join(base_dir, f'round_{rodada}', '*.html'))
        tps_list, lat_medias, lat_p99s = [], [], []
        
        for html in html_files:
            with open(html, 'r', encoding='utf-8') as f:
                soup = BeautifulSoup(f, 'html.parser')
                for tabela in soup.find_all('table'):
                    headers = [th.text.strip() for th in tabela.find_all('th')]
                    # No Caliper, o TPS já vem calculado nativamente na coluna "Throughput (TPS)"
                    if 'Throughput (TPS)' in headers:
                        idx_tps = headers.index('Throughput (TPS)')
                        idx_avg = headers.index('Avg Latency (s)')
                        idx_p99 = headers.index('99%ile Latency (s)') if '99%ile Latency (s)' in headers else headers.index('Max Latency (s)')
                        
                        for row in tabela.find_all('tr')[1:]:
                            cols = row.find_all('td')
                            if len(cols) > idx_p99:
                                tps_list.append(float(cols[idx_tps].text.strip()))
                                lat_medias.append(float(cols[idx_avg].text.strip()) * 1000)
                                lat_p99s.append(float(cols[idx_p99].text.strip()) * 1000)
                                
        if tps_list:
            resultados.append({
                'ID_Rodada': rodada,
                'Ferramenta': 'Caliper',
                'TPS_Nativo': round(np.mean(tps_list), 2), # Média do TPS reportado pelo Caliper
                'Latencia_Media_Nativa': round(np.mean(lat_medias), 2),
                'Latencia_P99_Nativa': round(np.mean(lat_p99s), 2),
                'Overhead_Medio_ms': 0,
                'Overhead_Variancia': 0
            })
            
    return resultados

def aplicar_saneamento(dados, log_file):
    caliper_data = [d for d in dados if d['Ferramenta'] == 'Caliper']
    jmeter_data = [d for d in dados if d['Ferramenta'] == 'JMeter']
    dados_finais = []
    
    # Ordem: JMeter primeiro no CSV
    for ferramenta, dataset in [('JMeter', jmeter_data), ('Caliper', caliper_data)]:
        if not dataset: continue
        dataset_limpo = [d for d in dataset if d['ID_Rodada'] != 1]
        log_file.write(f"[{ferramenta}] Rodada 1 descartada (Cold Start).\n")
        
        if dataset_limpo:
            latencias = [d['Latencia_Media_Nativa'] for d in dataset_limpo]
            media_geral = np.mean(latencias)
            outlier = max(dataset_limpo, key=lambda x: abs(x['Latencia_Media_Nativa'] - media_geral))
            dataset_limpo.remove(outlier)
            log_file.write(f"[{ferramenta}] Rodada {outlier['ID_Rodada']} descartada (Outlier).\n")
        
        dados_finais.extend(dataset_limpo[:30])
    return dados_finais

if __name__ == "__main__":
    jmeter_path = '../results/jmeter_runs'
    caliper_path = '../results/caliper_runs'
    
    dados_brutos = []
    dados_brutos.extend(processar_jmeter(jmeter_path))
    dados_brutos.extend(processar_caliper(caliper_path))
    
    with open('saneamento_log.txt', 'w', encoding='utf-8') as log:
        dados_validados = aplicar_saneamento(dados_brutos, log)
        
    with open('planilha_analise_consolidada.csv', 'w', newline='', encoding='utf-8') as f:
        fieldnames = ['ID_Rodada', 'Ferramenta', 'TPS_Nativo', 'Latencia_Media_Nativa', 'Latencia_P99_Nativa', 'Overhead_Medio_ms', 'Overhead_Variancia']
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(dados_validados)
    
    print("Consolidação concluída com sucesso.")
