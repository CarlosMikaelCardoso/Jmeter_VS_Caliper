#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
#set -x           # debug mode

CPU=2
MEMORY=4
DISK=15

if [[ "$#" == 1 ]]; then
     NUMBER_OF_VMs="$1"
elif [[ "$#" == 4 ]]; then
     NUMBER_OF_VMs="$1"
     CPU="$2"
     MEMORY="$3"
     DISK="$4"
else
     echo "Use: ${0} NUMBER_OF_VMs"
     echo "ou"
     echo "Use: ${0} NUMBER_OF_VMs CPU MEMORY(GB) DISK(GB)"
     exit
fi

SERVER_IP=$(ip -o route get to 8.8.8.8 | awk '{print $7}')

start_dir=$(pwd)
repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../ && pwd -P)

host_name=$(hostname)


function updateSystemPackages() {
  sudo apt update 
  #sudo apt -y upgrade
}

function configureHostNamespace() {
  if grep -q "127.0.1.1   $host_name" /etc/hosts; then
    echo "Namespace $host_name já está configurado no /etc/hosts."
  else
    echo "127.0.1.1   $host_name" | sudo tee -a /etc/hosts > /dev/null
  fi
}

function installRequeriments() {
  sudo apt install snapd -y
  sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq > /dev/null 2>&1 && sudo chmod +x /usr/bin/yq
  sudo systemctl start snapd
  sudo systemctl enable snapd
  sudo snap install multipass
}

function createCustomVMs() {
    for ((i=1; i<=NUMBER_OF_VMs; i++)); do
        echo "-> Criando vm${i} com ${CPU} CPUs, ${MEMORY}G de Memória, ${DISK}GB de Disco..."
        multipass launch jammy --cpus "$CPU" --disk "$DISK"GB --name "vm${i}" --memory "$MEMORY"G --mount "${repository_dir}":/iliada/
    done

    echo ""
    echo "--- Resumo das VMs criadas ---"
    sudo rm -rf "${repository_dir}/tmp/*"
    multipass list
}

function saveVmIPs() {
  {    
    echo "vms:"
    for ((i=1; i<=NUMBER_OF_VMs; i++)); do
      IP_VM=$(multipass info vm${i} | awk '/IPv4/ {print $2}')
      [[ -z "$IP_VM" ]] && exit 1
      echo "  - name: vm${i}"
      echo "    ip: ${IP_VM}"
      echo "    dns: vm${i}.iliada"
    done
    echo "dns_ip: ${SERVER_IP}"
   } | tee "${start_dir}/config.yaml"  > /dev/null
}

main() {
  updateSystemPackages
  configureHostNamespace
  installRequeriments
  createCustomVMs 
  saveVmIPs
}

main "$@"