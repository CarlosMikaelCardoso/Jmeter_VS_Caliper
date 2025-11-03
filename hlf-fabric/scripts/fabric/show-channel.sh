#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode


if [ -z "$3" ]; then
  echo "Uso: $0 org-name peer_name channel-name"
  exit 1
fi

org_name="$1"
peer_name="$2"
channel_name="$3"
namespace="${org_name}-net"

function showChannel(){
  peer_cli_pod=$(kubectl get pods -o name -A  | grep "${peer_name}"-cli)

  kubectl -n "${namespace}" exec "${peer_cli_pod}" cli -- peer channel fetch config config_block.pb -c "${channel_name}"

  kubectl -n "${namespace}" exec "${peer_cli_pod}" cli -- configtxlator proto_decode --input config_block.pb --type common.Block --output config_block.json

  kubectl -n "${namespace}" exec "${peer_cli_pod}" cli -- cat  config_block.json  
}

main() { 
  showChannel
}

main "$@"