import os
import csv
import glob
import re
import numpy as np
from bs4 import BeautifulSoup
from datetime import datetime

def processar_jmeter(base_dir):
    resultados = []
    # Analisar de round_1 até round_32
    for rodada in range(1, 33):
        tps_list = []
        latencies = []
        
        # --- [MODIFICAÇÃO: Captura de Overhead da API] ---
        # Localização: jmeter_runs/round_X/api.log
        api_log_path = os.path.join(base_dir, f'round_{rodada}', 'api.log')
        overhead_medio = 0
        overhead_variancia = 0
        
        if os.path.exists(api_log_path):
            req_timestamps = {} # Estrutura: {ReqID: [T1, T2]}
            with open(api_log_path, 'r', encoding='utf-8') as f:
                for line in f:
                    # Extrair Timestamp e ReqID
                    ts_match = re.search(r'\[(.*?)\] ReqID:(\w+)', line)
                    if ts_match:
                        ts_str, req_id = ts_match.groups()
                        # Converter para objeto datetime (mantendo milissegundos)
                        ts = datetime.strptime(ts_str[:23], '%Y-%m-%dT%H:%M:%S.%f')
                        
                        if req_id not in req_timestamps:
                            req_timestamps[req_id] = [None, None]
                        
                        if 'Recebido do JMeter' in line:
                            req_timestamps[req_id][0] = ts # T1
                        elif 'Enviado para Blockchain' in line:
                            req_timestamps[req_id][1] = ts # T2
            
            # Calcular Deltas (T2 - T1) em milissegundos
            deltas = []
            for r_id, times in req_timestamps.items():
                if times[0] and times[1]:
                    delta = (times[1] - times[0]).total_seconds() * 1000
                    deltas.append(delta)
            
            if deltas:
                overhead_medio = round(np.mean(deltas), 4)
                overhead_variancia = round(np.var(deltas), 4)
        # --- [FIM DA MODIFICAÇÃO] ---

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
            tps_estimado = len(latencies) / (sum(latencies)/1000) if sum(latencies) > 0 else 0
            
            resultados.append({
                'ID_Rodada': rodada,
                'Ferramenta': 'JMeter',
                'TPS_Nativo': round(tps_estimado, 2),
                'Latencia_Media_Nativa': round(lat_media, 2),
                'Latencia_P99_Nativa': round(lat_p99, 2),
                'Overhead_Medio_ms': overhead_medio,   # Nova coluna
                'Overhead_Variancia': overhead_variancia # Nova coluna
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
                tabelas = soup.find_all('table')
                for tabela in tabelas:
                    headers = [th.text.strip() for th in tabela.find_all('th')]
                    if 'Throughput (TPS)' in headers and 'Avg Latency (s)' in headers:
                        idx_tps = headers.index('Throughput (TPS)')
                        idx_avg = headers.index('Avg Latency (s)')
                        idx_p99 = headers.index('99%ile Latency (s)') if '99%ile Latency (s)' in headers else headers.index('Max Latency (s)')
                        
                        rows = tabela.find_all('tr')[1:]
                        for row in rows:
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
                'Overhead_Medio_ms': 0, # Caliper não possui adaptador intermediário
                'Overhead_Variancia': 0
            })
            
    return resultados

def aplicar_saneamento(dados, log_file):
    caliper_data = [d for d in dados if d['Ferramenta'] == 'Caliper']
    jmeter_data = [d for d in dados if d['Ferramenta'] == 'JMeter']
    dados_finais = []
    
    for ferramenta, dataset in [('JMeter', jmeter_data), ('Caliper', caliper_data)]:
        if not dataset: continue
        
        # 1. Remover Cold Start (Rodada 1)
        dataset_limpo = [d for d in dataset if d['ID_Rodada'] != 1]
        log_file.write(f"[{ferramenta}] Rodada 1 descartada por Cold Start.\n")
        
        # 2. Identificar Outlier (Maior desvio em Latência Média)
        if dataset_limpo:
            latencias = [d['Latencia_Media_Nativa'] for d in dataset_limpo]
            media_geral = np.mean(latencias)
            outlier = max(dataset_limpo, key=lambda x: abs(x['Latencia_Media_Nativa'] - media_geral))
            dataset_limpo.remove(outlier)
            log_file.write(f"[{ferramenta}] Rodada {outlier['ID_Rodada']} descartada por Outlier (Latência: {outlier['Latencia_Media_Nativa']} ms).\n")
        
        # Garantir as 30 rodadas estáveis
        dados_finais.extend(dataset_limpo[:30])
        
    return dados_finais

if __name__ == "__main__":
    # Caminhos base baseados na sua estrutura
    jmeter_path = '../results/jmeter_runs'
    caliper_path = '../results/caliper_runs'
    
    dados_brutos = []
    dados_brutos.extend(processar_caliper(caliper_path))
    dados_brutos.extend(processar_jmeter(jmeter_path))
    
    with open('saneamento_log.txt', 'w', encoding='utf-8') as log:
        dados_validados = aplicar_saneamento(dados_brutos, log)
        
    # Salvar planilha consolidada com as métricas de overhead
    with open('planilha_analise_consolidada.csv', 'w', newline='', encoding='utf-8') as f:
        fieldnames = [
            'ID_Rodada', 'Ferramenta', 'TPS_Nativo', 
            'Latencia_Media_Nativa', 'Latencia_P99_Nativa', 
            'Overhead_Medio_ms', 'Overhead_Variancia'
        ]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(dados_validados)
        
    print("Processamento concluído. Verifique 'planilha_analise_consolidada.csv'.")