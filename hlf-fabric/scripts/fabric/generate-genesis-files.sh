#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../../ && pwd -P)
tmp_dir="${repository_dir}/tmp"
chart_dir="${tmp_dir}/bevel/platforms/hyperledger-fabric/charts"

if [ -z "$2" ]; then
  echo "Uso: $0 org-name peer-name"
  exit 1
fi

org_name="$1"
peer_name="$2"
namespace="${org_name}-net"

function copyGenesisFiles() {
  echo "Iniciando a criação dos arquivos genesis..."

  # Obtendo os segredos e configmaps para a organização
  kubectl --namespace "${namespace}" get secret admin-msp -o json > "${chart_dir}"/fabric-genesis/files/"${org_name}".json
  kubectl --namespace "${namespace}" get configmap "${peer_name}"-msp-config -o json > "${chart_dir}"/fabric-genesis/files/"${org_name}"-config-file.json

  echo "Criação dos arquivos genesis concluída."
  echo "Arquivos disponíveis em: ${chart_dir}/fabric-genesis/files/"
}

main() { 
  copyGenesisFiles
}

main "$@"
