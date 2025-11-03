#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

if [[ "$#" -lt 1 ]]; then
    echo "Uso: setup-besu-vm1.sh <tipo-rede>"
    echo "Tipos de rede suportados: single, multi, iliada_v2"
    exit 1
fi


NETWORK_TYPE="$1"
AMBASSADOR_VERSION="8.7.2"

repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../../ && pwd -P)
besu_dir="${repository_dir}/lab-single-node/besu/"

case "$NETWORK_TYPE" in
    single)
        besu_dir="${repository_dir}/lab-single-node/besu"
        ;;
    multi)
        besu_dir="${repository_dir}/lab-multi-node/besu"
        ;;
    iliada_v2)
        besu_dir="${repository_dir}/iliada_v2/besu"
        ;;
    *)
        echo "Tipo de rede inválido: $NETWORK_TYPE"
        exit 1
        ;;
esac

config_dir="${besu_dir}/configs"


VM_IP=$(ip -o route get to 8.8.8.8 | sed -n 's/.*src \([0-9.]+\).*/\1/p')

function setupAmbassador(){
  helm repo add datawire https://app.getambassador.io
  kubectl apply -f "${config_dir}/aes-crds.yaml"
  sleep 50
  kubectl wait --timeout=120s --for=condition=available deployment emissary-apiext -n emissary-system
  
  if [[ -z $(kubectl get namespaces | grep ambassador) ]]; then
    kubectl create namespace ambassador
  fi
  
  sleep 40
  helm upgrade --install edge-stack datawire/edge-stack --namespace ambassador --version ${AMBASSADOR_VERSION} -f "${config_dir}/aes.yaml" --set adminService.loadBalancerSourceRanges="${VM_IP}:${VM_IP}" 
  
  sleep 40
  kubectl -n ambassador wait --for condition=available --timeout=120s deploy -l product=aes
}

main() { 
  setupAmbassador 
}

main "$@"