#!/bin/bash

REQUIRED_ARGS=3

# Check if the number of arguments is less than the required number
if [ "$#" -lt "$REQUIRED_ARGS" ]; then
  echo "This script will copy over a secret from one cluster to another, replacing last random prefix with '-manual'"
  echo "Usage: $0 <SOURCE_CONTEXT> <DEST_CONTEXT> <SOURCE_SECRET_NAME>"
  exit 1
fi

SOURCE_CONTEXT=$1
DEST_CONTEXT=$2
SOURCE_SECRET_NAME=$3
SOURCE_NAMESPACE="istio-gateways"
DEST_SECRET_NAME="${SOURCE_SECRET_NAME%-*}"

# Fetch the secret from the source cluster
SECRET=$(kubectl --context "$SOURCE_CONTEXT" -n "$SOURCE_NAMESPACE" get secret "$SOURCE_SECRET_NAME" -o yaml)

echo "Found secret $SOURCE_SECRET_NAME in namespace $SOURCE_NAMESPACE in $SOURCE_CONTEXT."

# Check if the secret was retrieved successfully
if [ $? -ne 0 ]; then
  echo "Error: Could not fetch secret $SOURCE_SECRET_NAME in namespace $NAMESPACE"
  exit 1
fi

# Remove managed metadata, annotations, and labels using yq
CLEANED_SECRET=$(echo "$SECRET" | yq e '
  del(.metadata.creationTimestamp) |
  del(.metadata.resourceVersion) |
  del(.metadata.selfLink) |
  del(.metadata.uid) |
  del(.metadata.annotations) |
  del(.metadata.labels)' -)

# Modify the secret name (remove random suffix and append -manual to the name)
MODIFIED_SECRET=$(echo "$CLEANED_SECRET" | sed "s/^  name: $SOURCE_SECRET_NAME$/  name: ${DEST_SECRET_NAME}-manual/")

# Prompt the user for confirmation
read -rp "Do you want to create the secret in $DEST_CONTEXT $SOURCE_NAMESPACE? (y/n): " choice
case "$choice" in
  y|Y )
    echo "Applying the modified secret..."
    echo "$MODIFIED_SECRET" | kubectl apply --context "$DEST_CONTEXT" -f -
    ;;
  n|N )
    echo "Exiting without applying changes."
    ;;
  * )
    echo "Invalid input. Exiting without applying changes."
    ;;
esac
