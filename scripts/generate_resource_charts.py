import os
import sys
import glob
import json
import pandas as pd
import matplotlib.pyplot as plt

def clean_percentage(val):
    """Converte '10.5%' ou '10,5%' para float 10.5"""
    if pd.isna(val): return 0.0
    s = str(val).replace('%', '').replace(',', '.')
    try:
        return float(s)
    except:
        return 0.0

def clean_memory(val):
    """Converte '100MiB', '1GiB' para float em MiB"""
    if pd.isna(val): return 0.0
    s = str(val).replace(',', '.') # Troca virgula decimal
    # Remove limite se houver (ex: "100MiB / 1GiB")
    if '/' in s:
        s = s.split('/')[0].strip()
    
    try:
        if 'GiB' in s:
            return float(s.replace('GiB', '').strip()) * 1024
        elif 'MiB' in s:
            return float(s.replace('MiB', '').strip())
        elif 'kB' in s:
            return float(s.replace('kB', '').strip()) / 1024
        elif 'B' in s:
            return float(s.replace('B', '').strip()) / (1024*1024)
        else:
            # Tenta converter direto se for apenas número
            return float(s)
    except:
        return 0.0

def parse_docker_stats(filepath):
    """
    Lê arquivo docker stats suportando JSON, CSV e TXT (Raw).
    """
    filename = os.path.basename(filepath)
    data_list = []

    try:
        # --- TENTATIVA 1: LER COMO CSV (Pandas) ---
        # Mesmo se chamar .json, o conteúdo pode ser CSV.
        # on_bad_lines='skip' ignora linhas quebradas
        try:
            df = pd.read_csv(filepath, sep=None, engine='python', on_bad_lines='skip')
            
            # Normaliza colunas para minusculo para facilitar busca
            df.columns = [c.lower().strip() for c in df.columns]
            
            # Verifica se tem as colunas essenciais
            col_container = next((c for c in df.columns if 'container' in c or 'name' in c), None)
            col_cpu = next((c for c in df.columns if 'cpu' in c), None)
            col_mem = next((c for c in df.columns if 'mem' in c), None)

            if col_container and col_cpu and col_mem:
                # Limpeza de dados
                df['Container'] = df[col_container]
                df['CPU'] = df[col_cpu].apply(clean_percentage)
                df['Mem'] = df[col_mem].apply(clean_memory)
                
                # Retorna lista de dicts
                return df[['Container', 'CPU', 'Mem']].to_dict('records')
        except Exception as e_csv:
            # Não é um CSV válido ou estruturado, continua...
            pass

        # --- TENTATIVA 2: LER COMO JSON ---
        with open(filepath, 'r') as f:
            content = f.read().strip()
            
        if content.startswith('[') or content.startswith('{'):
            try:
                json_data = json.loads(content)
                if isinstance(json_data, list):
                    for entry in json_data:
                        # Busca chaves insensível a maiúsculas/minúsculas
                        keys = {k.lower(): v for k, v in entry.items()}
                        
                        name = keys.get('name', keys.get('container', 'unknown'))
                        cpu_val = clean_percentage(keys.get('cpu_perc', keys.get('cpu', '0')))
                        mem_val = clean_memory(keys.get('mem_usage', keys.get('mem', '0')))
                        
                        data_list.append({'Container': name, 'CPU': cpu_val, 'Mem': mem_val})
                    return data_list
            except:
                pass

        # --- TENTATIVA 3: LER COMO TEXTO PURO (Docker Stats Raw) ---
        # Formato: NAME CPU % MEM USAGE...
        lines = content.splitlines()
        start_idx = 1 if lines and ("NAME" in lines[0] or "CONTAINER" in lines[0]) else 0
        
        for line in lines[start_idx:]:
            parts = line.split()
            if len(parts) < 3: continue
            
            # Assume Coluna 0 ou 1 é nome
            name = parts[0]
            # Se a primeira coluna parece ID (hash), pega a segunda
            if len(parts[0]) > 8 and parts[0].isalnum() and "peer" not in parts[0]:
                if len(parts) > 1: name = parts[1]
            
            # Procura valores na linha na força bruta
            cpu_val = 0.0
            mem_val = 0.0
            
            for part in parts:
                if '%' in part:
                    v = clean_percentage(part)
                    if v > 0 and cpu_val == 0: cpu_val = v
                if ('MiB' in part or 'GiB' in part):
                    v = clean_memory(part)
                    if v > 0 and mem_val == 0: mem_val = v
            
            if cpu_val > 0 or mem_val > 0:
                data_list.append({'Container': name, 'CPU': cpu_val, 'Mem': mem_val})
                
    except Exception as e:
        print(f"   [ERRO] Falha crítica em {filename}: {e}")
        
    return data_list

def plot_bar_chart(df, metric, unit, output_path, title):
    if df.empty: return

    # Filtra containers irrelevantes se necessário
    # df = df[df['Container'].str.contains('peer|orderer', case=False)]

    df = df.sort_values('Container')
    
    plt.style.use('ggplot')
    fig, ax = plt.subplots(figsize=(12, 6))
    
    colors = []
    for name in df['Container']:
        name_lower = str(name).lower()
        if 'peer' in name_lower: colors.append('#3498db') 
        elif 'orderer' in name_lower: colors.append('#e74c3c')
        else: colors.append('#95a5a6')
    
    bars = ax.bar(df['Container'], df[metric], color=colors, width=0.6)
    
    ax.set_title(title, fontsize=14)
    ax.set_ylabel(f"Média {metric} ({unit})", fontsize=12)
    ax.set_xlabel("Container", fontsize=12)
    plt.xticks(rotation=45, ha='right')
    
    # Adiciona valores acima das barras
    for bar in bars:
        height = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2., height,
                f'{height:.2f}', ha='center', va='bottom', fontsize=9, fontweight='bold')
    
    plt.tight_layout()
    plt.savefig(output_path)
    plt.close()
    print(f"✅ Gráfico gerado: {os.path.basename(output_path)}")

def process_scenario(input_dir, output_dir, scenario):
    # Procura arquivos com nome do cenário
    files = glob.glob(os.path.join(input_dir, f"*docker_stats*{scenario}*"))
    
    if not files:
        return

    print(f"   -> Processando {len(files)} arquivos para '{scenario}'...")

    all_stats = []
    for f in files:
        stats = parse_docker_stats(f)
        if stats:
            all_stats.extend(stats)
        else:
            # Debug silencioso: descomente se precisar
            # print(f"      [AVISO] Nenhum dado extraído de {os.path.basename(f)}")
            pass
        
    if not all_stats:
        print(f"⚠️  Dados vazios para cenário '{scenario}' após parsing.")
        return
    
    df = pd.DataFrame(all_stats)
    
    # Limpa nomes de containers (remove sufixos aleatórios se houver)
    # df['Container'] = df['Container'].apply(lambda x: x.split('.')[0])
    
    # Agrupa por Container e tira a média
    summary = df.groupby('Container').mean(numeric_only=True).reset_index()
    
    plot_bar_chart(summary, 'CPU', '%', 
                  os.path.join(output_dir, f"bar_cpu_{scenario}.png"),
                  f"Consumo CPU - {scenario.capitalize()}")
                  
    plot_bar_chart(summary, 'Mem', 'MiB', 
                  os.path.join(output_dir, f"bar_mem_{scenario}.png"),
                  f"Consumo Memória - {scenario.capitalize()}")

def main():
    if len(sys.argv) < 3:
        print("Uso: python3 generate_resource_charts.py <input> <output>")
        sys.exit(1)

    input_dir = sys.argv[1]
    output_dir = sys.argv[2]
    
    print(f"--- Gerando Gráficos Docker ---")
    for scen in ['open', 'query', 'transfer']:
        process_scenario(input_dir, output_dir, scen)

if __name__ == "__main__":
    main()