#!/bin/bash

# Check if the user provided an argument
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <E(Enable) or V(View)>"
  exit 1
fi

# Get the user input from the command-line argument
confirm=$1

# Get AWS account ID
account_id=$(aws sts get-caller-identity --query 'Account' --output text)
# List all KMS aliases and extract alias names and key IDs
aliases=$(aws kms list-aliases --query 'Aliases[*].[AliasName,TargetKeyId]' --output text)

# Loop through each alias and key ID pair
echo "---------------------------------- AWS KMS 리스트 조회 ----------------------------------"
printf "%-15s %-20s %-40s %-15s\n" "AccountID" "KeyAlias" "KeyID" "RotateState"
while read -r alias_name key_id; do
  if [[ "$key_id" != "None" && "$alias_name" && "$alias_name" != alias/aws/* ]]; then
    rotation_status=$(aws kms get-key-rotation-status --key-id $key_id --query 'KeyRotationEnabled' --output text)
    # Remove 'alias/' prefix from alias name
    clean_alias_name=${alias_name#alias/}
    printf "%-15s %-20s %-40s %-15s\n" "$account_id" "$clean_alias_name" "$key_id" "$rotation_status"
    if [[ "$rotation_status" == "False" && "$confirm" == "E" || "$confirm" == "Enable" ]]; then
        aws kms enable-key-rotation --key-id $key_id
        echo "Enabled key rotation for $key_id ($clean_alias_name)"
    fi
  fi
done <<< "$aliases"

# Re-query and print the entire result at the end if the user confirmed
if [[ "$confirm" == "E" || "$confirm" == "Enable" ]]; then
  echo ""
  echo "----------------------------AWS KMS Rotate Enabled  적용 확인----------------------------"
  printf "%-15s %-20s %-40s %-15s\n" "AccountID" "KeyAlias" "KeyID" "RotateState"
  aliases=$(aws kms list-aliases --query 'Aliases[*].[AliasName,TargetKeyId]' --output text)
  while read -r alias_name key_id; do
    if [[ "$key_id" != "None" && "$alias_name" && "$alias_name" != alias/aws/* ]]; then
      rotation_status=$(aws kms get-key-rotation-status --key-id $key_id --query 'KeyRotationEnabled' --output text)
      clean_alias_name=${alias_name#alias/}
      printf "%-15s %-20s %-40s %-15s\n" "$account_id" "$clean_alias_name" "$key_id" "$rotation_status"
    fi
  done <<< "$aliases"
fi
