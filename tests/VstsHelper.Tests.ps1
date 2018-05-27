. "$PSScriptRoot\..\GitDownloader\GitDownloader.ps1"

Describe 'Default git URI' {
    $FakeVstsUri = 'https://account.visualstudio.com/'
    $FakeTeamProject = 'OpenSource'
    It 'Returns VSTS URI & Team Project for git URI' {
        Mock Get-EnvironmentVariable { return $FakeVstsUri } -ParameterFilter { $Name -eq 'SYSTEM_TEAMFOUNDATIONCOLLECTIONURI' }
        Mock Get-EnvironmentVariable { return $FakeTeamProject } -ParameterFilter { $Name -eq 'SYSTEM_TEAMPROJECT' }

        Get-GitRepositoryUri | Should Be 'https://account.visualstudio.com/OpenSource/_git'
    }
}

Describe 'Default git directory' {
    $FakeAgentPath = 'TestDrive:\w\a1'
    BeforeEach {
        New-Item -Path "$FakeAgentPath\r" -ItemType Directory -Force
        New-Item -Path "$FakeAgentPath\r1" -ItemType Directory -Force
    }
    It 'Returns "git" inside build dir when triggered through build definition' {
        Mock Get-EnvironmentVariable { return "$FakeAgentPath\r" } -ParameterFilter { $Name -eq 'AGENT_BUILDDIRECTORY' }

        Get-GitDirectory | Should Be "$FakeAgentPath\r\git"
    }
    It 'Returns "git" inside release dir when triggered through release definition' {
        Mock Get-EnvironmentVariable { return "$FakeAgentPath\r1" } -ParameterFilter { $Name -eq 'AGENT_RELEASEDIRECTORY' }
        # mock can't run inside test scope, therefor, we need to remove build dir for correct scenario
        Remove-Item -Path "$FakeAgentPath\r" -Force

        Get-GitDirectory | Should Be "$FakeAgentPath\r1\git"
    }
}

Describe 'Same VSTS server' {
    Mock Get-EnvironmentVariable { return 'https://subdomain.on.company.com/tfs' } -ParameterFilter { $Name -eq 'SYSTEM_TEAMFOUNDATIONCOLLECTIONURI' }
    It 'Same when both use same domain' {
        Test-SameTfsServer -Uri 'https://subdomain.on.company.com/tfs/OpenSource/_git/Project' | Should Be $true
    }
    It 'Not same when both use different domain' {
        Test-SameTfsServer -Uri 'https://subdomain/tfs/OpenSource/_git/Project' | Should Be $false
    }
    It 'Same when using different protocol' {
        Test-SameTfsServer -Uri 'http://subdomain.on.company.com/tfs/OpenSource/_git/Project' | Should Be $true
    }
}