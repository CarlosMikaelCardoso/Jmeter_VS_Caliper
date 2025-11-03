#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

start_dir=$(pwd)
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../../ && pwd -P)
tmp_dir="${repository_dir}/tmp"
config_dir="${start_dir}/configs"
chart_dir="${tmp_dir}/bevel/platforms/hyperledger-fabric/charts"

if [ -z "$1" ]; then
  echo "Uso: $0 org-name"
  exit 1
fi

if [ ! -d "${config_dir}" ]; then
  config_dir="${start_dir}/fabric/configs"
fi

org_name="$1"
namespace="${org_name}-net"

function installGenesis() {
  echo "Iniciando a criação dos arquivos genesis..."

  
  helm install genesis "${chart_dir}/fabric-genesis" --namespace "${namespace}" --values "${config_dir}/genesis.yaml"
  echo "Instalação do genesis concluída."
  
  echo "Aguardando o pod genesis ser iniciado..."
  kubectl wait --namespace "${namespace}" --for=condition=complete --timeout=120s job/genesis-job
  
  echo "Instalação do genesis concluída."
}


main() { 
  installGenesis
}

main "$@"
