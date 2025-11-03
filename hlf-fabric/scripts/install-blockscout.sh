#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../ && pwd -P)
config_dir="${repository_dir}/lab-single-node/besu/configs/blockscout"

NAMESPACE="blockscout"
NETWORK_NAME="LabSingleNodeBesu"
SUBNETWORK_NAME="dev"

BLOCKSCOUT_RELEASE_NAME="blockscout"
BLOCKSCOUT_CHART_VERSION="3.2.1"
BLOCKSCOUT_VALUES_FILE="${config_dir}/blockscout-values.yaml"
BLOCKSCOUT_MAPPING_MANIFEST="${config_dir}/mapping-blockscout.yaml"
BLOCKSCOUT_FRONTEND_NODEPORT_MANIFEST="${config_dir}/blockscout-frontend-nodeport.yaml"
BLOCKSCOUT_BACKEND_NODEPORT_MANIFEST="${config_dir}/blockscout-backend-nodeport.yaml"

POSTGRES_RELEASE_NAME="blockscout-db"
POSTGRES_CHART_VERSION="15.5.0"
POSTGRES_VALUES_FILE="${config_dir}/postgres-values.yaml"

PROMETHEUS_RELEASE_NAME="kube-prometheus-stack"
PROMETHEUS_CHART_VERSION="59.1.0"
PROMETHEUS_VALUES_FILE="${config_dir}/prometheus-values.yaml"

BESU_NAMESPACE="ufpa-bes"
BESU_SERVICE_NAME="besu-node-validator"

function checkHelmInstalled() {
    if ! command -v helm &> /dev/null; then
        echo "Helm não está instalado. Instale com: sudo snap install helm --classic"
        exit 1
    fi
}

function checkYqInstalled() {
    if ! command -v yq &> /dev/null; then
        echo "yq não está instalado. Instale com: sudo snap install yq"
        exit 1
    fi
}

function addRepositories(){
    echo "Adicionando repositórios Helm..."
    helm repo add blockscout https://blockscout.github.io/helm-charts || true
    helm repo add bitnami https://charts.bitnami.com/bitnami || true
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
    helm repo update
}

function createNamespace(){
    echo "Criando namespace do Blockscout..."
    kubectl get namespace $NAMESPACE &> /dev/null || kubectl create namespace $NAMESPACE
}

function checkNamespaceBesu(){
    echo "Verificando serviço do Besu..."
    kubectl get svc "${BESU_SERVICE_NAME}-1" -n "$BESU_NAMESPACE" &> /dev/null || {
        echo "Serviço do Besu '${BESU_SERVICE_NAME}-1' não encontrado no namespace '$BESU_NAMESPACE'"
        exit 1
    }
}

function createMappingAmbassador(){
    echo "Criando Mapping no Ambassador..."
    kubectl apply -f "$BLOCKSCOUT_MAPPING_MANIFEST"
}

function exposeFrontendNodePort(){
    echo "Expondo frontend do Blockscout via NodePort..."
    kubectl apply -f "$BLOCKSCOUT_FRONTEND_NODEPORT_MANIFEST"
}

function exposeBackendNodePort(){
    echo "Expondo backend do Blockscout via NodePort..."
    kubectl apply -f "$BLOCKSCOUT_BACKEND_NODEPORT_MANIFEST"
}

function waitForResource() {
    local kind=$1   # deployment ou statefulset
    local name=$2   # nome do recurso

    if [[ "$kind" != "deployment" && "$kind" != "statefulset" ]]; then
        echo "Tipo inválido: $kind. Use 'deployment' ou 'statefulset'."
        exit 1
    fi

    kubectl rollout status "$kind" "$name" -n "${NAMESPACE}" --timeout=180s
}

function installPostgres() {
    echo "Instalando PostgreSQL (Bitnami)..."
    helm upgrade --install $POSTGRES_RELEASE_NAME bitnami/postgresql \
      --namespace $NAMESPACE \
      --version "$POSTGRES_CHART_VERSION" \
      --values "$POSTGRES_VALUES_FILE"
}

function waitForPostgres() {
    waitForResource statefulset "${POSTGRES_RELEASE_NAME}-postgresql"
}

function installPrometheus() {
    echo "Instalando Prometheus Operator (v${PROMETHEUS_CHART_VERSION})..."
    helm upgrade --install $PROMETHEUS_RELEASE_NAME prometheus-community/kube-prometheus-stack \
      --namespace $NAMESPACE \
      --version "$PROMETHEUS_CHART_VERSION" \
      --values "$PROMETHEUS_VALUES_FILE" \
      --wait
}

function waitForPrometheus() {
    waitForResource statefulset "prometheus-${PROMETHEUS_RELEASE_NAME}-prometheus"
}

function waitForGrafana() {
    echo "Aguardando Grafana Deployment ficar pronto..."
    waitForResource deployment "${PROMETHEUS_RELEASE_NAME}-grafana"
}

function waitForAlertmanager() {
    echo "Aguardando Alertmanager StatefulSet ficar pronto..."
    waitForResource statefulset "alertmanager-${PROMETHEUS_RELEASE_NAME}-alertmanager"
}

function createGenesisConfigMap() {
    echo "Criando ConfigMap com o genesis.json para o Blockscout..."

    kubectl get configmap besu-genesis -n "$BESU_NAMESPACE" -o jsonpath='{.data.genesis\.json}' > /tmp/genesis.json

    kubectl create configmap blockscout-genesis \
      --from-file=genesis.json=/tmp/genesis.json \
      -n "$NAMESPACE" \
      --dry-run=client -o yaml | kubectl apply -f -

    rm /tmp/genesis.json

    echo "✅ ConfigMap blockscout-genesis criado no namespace $NAMESPACE"
}

function updateBlockscoutConfig() {
    echo "Atualizando URLs RPC e CHAIN_ID no arquivo de configuração do Blockscout..."

    BESU_IP=$(kubectl get svc "$BESU_SERVICE_NAME-1" -n "$BESU_NAMESPACE" -o jsonpath='{.spec.clusterIP}')
    CHAIN_ID=$(kubectl --namespace "$BESU_NAMESPACE" get configmap besu-genesis -o jsonpath='{.data.genesis\.json}' | jq '.config.chainId')
    SECRET_KEY_BASE=$(openssl rand -hex 64)

    export CHAIN_ID
    export NETWORK_NAME
    export SUBNETWORK_NAME
    export SECRET_KEY_BASE
    export BESU_IP

    yq e -i '.config.network.id = env(CHAIN_ID)' "$BLOCKSCOUT_VALUES_FILE"
    yq e -i '.config.network.name = strenv(NETWORK_NAME)' "$BLOCKSCOUT_VALUES_FILE"

    yq e -i '.blockscout.env.ETHEREUM_JSONRPC_HTTP_URL = "http://" + strenv(BESU_IP) + ":8545"' "$BLOCKSCOUT_VALUES_FILE"
    yq e -i '.blockscout.env.ETHEREUM_JSONRPC_WS_URL = "ws://" + strenv(BESU_IP) + ":8546"' "$BLOCKSCOUT_VALUES_FILE"

    yq e -i '.blockscout.env.CHAIN_ID = env(CHAIN_ID)' "$BLOCKSCOUT_VALUES_FILE"
    yq e -i '.blockscout.env.SECRET_KEY_BASE = strenv(SECRET_KEY_BASE)' "$BLOCKSCOUT_VALUES_FILE"
    yq e -i '.blockscout.env.NETWORK = strenv(NETWORK_NAME)' "$BLOCKSCOUT_VALUES_FILE"
    yq e -i '.blockscout.env.SUBNETWORK = strenv(SUBNETWORK_NAME)' "$BLOCKSCOUT_VALUES_FILE"
}
function updatePrometheusConfig() {
    echo "Atualizando Prometheus additionalScrapeConfigs para os validadores..."

    IP_VALIDATOR_1=$(kubectl get svc besu-node-validator-1 -n "$BESU_NAMESPACE" -o jsonpath='{.spec.clusterIP}')
    IP_VALIDATOR_2=$(kubectl get svc besu-node-validator-2 -n "$BESU_NAMESPACE" -o jsonpath='{.spec.clusterIP}')
    IP_VALIDATOR_3=$(kubectl get svc besu-node-validator-3 -n "$BESU_NAMESPACE" -o jsonpath='{.spec.clusterIP}')
    IP_VALIDATOR_4=$(kubectl get svc besu-node-validator-4 -n "$BESU_NAMESPACE" -o jsonpath='{.spec.clusterIP}')

    yq e "
      (.additionalScrapeConfigs[] | select(.job_name == \"besu\") ).static_configs = [
        {
          \"targets\": [
            \"${IP_VALIDATOR_1}:9545\",
            \"${IP_VALIDATOR_2}:9545\",
            \"${IP_VALIDATOR_3}:9545\",
            \"${IP_VALIDATOR_4}:9545\"
          ]
        }
      ]
    " -i "$PROMETHEUS_VALUES_FILE"
}

function installRequirements(){
    addRepositories
    createNamespace
    checkNamespaceBesu
    installPostgres
    waitForPostgres
    installPrometheus
    waitForPrometheus
    waitForGrafana
    waitForAlertmanager
    createMappingAmbassador
}

function installBlockscout(){
    echo "Instalando Blockscout..."
    helm upgrade --install $BLOCKSCOUT_RELEASE_NAME blockscout/blockscout-stack \
      --namespace $NAMESPACE \
      --version "$BLOCKSCOUT_CHART_VERSION" \
      --values "$BLOCKSCOUT_VALUES_FILE" \
      --wait

    exposeFrontendNodePort
    exposeBackendNodePort
    
    echo "✅ Blockscout instalado com sucesso!"
}

main() {
    checkHelmInstalled
    checkYqInstalled
    updatePrometheusConfig
    installRequirements
    createGenesisConfigMap
    updateBlockscoutConfig
    installBlockscout
}

main "$@"