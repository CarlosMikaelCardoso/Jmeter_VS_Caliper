#!/usr/bin/env bash
set -o pipefail
set -x

# 1. Para o serviço que causa conflito
function stopSystemdResolved() {
    sudo systemctl disable systemd-resolved &>/dev/null || true
    sudo systemctl stop systemd-resolved &>/dev/null || true
    # Garante que o /etc/resolv.conf antigo seja removido
    sudo rm -f /etc/resolv.conf
}

# 2. Cria um DNS temporário para ter acesso à internet
function createTempResolvConf() {
    {
        echo "nameserver 8.8.8.8" # Usa o Google DNS para a instalação
        echo "nameserver 1.1.1.1" # Cloudflare como backup
    } | sudo tee /etc/resolv.conf > /dev/null
}

# 3. Instala as ferramentas necessárias
function installTools() {
    sudo apt-get update
    if ! command -v yq &> /dev/null; then
        YQ_VERSION="v4.40.5"
        wget -qO /tmp/yq https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64
        chmod +x /tmp/yq
        sudo mv /tmp/yq /usr/bin/yq
    fi
    sudo apt-get -o Dpkg::Options::="--force-confold" -y install dnsmasq
}

# 4. Configura o dnsmasq e o DNS final da VM
function configDNSForwarder() {
    local DNS_SERVER_IP="$1"
    local VM1_IP="$2"

    # Agora, cria o resolv.conf definitivo, apontando para o dnsmasq local
    sudo chattr -i /etc/resolv.conf &>/dev/null || true
    {
        echo "nameserver 127.0.0.1"
    } | sudo tee /etc/resolv.conf > /dev/null
    sudo chattr +i /etc/resolv.conf

    {
        echo "no-resolv"
        echo "server=${DNS_SERVER_IP}"
        echo "listen-address=${VM1_IP}"
        echo "listen-address=127.0.0.1"
        echo "bind-interfaces"
    } | sudo tee /etc/dnsmasq.conf > /dev/null

    sudo systemctl restart dnsmasq
}

main() {
    if [ -z "$1" ]; then
      echo "Uso: $0 <arquivo.yaml>"
      exit 1
    fi
    local config_yaml="$1"

    # --- ORDEM DE EXECUÇÃO CORRIGIDA ---
    stopSystemdResolved
    createTempResolvConf
    installTools
    
    local DNS_SERVER_IP=$(yq e '.dns_ip' "$config_yaml")
    local VM1_IP=$(yq e '.vms[0].ip' "$config_yaml")

    configDNSForwarder "$DNS_SERVER_IP" "$VM1_IP"
}

main "$@"