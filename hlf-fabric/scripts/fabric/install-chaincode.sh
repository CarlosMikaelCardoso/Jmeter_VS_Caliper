#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

start_dir=$(pwd)
repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../../ && pwd -P)
tmp_dir="${repository_dir}/tmp"
chart_dir="${tmp_dir}/bevel/platforms/hyperledger-fabric/charts"
config_dir="${start_dir}/configs" 

if [ -z "$2" ]; then
  echo "Uso: $0 org-name chaincode-name"
  exit 1
fi

if [ ! -d "${config_dir}" ]; then
  config_dir="${start_dir}/fabric/configs"
fi

org_name="$1"
chaincode_name="$2"
namespace="${org_name}-net"

function installChaincode(){
  helm install "${chaincode_name}-${org_name}" ${chart_dir}/fabric-external-chaincode-install --namespace "${namespace}" --values ${config_dir}/install-chaincode.yaml
}

main() { 
  installChaincode
}

main "$@"
