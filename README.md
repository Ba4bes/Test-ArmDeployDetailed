# Test-ArmDeployDetailed

Powershell-script to test an ARM deployment and show the resources that will be created

## Test an ARM deployment en show the resources

This script will first test an Arm deployment with Test-AzureRmResourceGroupDeployment.
If a generic error pops up, it will search for details in Azure.
If this test succeeds, an output will be generated that will show what resources will be deployed

There are two scripts available:

- TestArmPSLocal.ps1
  Run locally when creating a template
- TestArmPSBuild.ps1
  Can be used to used in a CICD-pipeline.

## HowTo

Find more info on  
 <https://4bes.nl/2018/12/13/script-test-arm-templates-and-show-the-deployed-resources>

And a guide to run it as part of an Azure Devops deployment  
<https://4bes.nl/2018/12/26/step-by-step-setup-a-build-deploy-pipeline-in-azure-devops-for-arm-templates/>