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

. "$PSScriptRoot\GitDownloader.ps1"

Save-GitRepository -RepositoryUrl $RepositoryUrl -RepositoryPath $RepositoryPath -BranchTag $BranchTag -Clean $Clean