#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

start_dir=$(pwd)
config_dir="${start_dir}/configs"
repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../../ && pwd -P)
tmp_dir="${repository_dir}/tmp"
chart_dir="${tmp_dir}/bevel/platforms/hyperledger-fabric/charts"

if [ -z "$2" ]; then
  echo "Uso: $0 org-name channel-name"
  exit 1
fi

if [ ! -d "${config_dir}" ]; then
  config_dir="${start_dir}/fabric/configs"
fi

org_name="$1"
channel_name="$2"
namespace="${org_name}-net"

function createChannel(){
  
  helm install "${channel_name}" "${chart_dir}"/fabric-osnadmin-channel-create --namespace "${namespace}" --values "${config_dir}"/channel-create.yaml
  
}

main() { 
  createChannel
}

main "$@"