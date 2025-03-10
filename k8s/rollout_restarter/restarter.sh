#!/bin/bash

# Check if at least one namespace is provided as an argument
if [ $# -eq 0 ]; then
  echo "Usage: $0 <namespace1> [<namespace2> ... <namespaceN>]"
  exit 1
fi

# Loop through each provided namespace
for namespace in "$@"; do
  echo "Processing namespace: $namespace"

  # Get all Rollout names in the specified namespace
  rollouts=$(kubectl get rollouts -n $namespace -o jsonpath='{.items[*].metadata.name}')

  # Convert rollouts to an array
  rollout_array=($rollouts)
  total_rollouts=${#rollout_array[@]}

  # Loop through each Rollout and restart it with progress indication
  for i in "${!rollout_array[@]}"; do
    rollout=${rollout_array[$i]}
    echo "Restarting Rollout $((i+1))/$total_rollouts: $rollout"
    kubectl argo rollouts restart -n $namespace $rollout
  done
done
