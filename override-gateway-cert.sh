#!/bin/bash

set -e

REQUIRED_ARGS=4

# Check if the number of arguments is less than the required number
if [ "$#" -lt "$REQUIRED_ARGS" ]; then
  echo "This script will copy over a secret from one cluster to another, replacing last random prefix with '-manual'"
  echo "Usage: $0 <CONTEXT> <NAMESPACE> <APP_NAME> <SECRET_NAME>"
  exit 1
fi

CONTEXT=$1
NAMESPACE=$2
APP_NAME=$3
SECRET_NAME=$4

# Get gateway using name prefix
GATEWAY_NAME=$(kubectl --context "${CONTEXT}" -n "${NAMESPACE}" get gateways.networking.istio.io --no-headers | awk '/^'"$APP_NAME"'/ {print $1}')
echo "Found gateway $GATEWAY_NAME in namespace $NAMESPACE in $CONTEXT."

# Add skiperator ignore label
echo "Adding skiperator ignore label to gateway $GATEWAY_NAME"
kubectl --context "${CONTEXT}" -n "${NAMESPACE}" label gateways.networking.istio.io "$GATEWAY_NAME" skiperator.kartverket.no/ignore=true

# Replace credentialName in gateway with new secret name
echo "Replacing credentialName in gateway $GATEWAY_NAME with $SECRET_NAME"
kubectl --context "${CONTEXT}" -n "${NAMESPACE}" patch gateways.networking.istio.io "$GATEWAY_NAME" --type='json' -p='[{"op": "replace", "path": "/spec/servers/1/tls/credentialName", "value": "'${SECRET_NAME}'"}]'
