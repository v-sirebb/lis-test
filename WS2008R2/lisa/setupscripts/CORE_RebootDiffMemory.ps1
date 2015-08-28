########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################



<#
.Synopsis
    Test LIS and shutdown with different ram settings

.Description
    Test LIS and shutdown with different ram settings
    The XML test case definition for this test would
    look similar to the following:
        <test>
            <testName>RebootDiffSize</testName>
            <testParams>
                <param>TC_COVERED=CORE-17</param>
                <param>MemSize=5GB,2GB</param>
            </testParams>
            <testScript>SetupScripts\CORE_RebootDiffMemory.ps1</testScript>
            <timeout>10800</timeout>
        </test>

.Parameter
    Name of VM to test

.Parameter
    Name of Hyper-V server hosting the VM

.Parameter
    Semicolon separated list of test parameters

.Example

#>


param([string] $vmName, [string] $hvServer, [string] $testParams)

#####################################################################
#
# CheckCurrentStateFor()
#
#####################################################################
function CheckCurrentStateFor([String] $vmName, [UInt16] $newState)
{
    $stateChanged = $False
    $vm = Get-VM $vmName -server $hvServer
    if ($($vm.EnabledState) -eq $newState)
    {
        $stateChanged = $True
    }
    return $stateChanged
}

#######################################################################
#
# Main script block
#
#######################################################################

$retVal = $false

#
# Check input arguments
#
if ($vmName -eq $null)
{
    "Error: VM name is null"
    return $retVal
}

if ($hvServer -eq $null)
{
    "Error: hvServer is null"
    return $retVal
}

$sshKey = $null
$ipv4 = $null
$rootDir = $null
$TC_COVERED = "Undefined"
$memArgs = $null

$params = $testParams.Split(";")

foreach ($p in $params)
{
    $fields = $p.Split("=")
    if ($fields.Length -ne 2)
    {
        # Malformed - just ignore
        continue
    }

    switch ($fields[0].Trim())
    {
    "sshKey"     { $sshKey    = $fields[1].Trim() }
    "ipv4"       { $ipv4      = $fields[1].Trim() }
    "rootdir"    { $rootDir   = $fields[1].Trim() }
    "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    "MemSize" { $memArgs      = $fields[1].Split(',') }
    default   {}
    }
}

#
# Make sure the required test params are provided
#
if ($null -eq $sshKey)
{
    Write-output "Error: Test parameter sshKey was not specified" 
    return $False
}

if ($null -eq $ipv4)
{
    Write-output "Error: Test parameter ipv4 was not specified" 
    return $False
}

if (-not $rootDir)
{
    Write-output "Error: Test parameter rootDir was not specified" 
    return $False
}

if (-not $memArgs)
{
    Write-output "Error: Test parameter MemSize was not specified" 
    return $False
}

#
# Change the working directory to where we need to be
#
if (-not (Test-Path $rootDir))
{
    Write-output"Error: The directory `"${rootDir}`" does not exist" 
    return $False
}

cd $rootDir

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-output "This script covers test case: ${TC_COVERED}" 

#
# Source the TCUtils.ps1 file
#
. .\setupscripts\TCUtils.ps1

$success = $True

ForEach ($memory in $memArgs)
{
    $retVal = $False
    #
    # Shutdown VM.
    #
    $vm = Get-VM -Name $vmName -Server $hvServer
#
    $testCaseTimeout = 180
    
    Stop-VM -VM $vmName -Server $hvServer -force    
    while ($testCaseTimeout -gt 0)
    {
        if ( (CheckCurrentStateFor $vmName ([UInt16][VMState]::stopped)))
        {
            break
        }
        Start-Sleep -seconds 2
        $testCaseTimeout -= 2
    }

    $memoryParam = "VMMemory=${memory}"
    .\setupScripts\SetVMMemory.ps1 -vmName $vmName -hvServer $hvServer -testParams $memoryParam
    if ($? -eq "True")
    {
        Write-output "VM Memory count updated to $memory" 
    }
    else
    {
        Write-output "Error: Unable to update VM memory" 
        return $False
    }

    $Error.Clear()
    Start-VM -VM $vmName -Server $hvServer  -ErrorAction SilentlyContinue
    if ( $Error[0] -and $Error[0].Exception.Message.Contains("Not enough memory") )
    {
        Write-output "Error: Not enough memory ($memory) to start VM." 
        continue
    }
    $Error.Clear()

    $timeout = 180
    while ($timeout -gt 0)
    {
        #
        # Check if the VM is in the Hyper-v Running state
        #
        $ipv4 = GetIPv4 $vmName $hvServer
        if ( $ipv4)
        {
            break
        }
        start-sleep -seconds 1
        $timeout -= 1
    }

    if($timeout -le 0)
    {
        Write-output "VM timeout at GetIPv4 operation with memory size $memory" 
        $success = $False
    }
    else
    {
        Write-output "VM started with $memory" 
        $retVal = $True
    }
}

return $retVal -and $success
