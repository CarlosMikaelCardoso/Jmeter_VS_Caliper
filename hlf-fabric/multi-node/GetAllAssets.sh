#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes

# Este script descobre quais ativos existem no ledger, iterando por uma
# lista de possíveis IDs (de 1 a 15). Para cada ID, ele primeiro usa a
# função 'AssetExists' e, se o resultado for 'true', ele então usa a
# função 'ReadAsset' para obter e exibir os detalhes completos do ativo.

echo "Buscando por ativos existentes no ledger..."
echo "-----------------------------------------"

# Itera de 1 a 15 para testar os IDs "asset1", "asset2", etc.
for i in {1..15}; do
    ASSET_ID="asset${i}"

    echo "Verificando se o '${ASSET_ID}' existe..."

    # Usa a função AssetExists para verificar a existência do ativo.
    # A saída 'true' ou 'false' é capturada na variável 'EXISTS'.
    EXISTS=$(kubectl hlf chaincode query --config=ifba.yaml \
        --user=ifba-admin-ifba-net \
        --peer=ifba-peer0.ifba-net \
        --chaincode=asset \
        --channel=demo \
        --fcn=AssetExists -a "$ASSET_ID")

    # Se o ativo existir, busca os seus detalhes com ReadAsset
    if [ "$EXISTS" = "true" ]; then
        echo "  -> Encontrado! Lendo os dados do '${ASSET_ID}'..."
        
        # Chama a função ReadAsset e formata a saída JSON com o 'jq'
        kubectl hlf chaincode query --config=ifba.yaml \
            --user=ifba-admin-ifba-net \
            --peer=ifba-peer0.ifba-net \
            --chaincode=asset \
            --channel=demo \
            --fcn=ReadAsset -a "$ASSET_ID" | jq .
            
        echo "-----------------------------------------"
    else
        # Se não existir, podemos parar de procurar, assumindo que os IDs são sequenciais.
        echo "  -> Não encontrado. Parando a busca."
        break
    fi
done

echo "Busca concluída."