#!/usr/bin/env bash
set -euo pipefail

###
### This scripts helps Appdrift in bringing applications down and up in a controlled way.
### Requires that autosync in ArgoCD is disabled for the selected apps.
###

# Validate dependencies are present
for tool in kubectl jq base64; do
    if ! command -v $tool &> /dev/null; then
        echo "Error: Tool '$tool' is missing from your \$PATH"
        exit 1
    fi
done

# Validate input arguments
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <up|down> namespace1/app1 namespace2/app2 ..."
    exit 1
fi

## Variables
mode="$1"
current_context=$(kubectl config current-context)
# Read argument into $apps
apps=("${@:2}")
# The amount of time for waiting on Kubernetes operations (10 * 60 seconds, 10 minutes)
deadline=600s

# Sanity check
read -r -p "You are currently operating against '$current_context'. Do you want to proceed with the '$mode' operation? [y/N] " response

# Convert the response to lowercase and check for a 'y' or 'yes' confirmation
case $response in
    [yY]|[yY][eE][sS])
        ;;
    *)
        echo "Operation aborted by user."
        exit 1
        ;;
esac

# Get unique namespaces
mapfile -t unique_namespaces < <(printf "%s\n" "${apps[@]}" | cut -d'/' -f1 | sort -u)

# Authentication check
if ! kubectl auth can-i '*' deployments.apps -n "${unique_namespaces[0]}" &>/dev/null; then
    echo "Error: You are not authenticated against the current cluster ($current_context)."
    exit 1
fi

# Down mode
if [[ $mode == "down" ]]; then
    total_apps=${#apps[@]}
    for index in "${!apps[@]}"; do
        app="${apps[$index]}"
        namespace="${app%%/*}"
        appName="${app##*/}"

        echo "==> Bringing down app $((index+1))/$total_apps: $app"

        # Label the deployment
        if ! kubectl label deployment "$appName" -n "$namespace" \
            skiperator.kartverket.no/ignore=true --overwrite &>/dev/null; then
          echo "Error labeling deployment $appName in $namespace"
        fi

        # Set replicas to 0
        if ! kubectl scale deployment "$appName" -n "$namespace" --replicas=0 &>/dev/null; then
            echo "Error scaling deployment $appName to zero in $namespace"
        fi

        # Watch the underlying deployment until 0 replicas exist (hiding the output)
        if kubectl rollout status deployment "$appName" -n "$namespace" --watch --timeout=$deadline &>/dev/null; then
            echo "Successfully scaled $appName to 0"
        else
            echo "Error scaling down $appName in $namespace"
            exit 1
        fi

        # Use kubectl wait to ensure all pods with the label app=$appName are terminated
        echo "Waiting for pods to be terminated..."
        if ! kubectl wait pods -l app="$appName" -n "$namespace" --for=delete --timeout="$deadline" &>/dev/null; then
            echo "Timed out waiting for pods of $appName to terminate"
            exit 1
        fi
    done
fi

# Up mode
if [[ $mode == "up" ]]; then
    # Reverse the apps order for "up" mode
    mapfile -t apps < <(printf "%s\n" "${apps[@]}" | tac)

    total_apps=${#apps[@]}
    for index in "${!apps[@]}"; do
        app="${apps[$index]}"
        namespace="${app%%/*}"
        appName="${app##*/}"

        echo "==> Bringing up app $((index+1))/$total_apps: $app"

        # Remove the ignore label
        if ! kubectl label deployment -n "$namespace" "$appName" skiperator.kartverket.no/ignore- &>/dev/null; then
            echo "Error removing label for deployment $appName in $namespace"
        fi

        # Wait for a new Deployment to be generated by skiperator
        sleep 5

        # Watch the rollout status until it's done
        kubectl rollout status deployment "$appName" -n "$namespace" --watch --timeout=$deadline

        # Use kubectl wait to ensure all pods with the label app=$appName are terminated
        echo "Waiting for pods to become ready..."
        if ! kubectl wait pods -l app="$appName" -n "$namespace" --for=condition=ready --timeout="$deadline" &>/dev/null; then
            echo "Timed out waiting for pods of $appName to become ready"
            exit 1
        fi
    done
fi
