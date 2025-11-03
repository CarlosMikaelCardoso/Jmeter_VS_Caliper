#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

if [[ "$#" -lt 3 ]]; then
    echo "Uso: install-requirements.sh <ip1> <ip2> <ip-dns>"
    exit 1
fi

IP1="$1"
IP2="$2"
DNS_SERVER_IP="$3"

function installRequirements(){
  sudo microk8s enable hostpath-storage  
  sudo microk8s enable metallb:"${IP1}-${IP2}"
  sudo microk8s enable dns:"$DNS_SERVER_IP"
  
  if [ -L "/etc/resolv.conf" ]; then
    sudo unlink /etc/resolv.conf
  fi
  echo "nameserver ${DNS_SERVER_IP}" | sudo tee /etc/resolv.conf > /dev/null
    
  kubectl delete pods -n kube-system -l k8s-app=calico-node
} 

main() { 
  installRequirements
}

main "$@"