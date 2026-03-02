import os
import csv
import glob
import re
import numpy as np
import pandas as pd
from bs4 import BeautifulSoup
from datetime import datetime

def processar_jmeter(base_dir):
    resultados = []
    for rodada in range(1, 33):
        latencies = []
        df_list = []
        
        # --- [CAPTURA DE OVERHEAD DA API] ---
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

        # --- [PROCESSAMENTO JTL PARA TPS REAL] ---
        jtl_files = glob.glob(os.path.join(base_dir, f'round_{rodada}', '*.jtl'))
        for jtl in jtl_files:
            try:
                df = pd.read_csv(jtl)
                df_success = df[df['success'] == True].copy()
                if not df_success.empty:
                    df_list.append(df_success)
                    latencies.extend(df_success['elapsed'].tolist())
            except Exception as e:
                print(f"Erro ao ler {jtl}: {e}")

        if df_list:
            df_full = pd.concat(df_list)
            tempo_total_ms = (df_full['timeStamp'].max() + df_full['elapsed'].max()) - df_full['timeStamp'].min()
            tps_real = len(df_full) / (tempo_total_ms / 1000.0) if tempo_total_ms > 0 else 0
            
            resultados.append({
                'ID_Rodada': rodada,
                'Ferramenta': 'JMeter',
                'TPS_Nativo': round(tps_real, 2),
                'Latencia_Media_Nativa': round(np.mean(latencies), 2),
                'Latencia_P99_Nativa': round(np.percentile(latencies, 99), 2),
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
                'TPS_Nativo': round(np.mean(tps_list), 2),
                'Latencia_Media_Nativa': round(np.mean(lat_medias), 2),
                'Latencia_P99_Nativa': round(np.mean(lat_p99s), 2),
                'Overhead_Medio_ms': 0,
                'Overhead_Variancia': 0
            })
    return resultados

def aplicar_saneamento(dados):
    caliper_data = [d for d in dados if d['Ferramenta'] == 'Caliper']
    jmeter_data = [d for d in dados if d['Ferramenta'] == 'JMeter']
    dados_finais = []
    
    for dataset in [jmeter_data, caliper_data]:
        if not dataset: continue
        # Remover Rodada 1 e Outlier
        dataset_limpo = [d for d in dataset if d['ID_Rodada'] != 1]
        if dataset_limpo:
            latencias = [d['Latencia_Media_Nativa'] for d in dataset_limpo]
            media = np.mean(latencias)
            outlier = max(dataset_limpo, key=lambda x: abs(x['Latencia_Media_Nativa'] - media))
            dataset_limpo.remove(outlier)
        dados_finais.extend(dataset_limpo[:30])
    return dados_finais

if __name__ == "__main__":
    # 1. Processamento Inicial
    brutos = processar_jmeter('../results/jmeter_runs') + processar_caliper('../results/caliper_runs')
    validados = aplicar_saneamento(brutos)
    
    df_mestre = pd.DataFrame(validados)
    
    # 2. Cálculos de Comparação Justa
    jmeter_df = df_mestre[df_mestre['Ferramenta'] == 'JMeter'].copy()
    caliper_df = df_mestre[df_mestre['Ferramenta'] == 'Caliper'].copy()
    
    # Latencia Ajustada
    jmeter_df['Latencia_JMeter_Ajustada'] = jmeter_df['Latencia_Media_Nativa'] - jmeter_df['Overhead_Medio_ms']
    
    # Merge para Comparação e Erro
    df_final = pd.merge(
        jmeter_df[['ID_Rodada', 'TPS_Nativo', 'Latencia_Media_Nativa', 'Latencia_JMeter_Ajustada', 'Overhead_Medio_ms', 'Overhead_Variancia']],
        caliper_df[['ID_Rodada', 'Latencia_Media_Nativa', 'TPS_Nativo']].rename(columns={'Latencia_Media_Nativa': 'Lat_Caliper_Nativa', 'TPS_Nativo': 'TPS_Caliper'}),
        on='ID_Rodada'
    )
    
    # Erro Relativo %
    df_final['Erro_Relativo_%'] = (abs(df_final['Lat_Caliper_Nativa'] - df_final['Latencia_JMeter_Ajustada']) / df_final['Lat_Caliper_Nativa']) * 100
    
    # 3. Exportação
    df_final.to_csv('planilha_analise_consolidada.csv', index=False)
    print("Planilha mestre gerada com métricas de Latência Ajustada e Erro Relativo.")
