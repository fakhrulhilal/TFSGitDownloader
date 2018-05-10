Function Get-EnvironmentVariable {
    param([string]$Name)

    Return [Environment]::GetEnvironmentVariable($Name)
}

Function Get-GitCurrentBranch {
    $branch = (git symbolic-ref -q --short HEAD)
    If (-not ([string]::IsNullOrEmpty($branch)) -and ($branch -ne 'HEAD')) {
        Return $branch
    }
    $tag = (git describe --tags --exact-match)
    Return $tag
}

Function Invoke-VerboseCommand {
    param(
        [ScriptBlock]$Command,
        [string] $StderrPrefix = "",
        [int[]]$AllowedExitCodes = @(0)
    )
    $Script = $Command.ToString()
    $Captures = Select-String '\$(\w+)' -Input $Script -AllMatches
    ForEach ($Capture in $Captures.Matches) {
        $Variable = $Capture.Groups[1].Value
        $Value = Get-Variable -Name $Variable -ValueOnly
        $Script = $Script.Replace("`$$($Variable)", $Value)
    }
    Write-Host $Script
    If ($script:ErrorActionPreference -ne $null) {
        $backupErrorActionPreference = $script:ErrorActionPreference
    } ElseIf ($ErrorActionPreference -ne $null) {
        $backupErrorActionPreference = $ErrorActionPreference
    }
    $script:ErrorActionPreference = "Continue"
    try
    {
        & $Command 2>&1 | ForEach-Object -Process `
        {
            if ($_ -is [System.Management.Automation.ErrorRecord])
            {
                "$StderrPrefix$_"
            }
            else
            {
                "$_"
            }
        }
        if ($AllowedExitCodes -notcontains $LASTEXITCODE)
        {
            throw "Execution failed with exit code $LASTEXITCODE"
        }
    }
    finally
    {
        $script:ErrorActionPreference = $backupErrorActionPreference
    }
}

Function Update-GitRepository {
    param(
        [string]$Path,
        [string]$BranchTag
    )

    Write-Host "Updating repository inside $Path"
    Set-Location $Path | Out-Null
    $CurrentBranch = Get-GitCurrentBranch
    Invoke-VerboseCommand -Command { 
        git add .
        git stash 
    }
    If ($CurrentBranch -ine $BranchTag) {
        Write-Host "Undoing any pending changes in $Path"
        Invoke-VerboseCommand -Command {
            git checkout $BranchTag
            git checkout -- .
            git clean -fdx
        }
    }
    # get current fetch uri
    $remoteUris = git remote -v
    $match = [regex]::Match($remoteUris, '^(origin)\s(?<url>.+)\s\(fetch\)\W')
    $fetchUri = $match.Groups['url'].Value
    Write-Host "Pulling update from branch/tag $BranchTag"
    Invoke-VerboseCommand -Command { git config credential.interactive never }
    # try to use token provided by TFS server
    If (Test-SameTfsServer -Uri $fetchUri) {
        $SystemToken = Get-EnvironmentVariable -Name 'SYSTEM_ACCESSTOKEN'
        $AuthHeader = "Authorization: bearer $SystemToken"
        Invoke-VerboseCommand -Command { git -c http.extraheader="$AuthHeader" pull origin $BranchTag }
    }
    Else {
        Invoke-VerboseCommand -Command { git pull origin $BranchTag }
    }
}

Function Invoke-GitCloneRepository {
    param(
        [string]$Uri,
        [string]$BranchTag,
        [string]$Path
    )

    Write-Host "Cloning $Uri for branch/tag '$BranchTag' into $Path"
    # try to embed authentication from system token for same TFS server
    If ((Test-SameTfsServer -Uri $Uri)) {
        $SystemToken = Get-EnvironmentVariable -Name 'SYSTEM_ACCESSTOKEN'
        $AuthHeader = "Authorization: bearer $SystemToken"
        Invoke-VerboseCommand -Command { git -c http.extraheader="$AuthHeader" clone --single-branch --progress -b $BranchTag "$Uri" "$Path" }
    }
    Else {
        Invoke-VerboseCommand -Command { git clone --single-branch --progress -b $BranchTag "$Uri" "$Path" }
    }
    If ($LastExitCode -ne 0) {
        Write-Error $output -ErrorAction Stop
    }
}

Function Get-GitRepositoryUri {
    $VstsUri = Get-EnvironmentVariable -Name 'SYSTEM_TEAMFOUNDATIONCOLLECTIONURI'
    $TeamProject = Get-EnvironmentVariable -Name 'SYSTEM_TEAMPROJECT'
    $Uris =  @($VstsUri, $TeamProject, '_git') | %{ $_.Trim('/') }
    Return $Uris -join '/'
}

Function Get-GitDirectory {
    $AgentBuildDir = Get-EnvironmentVariable -Name 'AGENT_BUILDDIRECTORY'
    $AgentReleaseDir = Get-EnvironmentVariable -Name 'AGENT_RELEASEDIRECTORY'
	If (-not ([string]::IsNullOrWhiteSpace($AgentBuildDir)) -and (Test-Path -Path $AgentBuildDir -PathType Container)) {
		$Directory = $AgentBuildDir
	} ElseIf (-not ([string]::IsNullOrWhiteSpace($AgentReleaseDir)) -and (Test-Path $AgentReleaseDir -PathType Container)) {
		$Directory = $AgentReleaseDir
	}

	Return ([System.IO.Path]::Combine($Directory, 'git'))
}

Function Test-SameTfsServer {
    param([string]$Uri)
    $DefaultUri = Get-EnvironmentVariable -Name 'SYSTEM_TEAMFOUNDATIONCOLLECTIONURI'
    # we don't care the protocol, either http or https
    $DefaultUri = $DefaultUri -replace '^https?:', ''
    $Uri = $Uri -replace '^https?:', ''
    $escapedPattern = [regex]::Escape($DefaultUri)
    Return $Uri -match "^($($escapedPattern))"
}

Function Save-GitRepository {
    [CmdletBinding()]
    param(
        # repository name
        [string]
        [parameter(mandatory=$true)]
        $RepositoryUrl,
    
        # the root directory to store all git repositories
        [string]
        [parameter(mandatory=$false)]
        $RepositoryPath,
    
        # branch/tag name to checkout
        [parameter(mandatory=$false)]
        [string]
        $BranchTag = 'master',
    
        # determine whether to clean the folder before downloading the repository or not (default: false)
        [parameter(mandatory=$false)]
        [string]
        [ValidateSet('true', 'false', 'yes', 'no')]
        $Clean = 'false'
    )
    try {
        # try to find in PATH environment
        Get-Command -Name git -CommandType Application -ErrorAction Stop | Out-Null
    } catch [System.Management.Automation.CommandNotFoundException] {
        # try to find git in default location
        If (-not (Test-Path -Path "$($env:ProgramFiles)\Git\bin\git.exe" -PathType Leaf)) {
            Write-Error "Git command line not found or not installed" -ErrorAction Stop
        }
        Set-Alias -Name git -Value $env:ProgramFiles\Git\bin\git.exe -Force | Out-Null
    }

    $GitRepositoryUri = Get-GitRepositoryUri
    Write-Host "##vso[task.setvariable variable=Build.Repository.GitUri]$GitRepositoryUri"
    $RepositoryUrl = $RepositoryUrl -replace ([regex]::Escape('$(Build.Repository.GitUri)')), $GitRepositoryUri
    $GitDirectory = Get-GitDirectory
    Write-Host "##vso[task.setvariable variable=Build.GitDirectory]$GitDirectory"
    If ([string]::IsNullOrWhiteSpace($RepositoryPath)) {
        $captured = [regex]::Match($RepositoryUrl, '^(\w+:)?(?<separator>/|\\){1,2}')
        $Separator = '/'
        If ($captured.Success) {
            $Separator = $captured.Groups['separator'].Value[0]
        }
        # set default repository path
        $RepositoryName = $RepositoryUrl.Substring($RepositoryUrl.TrimEnd($Separator).LastIndexOf($Separator) + 1)
        $RepositoryPath = "`$(Build.GitDirectory)\$RepositoryName"
    }
    $RepositoryPath = $RepositoryPath -replace ([regex]::Escape('$(Build.GitDirectory)')), $GitDirectory

    # ensure containing git folder exists
    $RepositoryFolder = [System.IO.Path]::GetDirectoryName($RepositoryPath)
    If (-not (Test-Path -Path "$RepositoryFolder" -PathType Container)) {
        Write-Host "Creating git directory: $RepositoryFolder"
        New-Item -Path "$RepositoryFolder" -ItemType Directory -Force | Out-Null
    }

    $CurrentDirectory = (Get-Location).Path
    If (Test-Path -Path "$RepositoryPath" -PathType Container) {
        If (@('true', 'yes').Contains($Clean.ToLower())) {
            Write-Host "Cleaning directory $RepositoryPath"
            Remove-Item -Path "$RepositoryPath" -Recurse -Force | Out-Null
            Invoke-GitCloneRepository -Path "$RepositoryPath" -Uri "$RepositoryUrl" -BranchTag $BranchTag
        }
        Else {
            Update-GitRepository -Path "$RepositoryPath" -BranchTag $BranchTag
        }
    }
    Else {
        Invoke-GitCloneRepository -Path "$RepositoryPath" -Uri "$RepositoryUrl" -BranchTag $BranchTag
    }

    Set-Location "$CurrentDirectory"
}
