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

if [ -z "$3" ]; then
  echo "Uso: $0 org-name peer_name channel-name"
  exit 1
fi

if [ ! -d "${config_dir}" ]; then
  config_dir="${start_dir}/fabric/configs"
fi

org_name="$1"
peer_name="$2"
channel_name="$3"
namespace="${org_name}-net"

function joinChannel(){
  helm install "${peer_name}-${channel_name}" "${chart_dir}"/fabric-channel-join --namespace "${namespace}" --values "${config_dir}"/"join-channel-${org_name}-${peer_name}.yaml"
}

main() { 
  joinChannel
}

main "$@"
