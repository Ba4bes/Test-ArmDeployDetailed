function Test-ArmDeployDetailed {
    <#
.SYNOPSIS
Tests an azure deployment for error and outputs the recources that will be deployed

.DESCRIPTION
This function will first test an Arm deployment with Test-AzureRmResourceGroupDeployment. 
If a generic error pops up, it will search for details in Azure.
If this test succeeds, an output will be generated that will show what resources will be deployed


.PARAMETER ResourceGroup
The resourcegroup where the resources would be deployed to. Must exist. 

.PARAMETER TemplatePath
The path to the deploymentfile

.PARAMETER ParametersPath
The path to the parameterfile

.EXAMPLE
Test-ArmDeployDetailed -ResourceGroup Resourcegroup1 -TemplatePath .\armdeploy.json -ParametersPath .\armdeploy.parameters.json

.NOTES
Created by Barbara Forbes, 13-12-2018
Source for more output: #Source https://blog.mexia.com.au/testing-arm-templates-with-pester
#>

    Param(
        [string] [Parameter(Mandatory = $true)] $ResourceGroup,
        [string] [Parameter(Mandatory = $true)] $TemplatePath,
        [string] [Parameter(Mandatory = $true)] $ParametersPath

    )

    #requires -modules AzureRM

    #give the parameters back to caller
    Write-Verbose " Parameters set:"
    Write-Verbose "Resourcegroup: $ResourceGroup"
    Write-Verbose "Templatepath: $TemplatePath"
    Write-Verbose "Parameterpath: $ParametersPath"

    #Check for AzureRMConnection
    Try {
        Get-AzureRmContext -ErrorAction Stop | out-null
    }
    Catch {
        if ($_ -like "*Login-AzureRmAccount to login*") {
            Login-AzureRmAccount
        }
        Else {

            throw "Couldn't find AzureRMContext, script is stopping"
        
            exit
        }
    }

    #check if resourcegroup exist
    try {
        Get-AzureRmResourceGroup $ResourceGroup  -ErrorAction Stop | Out-Null 
    }
    catch {
        Write-Output "Resourcegroup $ResourceGroup does not exist. Please check your spelling or create the resourcegroup"
        exit
    }


    #make sure the debugpreference is right, as otherwise the Simple Test will give confusing results
    $DebugPreference = "SilentlyContinue"

    #set variables
    $SimpleOutput = $null
    $DetailedError = $null
    $Parameters = @{
        ResourceGroupName     = $ResourceGroup 
        TemplateFile          = $TemplatePath
        TemplateParameterFile = $ParametersPath
    }
    Write-Verbose "Test is starting"
    # take a simple test
    
    $SimpleOutput = Test-AzureRmResourceGroupDeployment @parameters 

    #Check for a secific output. It can sometimes give a very generic error-message. 
    #So this looks for the more clear errormessage in the AzureLogs.
    if ($SimpleOutput.Message -like "*s not valid according to the validation procedure*") {
        Write-Verbose "Something is off, waiting for the logfile"
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

    Write-Verbose "Test is done"

    if ($SimpleOutput) {
        Write-Output "something is off with your template"
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
        exit 
    }
    else {
        Write-Output "deployment is correct"
    }


    Write-Verbose "Starting with big test"
    #output to null as in case of error, you would run the script more than once
    $Output = $null
    #set debugpreference to continue so the Test-AzureRmResourceGroupDeployment runs with more output
    $DebugPreference = "Continue"

    $Output = Test-AzureRmResourceGroupDeployment @parameters 5>&1

    #Set DebugPreference back to normal
    $DebugPreference = "SilentlyContinue"

    Write-Verbose "collected Output"

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

}