#!/usr/bin/env bash

# Para o script se houver erros, variáveis não definidas, ou erro em um pipe
set -o errexit
set -o nounset
set -o pipefail

# --- VARIÁVEIS DE CONFIGURAÇÃO ---

# O diretório DE ONDE você copiou os arquivos da sua rede (onde está seu node2.yaml original)
# (Baseado no seu log de terminal: gercom@gercom:~/Jmeter_VS_Caliper/hlf-fabric/multi-node$)
SOURCE_NETWORK_DIR="$HOME/Jmeter_VS_Caliper/hlf-fabric/multi-node"

# O diretório ATUAL (onde o caliper-benchmarks está)
CALIPER_WORKSPACE_DIR=./caliper

# Arquivo 'node2.yaml' original da sua rede
SOURCE_NODE2_YAML="${SOURCE_NETWORK_DIR}/node2.yaml"

# Arquivo de perfil de conexão que o Caliper usará (na raiz do workspace)
# Este é o arquivo que o "worker" do Caliper procura
CONNECTION_PROFILE_DST="${CALIPER_WORKSPACE_DIR}/node2-connection-profile.yaml"

# Arquivo de configuração de rede do Caliper (onde colocamos os PEMs)
CALIPER_NETWORK_CONFIG="${CALIPER_WORKSPACE_DIR}/networks/fabric/minha-rede-hlf.yaml"

# O arquivo de benchmark que vamos usar
BENCHMARK_CONFIG="${CALIPER_WORKSPACE_DIR}/simple/config.yaml"

# --- FIM DA CONFIGURAÇÃO ---

# Função para verificar se um comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# PASSO 0: Verificar dependências (jq ou yq)
if ! command_exists yq && ! command_exists jq; then
    echo "ERRO: Este script precisa de 'yq' ou 'jq' para extrair as chaves do YAML."
    echo "Por favor, instale um dos dois e tente novamente."
    exit 1
fi

# Função segura para extrair dados do YAML
get_yaml_data() {
    local query=$1
    local file=$2
    if command_exists yq; then
        yq e "$query" "$file"
    else
        # Fallback para jq (requer conversão de yaml para json)
        # Esta é uma dependência extra, mas 'yq' já estava nos seus scripts
        echo "ERRO: 'yq' não encontrado. Por favor, instale 'yq'."
        exit 1
    fi
}

echo "--- [PASSO 1/6] Instalando dependências do Caliper ---"
npm install --only=prod @hyperledger/caliper-cli
npx caliper bind --caliper-bind-sut fabric:2.4

echo "--- [PASSO 2/6] Localizando arquivos de rede ---"
if [ ! -f "$SOURCE_NODE2_YAML" ]; then
    echo "ERRO: Arquivo 'node2.yaml' original não encontrado em ${SOURCE_NODE2_YAML}"
    exit 1
fi
echo "Arquivo de rede de origem encontrado."

# Copia o node2.yaml para a raiz do workspace, onde o worker do Caliper espera
cp "$SOURCE_NODE2_YAML" "$CONNECTION_PROFILE_DST"
echo "Perfil de conexão copiado para ${CONNECTION_PROFILE_DST}"

echo "--- [PASSO 3/6] Extraindo credenciais do admin ---"
ADMIN_CERT_PEM_RAW=$(get_yaml_data '.organizations.node2MSP.users."node2-admin.node2-net".cert.pem' "$SOURCE_NODE2_YAML")
ADMIN_KEY_PEM_RAW=$(get_yaml_data '.organizations.node2MSP.users."node2-admin.node2-net".key.pem' "$SOURCE_NODE2_YAML")

# MODIFICAÇÃO: Aumentado para 20 espaços para garantir a indentação correta do YAML
ADMIN_CERT_PEM_INDENTED=$(echo "${ADMIN_CERT_PEM_RAW}" | sed 's/^/                    /')
ADMIN_KEY_PEM_INDENTED=$(echo "${ADMIN_KEY_PEM_RAW}" | sed 's/^/                    /')

if [ -z "$ADMIN_CERT_PEM_RAW" ] || [ -z "$ADMIN_KEY_PEM_RAW" ]; then
    echo "ERRO: Não foi possível extrair o certificado ou a chave do admin de ${SOURCE_NODE2_YAML}."
    exit 1
fi
echo "Credenciais extraídas e indentadas com sucesso."

echo "--- [PASSO 4/6] Criando arquivo de configuração de rede do Caliper ---"
# Cria o 'minha-rede-hlf.yaml' com o caminho correto e os PEMs embutidos
cat << EOF > "$CALIPER_NETWORK_CONFIG"
name: Minha Rede HLF Operator
version: "2.0.0"
caliper:
  blockchain: fabric

channels:
  - channelName: demo
    contracts:
    - id: asset

organizations:
  - mspid: node2MSP
    connectionProfile:
      # Aponte para o arquivo na raiz do workspace
      path: './caliper/node2-connection-profile.yaml'
      discover: true
      
    identities:
      certificates:
        - name: 'node2-admin.node2-net'
          clientPrivateKey:
            pem: |-
${ADMIN_KEY_PEM_INDENTED}
          clientSignedCert:
            pem: |-
${ADMIN_CERT_PEM_INDENTED}
EOF
echo "Arquivo ${CALIPER_NETWORK_CONFIG} criado."

echo "--- [PASSO 5/6] Configuração do benchmark concluída ---"
# Não é necessário editar o config.yaml, pois ele já aponta para os arquivos .js que substituímos.

echo "--- [PASSO 6/6] Iniciando o benchmark... ---"
npx caliper launch manager \
  --caliper-workspace ./ \
  --caliper-networkconfig "$CALIPER_NETWORK_CONFIG" \
  --caliper-benchconfig "$BENCHMARK_CONFIG" \
  --caliper-flow-only-test \
  --caliper-fabric-gateway-enabled

echo "--- Benchmark concluído! ---"
echo "Relatório salvo em: ${CALIPER_WORKSPACE_DIR}/report.html"