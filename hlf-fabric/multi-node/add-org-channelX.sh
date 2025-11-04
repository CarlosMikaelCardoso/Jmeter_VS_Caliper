#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

# --- Validação de Entrada ---
if [ -z "${1:-}" ]; then
    echo "ERRO: Forneça o número da organização a ser adicionada."
    echo "Exemplo: ./add-org-channelX.sh 3"
    exit 1
fi

# --- Definição de Variáveis ---
NODE_NUMBER="$1"
NODE_NAME="node${NODE_NUMBER}"
ORG_MSP="${NODE_NAME}MSP"
ORG_CA_NAME="${NODE_NAME}-ca"
ORG_CA_NAMESPACE="${NODE_NAME}-net"
ORG_ADMIN_SECRET="${NODE_NAME}-admin"

# Define os caminhos para os certificados e identidades necessários
CERTS_DIR="org_certificates/${NODE_NAME}"
SIGN_CERT_PATH="${CERTS_DIR}/${ORG_CA_NAME}-signcert.pem"
TLS_CERT_PATH="${CERTS_DIR}/${ORG_CA_NAME}-tlscert.pem"

# --- FUNÇÃO PARA APLICAR IDENTIDADE REMOTA ---
function apply_remote_org_identity() {
    local org_namespace="${NODE_NAME}-net"
    local secret_yaml_path="${CERTS_DIR}/${NODE_NAME}-admin-secret.yaml"
    local identity_yaml_path="${CERTS_DIR}/${NODE_NAME}-admin-identity.yaml"

    echo "Verificando e criando o namespace ${org_namespace} no cluster local (VM1)..."
    kubectl create namespace "${org_namespace}" --dry-run=client -o yaml | kubectl apply -f -

    echo "Verificando se os arquivos de identidade existem..."
    if [ ! -f "$secret_yaml_path" ] || [ ! -f "$identity_yaml_path" ]; then
        echo "ERRO: Arquivos de identidade não encontrados em ${CERTS_DIR}/"
        echo "Por favor, certifique-se de que a pasta 'org_certificates/${NODE_NAME}' foi copiada para a VM1."
        exit 1
    fi

    echo "Aplicando o Secret e a FabricIdentity de ${NODE_NAME} na VM1..."
    kubectl apply -f "${secret_yaml_path}" -n "${org_namespace}"
    kubectl apply -f "${identity_yaml_path}" -n "${org_namespace}"

    echo "Aguardando 10 segundos para que os recursos de identidade sejam estabelecidos..."
    sleep 10
}

# --- FUNÇÃO PARA ATUALIZAR O CANAL (VERSÃO FINAL) ---
function update_channel_definition() {
    echo "Buscando a configuração atual do canal 'demo'..."
    local original_yaml
    original_yaml=$(kubectl get fabricmainchannel demo -o yaml)

    # --- INÍCIO DA SOLUÇÃO COM SED E TEMPLATE ---

    # 1. Indenta os certificados e salva em arquivos temporários.
    sed 's/^/    /' "${SIGN_CERT_PATH}" > /tmp/indented_sign.pem
    sed 's/^/    /' "${TLS_CERT_PATH}" > /tmp/indented_tls.pem

    # 2. Cria o patch YAML com placeholders.
    cat > org_patch.yaml <<EOF
- mspID: ${ORG_MSP}
  signRootCert: |-
SIGN_CERT_PLACEHOLDER
  tlsRootCert: |-
TLS_CERT_PLACEHOLDER
EOF

    # 3. Usa 'sed' com o comando 'r' (read file) para substituir os placeholders.
    #    Isso insere o conteúdo do arquivo de forma segura, e depois deletamos a linha do placeholder.
    sed -i -e '/SIGN_CERT_PLACEHOLDER/r /tmp/indented_sign.pem' -e '/SIGN_CERT_PLACEHOLDER/d' org_patch.yaml
    sed -i -e '/TLS_CERT_PLACEHOLDER/r /tmp/indented_tls.pem' -e '/TLS_CERT_PLACEHOLDER/d' org_patch.yaml
    
    # 4. Usa yq para realizar as duas operações de forma segura:
    #    a) Carregar o patch e adicioná-lo à lista 'externalPeerOrganizations'.
    #    b) Adicionar a nova identidade ao mapa 'identities'.
    export ORG_MSP ORG_ADMIN_SECRET ORG_CA_NAMESPACE
    local modified_yaml
    modified_yaml=$(yq e '
        ( .spec.externalPeerOrganizations += load("org_patch.yaml") )
        |
        ( .spec.identities[env(ORG_MSP)] = {
            "secretKey": "user.yaml",
            "secretName": env(ORG_ADMIN_SECRET),
            "secretNamespace": env(ORG_CA_NAMESPACE)
          }
        )
    ' - <<< "${original_yaml}")

    # 5. Limpa os arquivos temporários
    rm org_patch.yaml /tmp/indented_sign.pem /tmp/indented_tls.pem

    # --- FIM DA SOLUÇÃO ---

    # 6. Aplica o YAML final
    echo "Aplicando a seguinte configuração atualizada para o canal:"
    echo "${modified_yaml}"
    echo "${modified_yaml}" | kubectl apply -f -
}


# --- FUNÇÃO PRINCIPAL ---
function main() {
    # 1. Aplica a identidade da nova organização no cluster da VM1
    apply_remote_org_identity

    # 2. Atualiza a definição do canal
    update_channel_definition

    echo "Solicitação de atualização para adicionar ${ORG_MSP} ao canal 'demo' enviada."
    echo "Aguardando o HLF Operator processar a atualização..."

    # Espera o status do canal voltar para "Running" após a atualização
    kubectl wait --for=condition=Running FabricMainChannel/demo --timeout=180s

    echo "Canal 'demo' atualizado com sucesso para incluir a organização ${ORG_MSP}!"
}

# --- Execução da Função Principal ---
main "$@"