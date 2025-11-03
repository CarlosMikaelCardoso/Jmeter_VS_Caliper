#!/usr/bin/env bash
# set -o errexit   # abort on nonzero exitstatus
# set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

# Verifica se o arquivo YAML foi passado como argumento
if [ -z "$1" ]; then
  echo "Uso: $0 <arquivo.yaml>"
  exit 1
fi

config_yaml="$1"


firstIP=$(yq e '.vms[0].ip' "$config_yaml")

DNS_SERVER_IP=$(yq e '.dns_ip' "$config_yaml")
DNS_SERVER_INTERFACE=$(ip -o route get to 8.8.8.8 | awk '{print $5}')
HOST_PRIVATE_IP=$(yq e '.vms[0].ip' "$config_yaml")
MULTIPASS_INTERFACE=$(ip -o route get to "${firstIP}" | awk '{print $3}')
DNSMASQ_VERSION="2.90-0ubuntu0.22.04.1"

function installDNS() {
    sudo snap install yq
    # A variável de versão foi removida para instalar a versão padrão do repositório
    sudo apt install -y dnsmasq
    sudo systemctl disable systemd-resolved
    sudo systemctl stop systemd-resolved
}

# COMENTÁRIO: A função foi alterada para usar 'systemctl restart' em vez de 'service stop/start'.
# É o comando moderno e mais adequado para sistemas baseados em systemd como o Ubuntu.
function configDNS() {
    [[ -f "/etc/resolv.conf" ]] && sudo unlink /etc/resolv.conf

    {
        echo "nameserver 127.0.0.1"
        echo "nameserver 8.8.8.8"
    } | sudo tee /etc/resolv.conf > /dev/null

    num_vms=$(yq e '.vms | length' "$config_yaml")

    {
        for ((i = 0; i < num_vms; i++)); do
            ip=$(yq e ".vms[$i].ip" "$config_yaml")
            dns=$(yq e ".vms[$i].dns" "$config_yaml")
            echo "address=/.${dns}/${ip}"
        done

        echo "interface=${DNS_SERVER_INTERFACE}"
        echo "listen-address=${DNS_SERVER_IP}"
        # echo "listen-address=${HOST_PRIVATE_IP}"
        echo "listen-address=127.0.0.1"
        echo "bind-interfaces"
    } | sudo tee /etc/dnsmasq.conf > /dev/null
    
    sudo systemctl restart dnsmasq
}

main() {
    installDNS
    configDNS
}

main "$@"
