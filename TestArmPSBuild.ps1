<#
.SYNOPSIS
Tests an azure deployment for error and outputs the recources that will be deployed

.DESCRIPTION
This function will first test an Arm deployment with Test-AzureRmResourceGroupDeployment. 
If a generic error pops up, it will search for details in Azure.
If this test succeeds, an output will be generated that will show what resources will be deployed

.PARAMETER ResourceGroup
The resourcegroup where the resources would be deployed to. If it doesn't exist, it will be created

.PARAMETER TemplatePath
The path to the deploymentfile

.PARAMETER ParametersPath
The path to the parameterfile

.NOTES
This script should be ran within a CI/CD pipeline. 
If you want to run it manually, use TestarmPSlocal.ps1
Created by Barbara Forbes, 18-12-2018
Source for more output: #Source https://blog.mexia.com.au/testing-arm-templates-with-pester
#>

Param(
    [string] [Parameter(Mandatory = $true)] $ResourceGroup,
    [string] [Parameter(Mandatory = $true)] $TemplatePath,
    [string] [Parameter(Mandatory = $true)] $ParametersPath

)

#give the parameters back to caller
Write-Output " Parameters set:"
Write-Output $ResourceGroup
Write-Output $TemplatePath
Write-Output $ParametersPath

#make sure the debugpreference is right, as otherwise the simpletest will give confusing results
$DebugPreference = "SilentlyContinue"

#set variables
$SimpleOutput = $null
$DetailedError = $null
$Parameters = @{
    ResourceGroupName     = $ResourceGroup 
    TemplateFile          = $TemplatePath
    TemplateParameterFile = $ParametersPath
}
Write-Output "Test is starting"
# take a simple test

$SimpleOutput = Test-AzureRmResourceGroupDeployment @parameters 

#Check for a secific output. It give a very generic error-message. 
#So this script looks for the more clear errormessage in the AzureLogs.

if ($SimpleOutput.Message -like "*s not valid according to the validation procedure*") {
    Start-Sleep 30
    #use regex to find the ID of the log
    $Regex = '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}'
    $IDs = $SimpleOutput.Message | Select-String $Regex -AllMatches
    $trackingID = $IDs.Matches.Value | select-object -Last 1

    #Get Relevant logentry
    $LogContent = (Get-AzureRMLog -CorrelationId $trackingID -WarningAction ignore).Properties.Content
    $DetailedError = $LogContent.statusMessage
    $ErrorCode = ($DetailedError | convertfrom-json ).error.details.details.code
    $ErrorMessage = ($DetailedError | convertfrom-json ).error.details.details.message
}

if ($SimpleOutput) {
    Write-Output "something is off with your template, build will end"
    #check if DetailedError has been used. if it is, return the value
    if ($DetailedError) {
        Write-Output "General Error. Find info below:"
        Write-Output "ErrorCode: $ErrorCode"
        Write-Output "Errormessage: $ErrorMessage"
    }
    #if not, output the original message
    if (!$DetailedError) {
        Write-output "Error, Find info below:"
        Write-Output $SimpleOutput.Message
    }
    #exit code 1 is for Azure DevOps to stop the build in failed state. locally it just stops the script
    [Environment]::Exit(1)
}
else {
    Write-Output "deployment is correct"
}

Write-Output "Starting with big test"
#output to null as in case of error, you would run the script more than once
$Output = $null
#set debugpreference to continue so the Test-AzureRmResourceGroupDeployment runs with more output
$DebugPreference = "Continue"

$Output = Test-AzureRmResourceGroupDeployment @parameters 5>&1   

#Set DebugPreference back to normal
$DebugPreference = "SilentlyContinue"

Write-Output "collected Output"

#Grap the specific part of the output that tells you about the deployed Resources
$Response = $Output | where-object {$_.Message -like "*http response*"}
#get the jsonpart en convert it to work with it. 
$Result = (($Response -split "Body:")[1] | ConvertFrom-Json).Properties

#tell the user if de mode is complete or incremental
Write-Output "Mode for deployment is $($Result.Mode)" 


$ValidatedResources = $Result.ValidatedResources
Write-Output "The following Resources will be deployed:"

#go through each deployed Resource
foreach ($Resource in $ValidatedResources) { 
    #set up basic information in a hashtable to make it readable
    Write-Output "Creating Resource: $($Resource.type.Split("/")[-1])"
    $ResourceReadable = @{
        Name = $Resource.name
        Type = $Resource.type
        ID   = $Resource.id
    }

    $ResourceReadable
    $PropertiesReadable = @{}
    #pset up the properties of the resource to get a list of the information
    $Properties = $Resource.Properties | get-member -MemberType NoteProperty
    #check if the resourcetype is a deployment. It will be a nested resource and the properties will be a little lower down the line 
    if ($Resource.type -eq "Microsoft.Resources/deployments") {
        $Properties = $Resource.Properties.template.Resources.Properties | get-member -MemberType NoteProperty
        foreach ($Property in $Properties) {
        
            $propname = $Property.Name
          
            $key = $propname
            $value = $($Resource.Properties.template.Resources.Properties.$propname)
            $PropertiesReadable.add($key, $value)
        }
        Write-Output "Properties:"
        $PropertiesReadable
    
        Write-Output " "
    }
    else {
        foreach ($Property in $Properties) {
        
            $propname = $Property.Name

            $key = $propname
            $value = $($Resource.Properties.$propname)
            $PropertiesReadable.add($key, $value)
        }
        Write-Output "Properties:"
        $PropertiesReadable

        Write-Output " "
    }
}