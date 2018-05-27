. "$PSScriptRoot\..\GitDownloader\GitDownloader.ps1"

Describe 'Current branch/tag' {
    If ((Get-Command -Name git -CommandType Application -ErrorAction Ignore) -eq $null) {
        If (-not (Test-Path -Path "$($env:ProgramFiles)\Git\bin\git.exe" -PathType Leaf)) {
            Write-Error "Git command line is required to run the test" -ErrorAction Stop
        }
        Set-Alias -Name git -Value $env:ProgramFiles\Git\bin\git.exe -Force | Out-Null        
    }
    $CurrentWd = (Get-Item .).FullName
    BeforeEach {
        New-Item -Path TestDrive:\git -ItemType Directory -Force
        Set-Location TestDrive:\git
        git init
        Set-Content -Path 'file.txt' -Value 'Hello world!'
        git add .
        git commit -m 'dummy file'
        git tag v1.0.0
    }
    AfterEach {
        Set-Location $CurrentWd
        Remove-Item -Path TestDrive:\git -Recurse -Force
    }
    It 'Is the branch name when currently in branch' {
        git checkout master 2>&1 | Out-Null

        Get-GitCurrentBranch | Should Be 'master'
    }
    It 'Is the tag name when currently in tag' {
        git checkout v1.0.0 2>&1 | Out-Null

        Get-GitCurrentBranch | Should Be 'v1.0.0'
    }
}

Describe 'Git clone' {
	Function git () {}
	Mock git { }
	Mock Write-Host { }
    It 'Does not use token when in same VSTS server' {
        Mock Test-SameTfsServer { return $false }
 
        Invoke-GitCloneRepository -Uri 'http://dummy/repo.git' -BranchTag 'master' -Path TestDrive:\repo.git
		Assert-MockCalled git -ParameterFilter { 'clone --single-branch --progress -b master http://dummy/repo.git TestDrive:\repo.git' -eq $args }
   }
    It 'Uses token when in same VSTS server' {
        Mock Test-SameTfsServer { return $true }
        Mock Get-EnvironmentVariable { return 'token' } -ParameterFilter { $Name -eq 'SYSTEM_ACCESSTOKEN' }
 
        Invoke-GitCloneRepository -Uri 'http://dummy/repo.git' -BranchTag 'master' -Path TestDrive:\repo.git
		Assert-MockCalled git -ParameterFilter { '-c http.extraheader=Authorization: bearer token clone --single-branch --progress -b master http://dummy/repo.git TestDrive:\repo.git' -eq $args }
   }
}

Describe 'Git update repository' {
	Function git () {}
	Mock git { }
	Mock Get-GitFetchUri { Return 'http://dummy/repo.git' }
	Mock Get-GitCurrentBranch { Return 'master' }
	Mock Set-Location { }
	Mock Write-Host { }
   	It 'Does not use token when not in same VSTS server' {
		Mock Test-SameTfsServer { return $false }
 
        Update-GitRepository -BranchTag 'master' -Path TestDrive:\repo.git
		Assert-MockCalled git -ParameterFilter { 'pull origin master' -eq $args }
	}
    It 'Uses token when in same VSTS server' {
		Mock Test-SameTfsServer { return $true }
        Mock Get-EnvironmentVariable { return 'token' } -ParameterFilter { $Name -eq 'SYSTEM_ACCESSTOKEN' }
 
        Update-GitRepository -BranchTag 'master' -Path TestDrive:\repo.git
		Assert-MockCalled git -ParameterFilter { '-c http.extraheader=Authorization: bearer token pull origin master' -eq $args }
	}
}