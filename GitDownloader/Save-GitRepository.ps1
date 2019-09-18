[CmdletBinding()]
param()

Trace-VstsEnteringInvocation $MyInvocation
try {
	# get the inputs
	[string]$RepositoryUrl = Get-VstsInput -Name RepositoryUrl
	[string]$RepositoryPath = Get-VstsInput -Name RepositoryPath
	[string]$BranchTag = Get-VstsInput -Name BranchTag
	[bool]$Clean = Get-VstsInput -Name Clean -AsBool
	
	# import the helpers
	. "$PSScriptRoot\GitDownloader.ps1"

	Save-GitRepository -RepositoryUrl $RepositoryUrl -RepositoryPath $RepositoryPath -BranchTag $BranchTag -Clean $Clean
}
finally {
	Trace-VstsLeavingInvocation $MyInvocation
}