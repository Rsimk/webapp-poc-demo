# Bootstrap and deploy terraform configuration to Azure subscription

This folder contains Terraform configuration and bootstrap scripts.
Terraform is using  [Terraform backend](https://www.terraform.io/docs/backends/types/azurerm.html) on storage account.
Deployment SP (service principal) and terraform backend configuration are stored in the key vault.


### Pre-requisities
 - [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed.
 - [Hashicorp Terraform](https://www.terraform.io/downloads.html)
 - Azure AD user with owner role on subscription level 

### Steps

- login to Azure with az cli with owner role on subscription
- run bootstrap script [bootstrap.sh](tf/bootstrap/bootstrap.sh) in [bootstrap](tf/bootstrap) directory. It will create storage account for terraform backend state file, two SP's and key vault. first SP will be used to access second SP in the keyvault. First SP will have access only to keyvault ir will not be able to deploy resources. Second SP will be used together with terraform to deploy resources.
- store first SP credentials and key vault name in the safe place.
- logout from azure.
- login to azure with first SP and secret: ```az login --service-principal -u <app-url> -p <password> --tenant <tenant-id>```
- retrieve follow secrets from key vault: ```az keyvault secret show -n <secret-name> --vault-name <keyvault-name>```
    - arm-client-id
    - arm-client-secret
    - arm-subscription-id
    - arm-tenant-id
    - tf-backend-file
- logout from azure.
- set follow env variables. Use values retrieved from key vault:
    - export ARM_SUBSCRIPTION_ID=
    - export ARM_TENANT_ID=
    - export ARM_CLIENT_SECRET=
    - export ARM_CLIENT_ID=
- initialize terraform in [tf](tf) directory: ```terraform init -backend-config=bootstrap/backend.hcl```
- validate terraform configuration: ```terraform validate```
- prepare plan for terraform changes: ```terraform plan```
- create resources: ```terraform apply```

### Note:  
Deployment SP needs permission to create another SP for AKS . Following SP Azure AD Graph API permission is requirement: Application.ReadWrite.All 

To delete resources run: ```terraform destroy```
