#!/usr/bin/env bash
set -o errexit  # abort on nonzero exitstatus
set -o nounset  # abort on unbound variable
set -o pipefail # don't hide errors within pipes
# set -x # debug mode

# --- VALIDAÇÃO E CONFIGURAÇÃO INICIAL ---
if [ "$#" -ne 2 ]; then
    echo "Uso: $0 <nome_do_novo_no> <config.yaml>"
    echo "Exemplo: ./add-org-chaincodeX.sh node3 config.yaml"
    exit 1
fi

NEW_NODE_NAME=$1
GENERAL_CONFIG=$2
ANCHOR_NODE_NAME="node2" # Nó âncora que já está na rede

# Verifica se os arquivos necessários foram copiados para a VM atual (VM2)
if [ ! -f "${ANCHOR_NODE_NAME}.yaml" ] || \
   [ ! -f "chaincode-configs.txt" ] || \
   [ ! -d "org_certificates/${NEW_NODE_NAME}" ] || \
   [ ! -f "${NEW_NODE_NAME}.yaml" ]; then
    echo "ERRO: Arquivos/diretórios necessários não encontrados!"
    echo "Certifique-se de que os seguintes itens existem no diretório atual:"
    echo "  - ${ANCHOR_NODE_NAME}.yaml (local)"
    echo "  - chaincode-configs.txt (local)"
    echo "  - org_certificates/node1/ (copiada da VM1)"
    echo "  - org_certificates/${NEW_NODE_NAME}/ (copiada da VM do novo nó)"
    echo "  - ${NEW_NODE_NAME}.yaml (COMPLETO, copiado da VM do novo nó)"
    exit 1
fi

source chaincode-configs.txt

# --- DEFINIÇÃO DAS VARIÁVEIS ---
NEW_ORG_MSP="${NEW_NODE_NAME}MSP"
NEW_NAMESPACE="${NEW_NODE_NAME}-net"
NEW_PEER="${NEW_NODE_NAME}-peer0.${NEW_NAMESPACE}"
NEW_PEER_ADMIN="${NEW_NODE_NAME}-admin.${NEW_NAMESPACE}"
UPDATED_ENDORSEMENT_POLICY="${ENDORSEMENT_POLICY::-1}, '${NEW_ORG_MSP}.member')"
NEXT_SEQUENCE=$((SEQUENCE + 1))

# --- FUNÇÕES ---

# Aprova apenas para o node2, que é local nesta VM
function approve_for_anchor_org() {
    echo "--- Aprovando para a organização âncora (${ANCHOR_NODE_NAME}) ---"
    
    # Captura a saída de stderr (2>&1) e armazena o código de saída
    local stderr_output
    set +o errexit # Desativa o 'exit on error' temporariamente
    stderr_output=$(kubectl hlf chaincode approveformyorg --config="${ANCHOR_NODE_NAME}.yaml" \
        --user="${ANCHOR_NODE_NAME}-admin.${ANCHOR_NODE_NAME}-net" \
        --peer="${ANCHOR_NODE_NAME}-peer0.${ANCHOR_NODE_NAME}-net" \
        --package-id=$PACKAGE_ID \
        --version "$VERSION" \
        --sequence "$NEXT_SEQUENCE" \
        --name=asset \
        --policy="${UPDATED_ENDORSEMENT_POLICY}" \
        --channel=demo 2>&1)
    
    local exit_code=$?
    set -o errexit # Reativa o 'exit on error'

    # Verifica se o comando falhou
    if [ $exit_code -ne 0 ]; then
        # Se falhou, verifica se foi pelo erro "unchanged content"
        if echo "${stderr_output}" | grep -q "unchanged content"; then
            echo "AVISO: A aprovação (Sequence ${NEXT_SEQUENCE}) já existe. Pulando."
            # Ignora o erro e continua (retorna 0)
            return 0
        else
            # Se foi outro erro, imprime o erro e falha o script
            echo "ERRO: Falha ao aprovar o chaincode:"
            echo "${stderr_output}"
            return 1 # Falha
        fi
    fi
    
    # Se chegou aqui, o comando foi bem-sucedido (exit_code == 0)
    echo "Aprovação (Sequence ${NEXT_SEQUENCE}) bem-sucedida."
    return 0
}

# function update_anchor_config_with_new_org() {
#     local config_to_update="${ANCHOR_NODE_NAME}.yaml"
    
#     echo "--- Atualizando ${config_to_update} para incluir a organização ${NEW_NODE_NAME} ---"

#     local peer_tls_cert_path="org_certificates/${NEW_NODE_NAME}/${NEW_NODE_NAME}-ca-tlscert.pem"
#     if [ ! -f "${peer_tls_cert_path}" ]; then
#         echo "ERRO: Certificado TLS do peer não encontrado em ${peer_tls_cert_path}"
#         exit 1
#     fi
#     export PEER_TLS_CERT_PEM=$(cat "${peer_tls_cert_path}")

#     local node_number=${NEW_NODE_NAME//[!0-9]/}
#     local dns_suffix=$(yq e ".vms[] | select(.name == \"vm${node_number}\") | .dns" "${GENERAL_CONFIG}")
#     if [ -z "$dns_suffix" ] || [ "$dns_suffix" == "null" ]; then
#         # Fallback para o caso de o nó estar em uma VM compartilhada (ex: node3 na vm1)
#         local current_ip=$(yq e ".vms[] | select(.name == \"vm${node_number}\")" "${GENERAL_CONFIG}" 2>/dev/null)
#         if [ -z "$current_ip" ]; then
#             local vm1_ip=$(yq e '.vms[0].ip' "$GENERAL_CONFIG")
#             dns_suffix=$(yq e ".vms[] | select(.ip == \"${vm1_ip}\") | .dns" "${GENERAL_CONFIG}")
#         fi
#         if [ -z "$dns_suffix" ] || [ "$dns_suffix" == "null" ]; then
#             echo "ERRO: Não foi possível encontrar o sufixo DNS para o nó ${NEW_NODE_NAME} em ${GENERAL_CONFIG}."
#             exit 1
#         fi
#     fi
#     local peer_url="grpcs://${NEW_PEER}.${dns_suffix}:443"

#     export NEW_PEER
#     export peer_url

#     yq e -i '
#         .peers[strenv(NEW_PEER)].url = strenv(peer_url) |
#         .peers[strenv(NEW_PEER)].grpcOptions.allow-insecure = false |
#         .peers[strenv(NEW_PEER)].tlsCACerts.pem = strenv(PEER_TLS_CERT_PEM) |
#         .channels.demo.peers[strenv(NEW_PEER)].endorsingPeer = true |
#         .channels.demo.peers[strenv(NEW_PEER)].chaincodeQuery = true |
#         .channels.demo.peers[strenv(NEW_PEER)].ledgerQuery = true |
#         .channels.demo.peers[strenv(NEW_PEER)].eventSource = true
#     ' "${config_to_update}"

#     echo "Arquivo ${config_to_update} atualizado com sucesso com as informações do peer ${NEW_PEER}."
# }


# Exibe as instruções manuais para a VM do NOVO NÓ
function display_manual_instructions() {
    # Extrai a lista de MSPs da política (ex: node2MSP,node3MSP,node4MSP)
    local COMMIT_ORGS
    COMMIT_ORGS=$(echo "${UPDATED_ENDORSEMENT_POLICY}" | grep -o "'[a-zA-Z0-9]\+MSP" | sed "s/'//g" | tr '\n' ',' | sed 's/,$//')
    
    # Define o MSP do nó âncora (o nó local que já aprovou)
    local ANCHOR_ORG_MSP="${ANCHOR_NODE_NAME}MSP"

    echo ""
    echo "========================================================================"
    echo "✅ A aprovação para ${ANCHOR_NODE_NAME} (${ANCHOR_ORG_MSP}) foi concluída."
    echo "✅ O arquivo de configuração '${ANCHOR_NODE_NAME}.yaml' foi atualizado."
    echo ""
    echo "➡️  AÇÃO MANUAL NECESSÁRIA NAS OUTRAS VMs:"
    echo ""
    echo "    - PASSO 1: APROVAR a nova definição em CADA VM remota."
    echo "------------------------------------------------------------------------"

    # Itera sobre todos os MSPs que precisam aprovar
    for ORG_MSP in $(echo "${COMMIT_ORGS}" | tr ',' ' '); do
        
        # Pula o nó âncora (local), que já aprovou
        if [ "${ORG_MSP}" == "${ANCHOR_ORG_MSP}" ]; then
            continue
        fi
        
        # Deriva os nomes do MSP (ex: node3MSP -> node3)
        local NODE_NAME=${ORG_MSP%MSP}
        local NAMESPACE="${NODE_NAME}-net"
        local PEER="${NODE_NAME}-peer0.${NAMESPACE}"
        local ADMIN_USER="${NODE_NAME}-admin.${NAMESPACE}"
        
        # Monta o comando de aprovação para este nó específico
        local approve_command="kubectl hlf chaincode approveformyorg \\
    --config=${NODE_NAME}.yaml \\
    --user=${ADMIN_USER} \\
    --peer=${PEER} \\
    --package-id=$PACKAGE_ID \\
    --version=\"$VERSION\" \\
    --sequence=\"$NEXT_SEQUENCE\" \\
    --name=asset \\
    --policy=\"${UPDATED_ENDORSEMENT_POLICY}\" \\
    --channel=demo"

        echo ""
        echo "    >>> Comando para a VM do ${NODE_NAME}:"
        echo ""
        echo -e "${approve_command}"
        echo "------------------------------------------------------------------------"
    done

    echo ""
    echo "    - PASSO 2: FAZER O COMMIT da definição (execute em APENAS UMA VM):"
    echo "    (Após TODAS as organizações (ex: node2, node3, node4) terem aprovado)"
    echo "------------------------------------------------------------------------"
    echo "    Você pode executar o commit a partir de qualquer nó que aprovou."
    echo "    Exemplo (executando a partir do ${NEW_NODE_NAME}, mas poderia ser o node3):"
    
    # Monta um comando de commit de *exemplo* (pode ser executado de qualquer nó)
    local commit_command="kubectl hlf chaincode commit \\
    --channel=demo \\
    --name=asset \\
    --version=\"$VERSION\" \\
    --sequence=\"$NEXT_SEQUENCE\" \\
    --policy=\"${UPDATED_ENDORSEMENT_POLICY}\" \\
    --config=${NEW_NODE_NAME}.yaml \\
    --user=${NEW_PEER_ADMIN} \\
    --commit-orgs=\"${COMMIT_ORGS}\" \\
    --mspid=${NEW_ORG_MSP}"
    
    echo -e "${commit_command}"
    echo "------------------------------------------------------------------------"
    echo ""
    echo "========================================================================"
    echo ""
    read -p "Pressione [Enter] APÓS ter executado os comandos manuais nas outras VMs para continuar..."
}

# Salva a configuração para o próximo ciclo
function save_configs() {
    echo "Salvando configurações atualizadas em chaincode-configs.txt..."
    cat <<EOF > chaincode-configs.txt
CHAINCODE_NAME=${CHAINCODE_NAME}
CHAINCODE_LABEL=${CHAINCODE_LABEL}
VERSION=${VERSION}
PACKAGE_ID=${PACKAGE_ID}
SEQUENCE=${NEXT_SEQUENCE}
ENDORSEMENT_POLICY="${UPDATED_ENDORSEMENT_POLICY}"
EOF
    echo "Configurações salvas com sucesso."
}

# --- FLUXO DE EXECUÇÃO PRINCIPAL ---
main() {
    # 1. [MODIFICADO] A função 'approve_for_anchor_org' agora
    # lida com o caso de "já aprovado" internamente.
    approve_for_anchor_org
    
    # 2. Salva as configurações
    save_configs

    # 4. Pausa e exibe as instruções manuais
    display_manual_instructions
    
    echo "Processo concluído!"
}

main "$@"