# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

function Invoke-PowerShell
{
    <#
    .SYNOPSIS
    Invokes a script block or script in a separate powershell.exe process.
    
    .DESCRIPTION
    The `Invoke-PowerShell` scripts runs a script block or a PowerShell script under a new `powershell.exe` process. You pass arguments to the script block or script with the `ArgumentList` parameter. To pass parameters to `powershell.exe` itself, use the other switches and parameters.

    If using PowerShell v2.0, the invoked PowerShell process can run under the .NET 4.0 CLR (using `v4.0` as the value to the Runtime parameter).

    If using PowerShell v3.0, you can *only* run script blocks under a `v4.0` CLR.  PowerShell converts script blocks to an encoded command, and when running encoded commands, PowerShell doesn't allow the `-Version` parameter for running PowerShell under a different version.  To run code under a .NET 2.0 CLR from PowerShell 3, use the `FilePath` parameter to run a specfic script.
    
    This function launches a PowerShell process that matches the architecture of the *operating system*.  On 64-bit operating systems, you can run under 32-bit PowerShell by specifying the `x86` switch).

    PowerShell's execution policy has to be set seperately in all architectures (i.e. x86 and x64), so you may get an error message about scripts being disabled.  Use the `-ExecutionPolicy` parameter to set a temporary execution policy when running a script.

    Beginning with PowerShell 2.3.0, you can run a PowerShell script as another user. Pass the user's credentials to the `$Credential` parameter.
    
    .EXAMPLE
    Invoke-PowerShell -Command { $PSVersionTable }
    
    Runs a separate PowerShell process which matches the architecture of the operating system, returning the $PSVersionTable from that process.  This will fail under 32-bit PowerShell on a 64-bit operating system.
    
    .EXAMPLE
    Invoke-PowerShell -Command { $PSVersionTable } -x86
    
    Runs a 32-bit PowerShell process, return the $PSVersionTable from that process.
    
    .EXAMPLE
    Invoke-PowerShell -Command { $PSVersionTable } -Runtime v4.0
    
    Runs a separate PowerShell process under the v4.0 .NET CLR, returning the $PSVersionTable from that process.  Should return a CLRVersion of `4.0`.
    
    .EXAMPLE
    Invoke-PowerShell -FilePath C:\Projects\Carbon\bin\Set-DotNetConnectionString.ps1 -ArgumentList '-Name','myConn','-Value',"'data source=.\DevDB;Integrated Security=SSPI;'"
    
    Runs the `Set-DotNetConnectionString.ps1` script with `ArgumentList` as arguments/parameters.
    
    Note that you have to double-quote any arguments with spaces.  Otherwise, the argument gets interpreted as multiple arguments.

    .EXAMPLE
    Invoke-PowerShell -FilePath Get-PsVersionTable.ps1 -x86 -ExecutionPolicy RemoteSigned

    Shows how to run powershell.exe with a custom executin policy, in case the running of scripts is disabled.

    .EXAMPLE
    Invoke-PowerShell -FilePath Get-PsVersionTable.ps1 -Credential $cred

    Demonstrates that you can run PowerShell scripts as a specific user with the `Credential` parameter.

    .EXAMPLE
    Invoke-PowerShell -FilePath Get-PsVersionTable.ps1 -Credential $cred

    Demonstrates that you can run PowerShell scripts as a specific user with the `Credential` parameter.
    #>
    [CmdletBinding(DefaultParameterSetName='ScriptBlock')]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='ScriptBlock')]
        [Parameter(Mandatory=$true,ParameterSetName='CommandWithCredential')]
        [Alias('Command')]
        [object]
        # Pass a script block or a string of PowerShell code.
        #
        # If you pass a string, you can run that command as another user with the `Credential` parameter.
        $ScriptBlock,
        
        [Parameter(Mandatory=$true,ParameterSetName='FilePath')]
        [Parameter(Mandatory=$true,ParameterSetName='FilePathWithCredential')]
        [string]
        # The script to run.
        $FilePath,

        [Parameter(Mandatory=$true,ParameterSetName='ScriptBlock')]
        [Parameter(Mandatory=$true,ParameterSetName='FilePath')]
        [Parameter(Mandatory=$true,ParameterSetName='FilePathWithCredential')]
        [object[]]
        [Alias('Args')]
        # Any arguments to pass to the command/scripts. These *are not* powershell.exe arguments.
        $ArgumentList,

        [Parameter(ParameterSetName='CommandWithCredential')]
        [Switch]
        # Base-64 encode the command in `ScriptBlock` and run it with PowerShell.exe's -EncodedCommand switch.
        $Encode,
        
        [string]
        # Determines how output from the PowerShel command is formatted
        $OutputFormat,

        [Parameter(ParameterSetName='FilePath')]
        [Parameter(ParameterSetName='CommandWithCredential')]
        [Microsoft.PowerShell.ExecutionPolicy]
        # The execution policy to use when running a script.  By default, execution policies are set to `Restricted`. If running an architecture of PowerShell whose execution policy isn't set, `Invoke-PowerShell` will fail.
        $ExecutionPolicy,

        [Switch]
        # Run PowerShell non-interactively. This passes the `-NonInteractive` switch to powershell.exe.
        $NonInteractive,

        [Switch]
        # Run the x86 (32-bit) version of PowerShell, otherwise the version which matches the OS architecture is run, *regardless of the architecture of the currently running process*.
        $x86,
        
        [string]
        [ValidateSet('v2.0','v4.0')]
        # The CLR to use.  Must be one of `v2.0` or `v4.0`.  Default is the current PowerShell runtime.
        $Runtime,

        [Parameter(ParameterSetName='FilePath')]
        [Parameter(Mandatory=$true,ParameterSetName='CommandWithCredential')]
        [pscredential]
        # Run the process as this user.
        #
        # This parameter is new in Carbon 2.3.0.
        $Credential
    )
    
    Set-StrictMode -Version 'Latest'

    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

    $powerShellv3Installed = Test-Path -Path HKLM:\SOFTWARE\Microsoft\PowerShell\3
    $currentRuntime = 'v{0}.0' -f $PSVersionTable.CLRVersion.Major
    if( $powerShellv3Installed )
    {
        $currentRuntime = 'v4.0'
    }

    # Check that the selected runtime is installed.
    if( $PSBoundParameters.ContainsKey('Runtime') )
    {
        $runtimeInstalled = switch( $Runtime )
        {
            'v2.0' { Test-DotNet -V2 }
            'v4.0' { Test-DotNet -V4 -Full }
            default { Write-Error ('Unknown runtime value ''{0}''.' -f $Runtime) }
        }

        if( -not $runtimeInstalled )
        {
            Write-Error ('.NET {0} not found.' -f $Runtime)
            return
        }
    }


    if( -not $Runtime )
    {
        $Runtime = $currentRuntime
    }

    if(  $PSCmdlet.ParameterSetName -eq 'ScriptBlock' -and `
         $Host.Name -eq 'Windows PowerShell ISE Host' -and `
         $Runtime -eq 'v2.0' -and `
         $powerShellv3Installed )
    {
        Write-Error ('The PowerShell ISE v{0} can''t run script blocks under .NET {1}. Please run from the PowerShell console, or save your script block into a file and re-run Invoke-PowerShell using the `FilePath` parameter.' -f `
                        $PSVersionTable.PSVersion,$Runtime)
        return
    }

    $comPlusAppConfigEnvVarName = 'COMPLUS_ApplicationMigrationRuntimeActivationConfigPath'
    $activationConfigDir = Join-Path $env:TEMP ([IO.Path]::GetRandomFileName())
    $activationConfigPath = Join-Path $activationConfigDir powershell.exe.activation_config
    $originalCOMAppConfigEnvVar = [Environment]::GetEnvironmentVariable( $comPlusAppConfigEnvVarName )
    if( -not $powerShellv3Installed -and $currentRuntime -ne $Runtime )
    {
        $null = New-Item -Path $activationConfigDir -ItemType Directory
        @"
<?xml version="1.0" encoding="utf-8" ?>
<configuration>
  <startup useLegacyV2RuntimeActivationPolicy="true">
    <supportedRuntime version="{0}" />
  </startup>
</configuration>
"@ -f $Runtime | Out-File -FilePath $activationConfigPath -Encoding OEM
        Set-EnvironmentVariable -Name $comPlusAppConfigEnvVarName -Value $activationConfigDir -ForProcess
    }
    
    $params = @{ }
    if( $x86 )
    {
        $params.x86 = $true
    }
    
    try
    {
        $psPath = Get-PowerShellPath @params
        if( $ArgumentList -eq $null )
        {
            $ArgumentList = @()
        }

        $powerShellArgs = Invoke-Command -ScriptBlock {
            if( $powerShellv3Installed -and $Runtime -eq 'v2.0' )
            {
                '-Version'
                '2.0'
            }

            if( $NonInteractive )
            {
                '-NonInteractive'
            }

            '-NoProfile'

            if( $OutputFormat )
            {
                '-OutputFormat'
                $OutputFormat
            }

            if( $ExecutionPolicy -and $PSCmdlet.ParameterSetName -ne 'ScriptBlock' )
            {
                '-ExecutionPolicy'
                $ExecutionPolicy
            }
        }

        if( $PSCmdlet.ParameterSetName -eq 'ScriptBlock' )
        {
            & $psPath $powerShellArgs -Command $ScriptBlock -Args $ArgumentList
        }
        elseif( $PSCmdlet.ParameterSetName -like 'FilePath*' )
        {
            if( $Credential )
            {
                Start-PowerShellProcess -CommandLine ('{0} -File "{1}" {2}' -f ($powerShellArgs -join " "),$FilePath,($ArgumentList -join " ")) -Credential $Credential
            }
            else
            {
                Write-Debug ('{0} {1} -File {2} {3}' -f $psPath,($powerShellArgs -join " "),$FilePath,($ArgumentList -join ' '))
                & $psPath $powerShellArgs -File $FilePath $ArgumentList
                Write-Debug ('LASTEXITCODE: {0}' -f $LASTEXITCODE)
            }
        }
        else
        {
            $argName = '-Command'
            if( $Encode )
            {
                $ScriptBlock = ConvertTo-Base64 -Value $ScriptBlock
                $argName = '-EncodedCommand'
            }
            Start-PowerShellProcess -CommandLine ('{0} {1} {2}' -f ($powerShellArgs -join " "),$argName,$ScriptBlock) -Credential $Credential
        }
    }
    finally
    {
        if( Test-Path -Path $activationConfigDir -PathType Leaf )
        {
            Remove-Item -Path $activationConfigDir -Recurse -Force
        }

        if( Test-Path -Path env:$comPlusAppConfigEnvVarName )
        {
            if( $originalCOMAppConfigEnvVar )
            {
                Set-EnvironmentVariable -Name $comPlusAppConfigEnvVarName -Value $originalCOMAppConfigEnvVar -ForProcess
            }
            else
            {
                Remove-EnvironmentVariable -Name $comPlusAppConfigEnvVarName -ForProcess
            }
        }
    }
}

