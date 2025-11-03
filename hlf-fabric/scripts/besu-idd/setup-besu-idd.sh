#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

DOCKER_COMPOSE_VERSION="v2.20.3"
BVERSION="24.5.4"
NODES=("org1-node1" "org1-node2" "org2-node1" "org2-node2" "org3-node1")
HOST_IP="${1:-$(ip -4 addr show eth1 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || ip -4 addr show enp0s3 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')}"
OAUTH2_TOKEN=

function update_repositories(){
  sudo apt update && sudo apt -y upgrade
}

function install_micro_requirements(){
  sudo apt install -y git curl unzip zip
}

function install_docker(){
  sudo apt-get install -y ca-certificates curl gnupg lsb-release
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  sudo docker --version
  sudo docker run hello-world
}

function install_docker_compose(){
  sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" -o docker-compose
  sudo mv docker-compose /usr/bin/docker-compose
  sudo chmod +x /usr/bin/docker-compose
  sudo docker-compose --version
}

function install_jdk(){
  sudo apt install -y openjdk-17-jre openjdk-17-jdk
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
  export PATH=$JAVA_HOME/bin:$PATH
}

function install_requirements() {
  install_micro_requirements
  install_docker
  install_docker_compose
  install_jdk
}

function clone_iliada_project(){
  mkdir -p iliada && cd iliada
  git clone https://oauth2:${OAUTH2_TOKEN}@git.rnp.br/iliada-blockchain/m3/rede-besu-idd-v1.git
  mv rede-besu-idd-v1 rede-besu-idd-v1-3
  cd rede-besu-idd-v1-3
}

function get_binaries_besu(){
  curl -L "https://github.com/hyperledger/besu/releases/download/${BVERSION}/besu-${BVERSION}.zip" -o "besu-${BVERSION}.zip"
  unzip "besu-${BVERSION}.zip"
}

function generate_keys_nodes(){
  for node in "${NODES[@]}"; do
    mkdir -p config/nodes/$node
    ./besu-${BVERSION}/bin/besu --data-path=config/nodes/$node public-key export --to=config/nodes/$node/key.pub
    ./besu-${BVERSION}/bin/besu --data-path=config/nodes/$node public-key export-address --to=config/nodes/$node/node.id
  done
}

function generate_static_nodes_json() {
  echo "[" > static-nodes.json
  port=30301
  for node in "${NODES[@]}"; do
    enode_id=$(cat config/nodes/${node}/node.id)
    echo "\"enode://${enode_id}@${HOST_IP}:${port}\"," >> static-nodes.json
    ((port++))
  done
  sed -i '$ s/,$//' static-nodes.json
  echo "]" >> static-nodes.json
}

function generate_genesis_and_extradata(){
  echo "[" > initialValidators.json
  for node in "${NODES[@]}"; do
    cat config/nodes/${node}/node.id | sed 's/^/"/;s/$/"/' >> initialValidators.json
    echo "," >> initialValidators.json
  done
  sed -i '$ s/,$//' initialValidators.json
  echo "]" >> initialValidators.json

  ./besu-${BVERSION}/bin/besu rlp encode --from=initialValidators.json --type=QBFT_EXTRA_DATA > extraData.json

  cat > genesis.json <<EOF
{
  "config": {
    "chainId": 10002,
    "berlinBlock": 0,
    "qbft": {
      "epochlength": 30000,
      "blockperiodseconds": 4,
      "requesttimeoutseconds": 8
    }
  },
  "nonce": "0x0",
  "gasLimit": "0xF42400",
  "difficulty": "0x1",
  "mixHash": "0x63746963616c2062797a616e74696e65206661756c7420746f6c6572616e6365",
  "extraData": "$(cat extraData.json)",
  "alloc": {},
  "timestamp": "0x$(printf '%x' $(date +%s))"
}
EOF
}

function prepare_node_configs(){
  for node in "${NODES[@]}"; do
    mkdir -p volumes/$node
    cp config/nodes/$node/key* config/nodes/$node/node.id volumes/$node/
  done
}

function generate_docker_compose() {
  p2p_port=30301
  rpc_port=8545
  ws_port=8551

  for node in "${NODES[@]}"; do
    node_dir="config/nodes/${node}"
    mkdir -p "$node_dir"

    cat > "$node_dir/docker-compose.yaml" <<EOF
version: '3.4'

services:
  besu:
    image: hyperledger/besu:${BVERSION}
    container_name: besu-${node}
    environment:
      LOG4J_CONFIGURATION_FILE: "/var/lib/besu/log.xml"
      BESU_DATA_PATH: "/var/lib/besu"
      BESU_GENESIS_FILE: "/var/lib/besu/genesis.json"
      BESU_RPC_HTTP_ENABLED: "true"
      BESU_RPC_HTTP_API: "ADMIN,ETH,TXPOOL,NET,QBFT,WEB3,DEBUG,TRACE,PERM"
      BESU_RPC_HTTP_CORS_ORIGINS: "*"
      BESU_HOST_ALLOWLIST: "*"
      BESU_P2P_HOST: "${HOST_IP}"
      BESU_P2P_PORT: "${p2p_port}"
      BESU_DISCOVERY_ENABLED: "false"
      BESU_METRICS_ENABLED: "true"
      BESU_METRICS_HOST: "0.0.0.0"
      BESU_PERMISSIONS_ACCOUNTS_CONTRACT_ENABLED: "true"
      BESU_PERMISSIONS_ACCOUNTS_CONTRACT_ADDRESS: "0x0000000000000000000000000000000000008888"
      BESU_PERMISSIONS_NODES_CONTRACT_ENABLED: "true"
      BESU_PERMISSIONS_NODES_CONTRACT_ADDRESS: "0x0000000000000000000000000000000000009999"
      BESU_PERMISSIONS_NODES_CONTRACT_VERSION: "1"
    volumes:
      - \${PWD}/../../../volumes/${node}:/var/lib/besu
      - \${PWD}/key:/var/lib/besu/key
      - \${PWD}/../../besu/genesis.json:/var/lib/besu/genesis.json
      - \${PWD}/../${node}/log.xml:/var/lib/besu/log.xml
      - \${PWD}/../../besu/static-nodes.json:/var/lib/besu/static-nodes.json
    ports:
      - "${p2p_port}:${p2p_port}"
      - "${rpc_port}:${rpc_port}"
      - "${ws_port}:${ws_port}"
EOF

    ((p2p_port++))
    ((rpc_port++))
    ((ws_port++))
  done
}

function generate_log_xml(){
  for node in "${NODES[@]}"; do
    log_path="config/nodes/${node}/log.xml"
    cat > "${log_path}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Configuration>
  <Appenders>
    <Console name="Console" target="SYSTEM_OUT">
      <PatternLayout pattern="%d{yyyy-MM-dd HH:mm:ss} %-5p [%c{1.}] %m%n"/>
    </Console>
  </Appenders>
  <Loggers>
    <Root level="INFO">
      <AppenderRef ref="Console"/>
    </Root>
  </Loggers>
</Configuration>
EOF
  done
}

function start_nodes() {
  for node in "${NODES[@]}"; do
    (
      cd config/nodes/${node}
      sudo docker-compose up -d
    )
  done
}

function main(){
  update_repositories
  install_requirements
  clone_iliada_project
  get_binaries_besu
  generate_keys_nodes
  generate_static_nodes_json
  generate_genesis_and_extradata
  prepare_node_configs
  generate_docker_compose
  generate_log_xml
  start_nodes
}

main "$@"