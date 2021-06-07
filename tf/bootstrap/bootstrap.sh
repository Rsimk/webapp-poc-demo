#!/bin/bash

set -e

# Defaults
LOCATION='westeurope'
SP_NAME='http://tf-deploy-demo'
SP_PIPELINE_NAME='http://tf-pipeline-demo'
TF_RG_NAME='tfstate-demo-rg'
TF_STATE_KEY_NAME='backend.tfstate'
TF_STORAGE_ACCT_NAME=tf$RANDOM$RANDOM"st1"
TF_KEYVAULT_NAME=tf-$RANDOM$RANDOM"-kv"
TF_STORAGE_ACCT_SKU='Standard_GRS'
TF_STORAGE_CONTAINER_NAME="tfstate"

usage() {
  echo "Usage: $0" 1>&2
  exit 1
}

exit_abnormal() {
  echo $1 1>&2
  usage
}

SUBSCRIPTION=$(az account list --query '[?isDefault]' --output json --all)
SUBSCRIPTION_ID=$(echo $SUBSCRIPTION | jq -r .[].id)
echo "Using subscription id: $(echo $SUBSCRIPTION | jq -r '.[].id')"
echo "Using location: $LOCATION"

if [ ! "$SUBSCRIPTION_ID" ]; then
  exit_abnormal 'Not logged in with az cli or no subscriptions'
fi

# Create backend.hcl
cp -f backend.hcl.example backend.hcl
sed -i "s/myrg/$TF_RG_NAME/" backend.hcl
sed -i "s/mystorageaccount/$TF_STORAGE_ACCT_NAME/" backend.hcl
sed -i "s/mystatecontainer/$TF_STORAGE_CONTAINER_NAME/" backend.hcl
sed -i "s/mybackendkey.tfstate/$TF_STATE_KEY_NAME/" backend.hcl

ADMIN_USER=$(az ad signed-in-user show --output json)

# Configure az cli for silent output and defaults
# export AZURE_CORE_OUTPUT=none
az configure --defaults group=$TF_RG_NAME location=$LOCATION \
             --scope local

# skip if exists 
if [[ $(az group exists --name $TF_RG_NAME) == false ]]; then
    echo "Creating resource group $TF_RG_NAME"
    az group create --name $RESOURCEGROUPNAME --location $LOCATION
fi

echo "Creating service principal and assigning 'Owner' role on subscription level"
SP=$(az ad sp create-for-rbac -n $SP_NAME \
                               --role "Owner" \
                               --scopes "/subscriptions/$SUBSCRIPTION_ID" \
                               --output json)

echo "Creating service principal and assigning Reader role at resource group: $TF_RG_NAME"
SP_PIPELINE=$(az ad sp create-for-rbac -n $SP_PIPELINE_NAME \
                               --role "Reader" \
                               --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$TF_RG_NAME" \
                               --sdk-auth \
                               --output json)

echo "Waiting for the new service principals to appear in the Azure AD Graph"
while [ ! "$SP_OBJECT" ] || [ ! "$SP_PIPELINE_OBJECT" ]; do
  printf '.'
  SP_OBJECT=$(az ad sp show --id "$SP_NAME" --output json)
  SP_PIPELINE_OBJECT=$(az ad sp show --id "$SP_PIPELINE_NAME" --output json)
  sleep 5
done
printf '\n'

echo "Creating storage account $TF_STORAGE_ACCT_NAME"
az storage account create --name $TF_STORAGE_ACCT_NAME \
                          --https-only \
                          --kind StorageV2 \
                          --sku $TF_STORAGE_ACCT_SKU

echo "Adding 'Reader and Data Access' role assignment on storage account for SPN"
az role assignment create --role 'Reader and Data Access' \
                          --assignee-object-id $(echo $SP_OBJECT | jq -r .objectId) \
                          --assignee-principal-type ServicePrincipal \
                          --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$TF_RG_NAME/providers/Microsoft.Storage/storageAccounts/$TF_STORAGE_ACCT_NAME"

echo "Adding 'Owner' role assignment for SPN on the subscription for SPN"
az role assignment create --role 'Owner' \
                          --assignee-object-id $(echo $SP_OBJECT | jq -r .objectId) \
                          --assignee-principal-type ServicePrincipal \
                          --scope "/subscriptions/$SUBSCRIPTION_ID"


echo "Adding 'Storage Blob Data Contributor' role assignment for $(echo $ADMIN_USER | jq -r .userPrincipalName)"
TOBEREMOVED=$(az role assignment create --role 'Storage Blob Data Contributor' \
                          --assignee-object-id $(echo $ADMIN_USER | jq -r .objectId) \
                          --assignee-principal-type User \
                          --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$TF_RG_NAME/providers/Microsoft.Storage/storageAccounts/$TF_STORAGE_ACCT_NAME" \
                          --output json)

echo "Creating blob container for Terraform backend"
az storage container create --account-name $TF_STORAGE_ACCT_NAME \
                            --auth-mode login \
                            --name $TF_STORAGE_CONTAINER_NAME

echo "Creating key vault $TF_KEYVAULT_NAME"
az keyvault create --name $TF_KEYVAULT_NAME

echo "Adding key vault access policy for $(echo $ADMIN_USER | jq -r .userPrincipalName)"
az keyvault set-policy --name $TF_KEYVAULT_NAME \
                       --object-id $(echo $ADMIN_USER | jq -r .objectId) \
                       --secret-permissions get list set

echo "Adding kay vault access policy for action/pipeline service principal"
az keyvault set-policy --name $TF_KEYVAULT_NAME \
                       --object-id $(echo $SP_PIPELINE_OBJECT | jq -r .objectId) \
                       --secret-permissions get list

echo "Creating secrets: arm-client-id, arm-client-secret, arm-tenant-id, arm-subscription-id & tf-backend-file"
az keyvault secret set --vault-name $TF_KEYVAULT_NAME \
                --name arm-client-id \
                --value $(echo $SP | jq -r .appId)
az keyvault secret set --vault-name $TF_KEYVAULT_NAME \
                --name arm-client-secret \
                --value $(echo $SP | jq -r .password)
az keyvault secret set --vault-name $TF_KEYVAULT_NAME \
                --name arm-subscription-id \
                --value $SUBSCRIPTION_ID
az keyvault secret set --vault-name $TF_KEYVAULT_NAME \
                --name arm-tenant-id \
                --value $(echo $SUBSCRIPTION | jq -r '.[].tenantId')
az keyvault secret set --vault-name $TF_KEYVAULT_NAME \
                --name tf-backend-file \
                --value "$(cat backend.hcl)"

echo "Removing key vault access policy for $(echo $ADMIN_USER | jq -r .userPrincipalName)"
az keyvault delete-policy --name $TF_KEYVAULT_NAME \
                       --object-id $(echo $ADMIN_USER | jq -r .objectId)

az configure --defaults group='' location='' \
             --scope local

echo "Removing 'Storage Blob Data Contributor' role assignment for $(echo $ADMIN_USER | jq -r .userPrincipalName)"
az role assignment delete --ids $(echo $TOBEREMOVED | jq -r .id )

echo "Adding Application.ReadWrite.All permission on deploy SP"
az ad app permission add --id $(echo $SP_OBJECT | jq -r .objectId) --api 00000002-0000-0000-c000-000000000000 --api-permissions 1cda74f2-2616-4834-b122-5cb1b07f8a59=Role
az ad app permission admin-consent --id $(echo $SP_OBJECT | jq -r .objectId)

echo "You will need to create the following secrets in GitHub or Azure DevOps"
echo
echo "AZURE_CREDENTIALS:"
echo "-------------------------------"
echo $SP_PIPELINE | jq
echo "-------------------------------"
echo 
echo "KEYVAULT_NAME:"
echo "-------------------------------"
echo $TF_KEYVAULT_NAME
echo "-------------------------------"

unset AZURE_CORE_OUTPUT
