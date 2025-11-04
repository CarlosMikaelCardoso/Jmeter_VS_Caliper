import subprocess
import json
import os
import sys

# --- Configurações da Rede ---
CONFIG_FILE = "node2.yaml"
USER = "node2-admin.node2-net"
PEER = "node2-peer0.node2-net"
CHAINCODE_NAME = "asset"
CHANNEL_NAME = "demo"
# -----------------------------

def clear_screen():
    """Limpa o ecrã do terminal."""
    os.system('cls' if os.name == 'nt' else 'clear')

def run_command(command_type, fcn, args=[]):
    """
    Executa um comando kubectl (query ou invoke) e imprime o resultado.
    
    Args:
        command_type (str): "query" ou "invoke".
        fcn (str): O nome da função do chaincode a ser chamada.
        args (list): Uma lista de argumentos para a função.
    """
    base_cmd = [
        "kubectl", "hlf", "chaincode", command_type,
        "--config", CONFIG_FILE,
        "--user", USER,
        "--peer", PEER,
        "--chaincode", CHAINCODE_NAME,
        "--channel", CHANNEL_NAME,
        "--fcn", fcn
    ]

    for arg in args:
        base_cmd.extend(["-a", arg])

    print("Executando o comando:")
    print(" ".join(f'"{item}"' if ' ' in item else item for item in base_cmd))
    print("-" * 30)

    try:
        # Executa o comando e captura a saída
        result = subprocess.run(base_cmd, capture_output=True, text=True, check=True)
        
        # Tenta formatar a saída como JSON, se possível
        try:
            parsed_json = json.loads(result.stdout)
            print("Resultado (JSON formatado):")
            print(json.dumps(parsed_json, indent=4))
        except json.JSONDecodeError:
            print("Resultado:")
            print(result.stdout)

    except subprocess.CalledProcessError as e:
        # Se o comando falhar, imprime a mensagem de erro
        print("❌ Erro ao executar o comando!", file=sys.stderr)
        print(e.stderr, file=sys.stderr)


def get_asset_details():
    """Pede ao utilizador os detalhes completos de um ativo."""
    asset_id = input("  - Digite o ID do ativo (ex: asset10): ")
    color = input("  - Digite a Cor: ")
    size = input("  - Digite o Tamanho (número): ")
    owner = input("  - Digite o Dono: ")
    appraised_value = input("  - Digite o Valor Avaliado (número): ")
    return [asset_id, color, size, owner, appraised_value]

# Comentário sobre a modificação:
# A função main() foi completamente refatorada para remover o menu interativo.
# Agora, ela analisa os argumentos passados na linha de comando e chama a
# função correspondente, priorizando a parametrização do script. Se não houver
# parâmetros válidos, ela exibe uma mensagem de uso.
#
def main():
    COMMAND_USAGE = {
    "ReadAsset": {
        "description": "Lê os detalhes de um ativo.",
        "params": ["<asset_id>"],
        "example": "python3 chainCodeCLI.py ReadAsset asset1"
    },
    "AssetExists": {
        "description": "Verifica se um ativo existe.",
        "params": ["<asset_id>"],
        "example": "python3 chainCodeCLI.py AssetExists asset3"
    },
    "GetAllAssets": {
        "description": "Lista todos os ativos no ledger.",
        "params": [],
        "example": "python3 chainCodeCLI.py GetAllAssets"
    },
    "CreateAsset": {
        "description": "Cria um novo ativo.",
        "params": ["<asset_id>", "<color>", "<size>", "<owner>", "<appraised_value>"],
        "example": "python3 chainCodeCLI.py CreateAsset asset10 red 20 owner1 500"
    },
    "UpdateAsset": {
        "description": "Atualiza um ativo existente.",
        "params": ["<asset_id>", "<color>", "<size>", "<owner>", "<appraised_value>"],
        "example": "python3 chainCodeCLI.py UpdateAsset asset10 blue 25 newOwner 600"
    },
    "TransferAsset": {
        "description": "Transfere a posse de um ativo para um novo dono.",
        "params": ["<asset_id>", "<new_owner>"],
        "example": "python3 chainCodeCLI.py TransferAsset asset1 owner2"
    },
    "DeleteAsset": {
        "description": "Deleta um ativo.",
        "params": ["<asset_id>"],
        "example": "python3 chainCodeCLI.py DeleteAsset asset1"
    },
    "InitLedger": {
        "description": "Reinicia o ledger com dados iniciais de teste.",
        "params": [],
        "example": "python3 chainCodeCLI.py InitLedger"
    }
    }
    
    """Analisa os argumentos da linha de comando para chamar as funções."""
    if len(sys.argv) < 2:
        print("Uso: python seu_script.py <comando> [argumentos]")
        print("Comandos disponíveis: ReadAsset, AssetExists, GetAllAssets, CreateAsset, UpdateAsset, TransferAsset, DeleteAsset, InitLedger")
        print("Exemplo: python seu_script.py ReadAsset asset1")
        sys.exit(1)

    command = sys.argv[1]
    args = sys.argv[2:]

    # Mapeamento dos comandos para as funções e seus tipos
    commands = {
        "ReadAsset": {"type": "query", "fcn": "ReadAsset"},
        "AssetExists": {"type": "query", "fcn": "AssetExists"},
        "GetAllAssets": {"type": "query", "fcn": "GetAllAssets"},
        "CreateAsset": {"type": "invoke", "fcn": "CreateAsset"},
        "UpdateAsset": {"type": "invoke", "fcn": "UpdateAsset"},
        "TransferAsset": {"type": "invoke", "fcn": "TransferAsset"},
        "DeleteAsset": {"type": "invoke", "fcn": "DeleteAsset"},
        "InitLedger": {"type": "invoke", "fcn": "InitLedger"},
    }

    if command in commands:
        cmd_info = commands[command]
        run_command(cmd_info["type"], cmd_info["fcn"], args)
    else:
        print(f"❌ Comando '{command}' não reconhecido.")
        sys.exit(1)

if __name__ == "__main__":
    main()