#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

if [[ "$#" -lt 1 ]]; then
    echo "Uso: refresh-genesis-files.sh <org>"
    exit 1
fi

ORG="$1"


repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../../&& pwd -P)
file_dir="${repository_dir}/tmp/bevel/platforms/hyperledger-besu/charts/besu-genesis/files/"


function refreshGenesisFiles(){
  cd "$file_dir"

  echo "Atualizando genesis.json, static-nodes.json e bootnodes.json..."
  kubectl --namespace "${ORG}-bes" get configmap besu-peers -o jsonpath='{.data.static-nodes\.json}' > static-nodes.json
  kubectl --namespace "${ORG}-bes" get configmap besu-genesis  -o jsonpath='{.data.genesis\.json}' > genesis.json
  kubectl --namespace "${ORG}-bes" get configmap besu-bootnodes  -o jsonpath='{.data.bootnodes-json}' > bootnodes.json
  
  echo "Arquivos genesis atualizados com sucesso."
}

main() { 
  refreshGenesisFiles 
}

main "$@"
