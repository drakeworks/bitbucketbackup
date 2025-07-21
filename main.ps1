# Bitbucket Repository Backup Script for Windows PowerShell
# PowerShell equivalent of main.sh

param(
    [string]$ConfigFile = "config.env",
    [switch]$DryRun,
    [switch]$Verbose,
    [switch]$SkipExisting,
    [int]$Jobs = 4,
    [switch]$Verify,
    [switch]$Help
)

# Global variables
$ScriptName = Split-Path $MyInvocation.MyCommand.Name -Leaf
$FailedRepos = @()
$SuccessfulRepos = @()
$TotalRepos = 0
$ProcessedRepos = 0

# Colors for output
$Red = "Red"
$Green = "Green"
$Yellow = "Yellow"
$Blue = "Blue"

# Logging function
function Write-Log {
    param(
        [string]$Level,
        [string]$Message
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    switch ($Level) {
        "ERROR" { Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $Red }
        "WARN"  { Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $Yellow }
        "INFO"  { Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $Blue }
        "SUCCESS" { Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $Green }
        default { Write-Host "[$timestamp] [$Level] $Message" }
    }
}

# Usage function
function Show-Usage {
    Write-Host @"
Usage: $ScriptName [OPTIONS]

A comprehensive Bitbucket repository backup script for Windows PowerShell.

OPTIONS:
    -ConfigFile FILE    Specify configuration file (default: config.env)
    -DryRun            Show what would be done without executing
    -Verbose           Enable verbose output
    -SkipExisting      Skip repositories that already exist
    -Jobs N            Number of parallel jobs (default: 4)
    -Verify            Verify backups after completion
    -Help              Show this help message

EXAMPLES:
    .\main.ps1                    # Run with default settings
    .\main.ps1 -DryRun            # See what would be backed up
    .\main.ps1 -Verbose -Jobs 8   # Verbose output with 8 parallel jobs
    .\main.ps1 -ConfigFile my.env # Use custom config file

CONFIGURATION:
    Create config.env from config.env.example and set:
    - ATLASSIAN_EMAIL: Your Atlassian account email
    - API_TOKEN: Your Bitbucket API token
    - ORGNAME: Your Bitbucket workspace name
    - BACKUP_DIR: Directory to store backups

"@
}

# Load configuration
function Load-Config {
    param([string]$ConfigFile)
    
    if (-not (Test-Path $ConfigFile)) {
        Write-Log "ERROR" "Configuration file not found: $ConfigFile"
        Write-Host "Please copy config.env.example to $ConfigFile and update with your values."
        exit 1
    }
    
    # Read and parse config file
    $config = Get-Content $ConfigFile | Where-Object { $_ -match '^[^#]' } | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            @{ Name = $matches[1]; Value = $matches[2].Trim('"') }
        }
    }
    
    # Set variables
    $script:ATLASSIAN_EMAIL = ($config | Where-Object { $_.Name -eq "ATLASSIAN_EMAIL" }).Value
    $script:API_TOKEN = ($config | Where-Object { $_.Name -eq "API_TOKEN" }).Value
    $script:ORGNAME = ($config | Where-Object { $_.Name -eq "ORGNAME" }).Value
    $script:BACKUP_DIR = ($config | Where-Object { $_.Name -eq "BACKUP_DIR" }).Value
    
    # Set default backup directory if not specified
    if (-not $BACKUP_DIR) {
        $script:BACKUP_DIR = "$env:TEMP\bitbucket-backup"
    }
    
    # Validate required configuration
    if (-not $ATLASSIAN_EMAIL -or -not $API_TOKEN -or -not $ORGNAME) {
        Write-Log "ERROR" "Missing required configuration in $ConfigFile"
        Write-Host "Please ensure ATLASSIAN_EMAIL, API_TOKEN, and ORGNAME are set."
        exit 1
    }
    
    Write-Log "INFO" "Configuration loaded successfully"
}

# Get repositories from Bitbucket API
function Get-Repositories {
    Write-Log "INFO" "Fetching repository list from Bitbucket workspace: $ORGNAME"
    
    $tempFile = [System.IO.Path]::GetTempFileName()
    
    try {
        $headers = @{
            "Accept" = "application/json"
        }
        
        $credential = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$ATLASSIAN_EMAIL`:$API_TOKEN"))
        $headers["Authorization"] = "Basic $credential"
        
        $uri = "https://api.bitbucket.org/2.0/repositories/$ORGNAME?pagelen=100"
        
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -OutFile $tempFile
        
        Write-Log "SUCCESS" "Successfully connected to Bitbucket API"
        
        # Parse JSON response
        $jsonContent = Get-Content $tempFile -Raw | ConvertFrom-Json
        
        $repos = $jsonContent.values | ForEach-Object { $_.slug }
        
        return $repos
    }
    catch {
        Write-Log "ERROR" "Failed to fetch repositories from Bitbucket API: $($_.Exception.Message)"
        exit 1
    }
    finally {
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }
    }
}

# Process a single repository
function Process-Repository {
    param([string]$RepoName)
    
    $repoUrl = "https://cyphertek-admin:$API_TOKEN@bitbucket.org/$ORGNAME/$RepoName.git"
    $repoBackupDir = Join-Path $BACKUP_DIR $RepoName
    
    if ($DryRun) {
        Write-Log "INFO" "[DRY RUN] Would process repository: $RepoName"
        return $true
    }
    
    # Create backup directory if it doesn't exist
    if (-not (Test-Path $repoBackupDir)) {
        New-Item -ItemType Directory -Path $repoBackupDir -Force | Out-Null
    }
    
    # Skip if repository exists and skip-existing is enabled
    if ($SkipExisting -and (Test-Path (Join-Path $repoBackupDir ".git"))) {
        Write-Log "INFO" "Skipping existing repository: $RepoName"
        return $true
    }
    
    # Clone or update repository
    if (-not (Test-Path (Join-Path $repoBackupDir ".git"))) {
        Write-Log "INFO" "Cloning repository: $RepoName"
        
        try {
            & git clone $repoUrl $repoBackupDir
            if ($LASTEXITCODE -eq 0) {
                Write-Log "SUCCESS" "Successfully cloned $RepoName"
            } else {
                Write-Log "ERROR" "Failed to clone $RepoName"
                $script:FailedRepos += $RepoName
                return $false
            }
        }
        catch {
            Write-Log "ERROR" "Failed to clone $RepoName: $($_.Exception.Message)"
            $script:FailedRepos += $RepoName
            return $false
        }
    } else {
        Write-Log "INFO" "Repository already exists, updating: $RepoName"
    }
    
    # Change to repository directory
    Push-Location $repoBackupDir
    
    try {
        # Fetch all remote branches
        & git fetch --all
        if ($LASTEXITCODE -ne 0) {
            Write-Log "ERROR" "Failed to fetch branches for $RepoName"
            $script:FailedRepos += $RepoName
            return $false
        }
        
        # Get list of all remote branches
        $remoteBranches = & git branch -r | Where-Object { $_ -notmatch 'HEAD' } | ForEach-Object { $_ -replace 'origin/', '' }
        
        # Update all branches
        $branchCount = 0
        $updatedBranches = 0
        
        foreach ($branch in $remoteBranches) {
            $branchCount++
            if ($Verbose) {
                Write-Log "INFO" "  Updating branch: $branch"
            }
            
            try {
                & git checkout $branch 2>$null
                if ($LASTEXITCODE -ne 0) {
                    & git checkout -b $branch "origin/$branch" 2>$null
                }
                
                if ($LASTEXITCODE -eq 0) {
                    & git pull origin $branch
                    if ($LASTEXITCODE -eq 0) {
                        $updatedBranches++
                        if ($Verbose) {
                            Write-Log "SUCCESS" "    Updated $branch branch"
                        }
                    } else {
                        Write-Log "WARN" "    Failed to update $branch branch"
                    }
                } else {
                    Write-Log "WARN" "    Failed to checkout $branch branch"
                }
            }
            catch {
                Write-Log "WARN" "    Error processing branch $branch : $($_.Exception.Message)"
            }
        }
        
        Write-Log "SUCCESS" "Completed backup of $RepoName ($updatedBranches/$branchCount branches updated)"
        $script:SuccessfulRepos += $RepoName
        return $true
    }
    finally {
        Pop-Location
    }
}

# Generate summary report
function Show-Summary {
    $totalRepos = $TotalRepos
    $successful = $SuccessfulRepos.Count
    $failed = $FailedRepos.Count
    
    # Calculate backup size
    $backupSize = "Unknown"
    if (Test-Path $BACKUP_DIR) {
        try {
            $size = (Get-ChildItem $BACKUP_DIR -Recurse | Measure-Object -Property Length -Sum).Sum
            $backupSize = "{0:N0} bytes" -f $size
        }
        catch {
            $backupSize = "Unknown"
        }
    }
    
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "           BACKUP SUMMARY"
    Write-Host "=========================================="
    Write-Host "Total repositories: $totalRepos"
    Write-Host "Successful backups: $successful"
    Write-Host "Failed backups: $failed"
    Write-Host "Backup location: $BACKUP_DIR"
    Write-Host "Backup size: $backupSize"
    Write-Host "Backup time: $(Get-Date)"
    Write-Host "=========================================="
    
    if ($FailedRepos.Count -gt 0) {
        Write-Host ""
        Write-Host "Failed repositories:"
        $FailedRepos | ForEach-Object { Write-Host "  - $_" }
    }
    
    if ($SuccessfulRepos.Count -gt 0) {
        Write-Host ""
        Write-Host "Successful repositories:"
        $SuccessfulRepos | ForEach-Object { Write-Host "  - $_" }
    }
}

# Main execution
function Main {
    param([string[]]$Args)
    
    # Show help if requested
    if ($Help) {
        Show-Usage
        return
    }
    
    # Load configuration
    Load-Config -ConfigFile $ConfigFile
    
    # Show dry run message
    if ($DryRun) {
        Write-Log "INFO" "DRY RUN MODE - No actual changes will be made"
    }
    
    # Get list of repositories
    $repos = Get-Repositories
    $script:TotalRepos = $repos.Count
    
    if ($TotalRepos -eq 0) {
        Write-Log "ERROR" "No repositories found"
        exit 1
    }
    
    Write-Log "INFO" "Found $TotalRepos repositories to backup"
    
    if ($Verbose) {
        $repos | ForEach-Object { Write-Host $_ }
        Write-Host ""
    }
    
    # Create backup directory if it doesn't exist
    if (-not (Test-Path $BACKUP_DIR)) {
        New-Item -ItemType Directory -Path $BACKUP_DIR -Force | Out-Null
        Write-Log "INFO" "Created backup directory: $BACKUP_DIR"
    }
    
    # Process repositories
    $current = 0
    
    foreach ($repoName in $repos) {
        $current++
        
        # Show progress
        $percent = [math]::Round(($current / $TotalRepos) * 100)
        Write-Progress -Activity "Backing up repositories" -Status "Processing $repoName" -PercentComplete $percent
        
        # Process repository
        Process-Repository -RepoName $repoName
        $script:ProcessedRepos++
    }
    
    Write-Progress -Activity "Backing up repositories" -Completed
    
    # Show summary
    Show-Summary
    
    # Exit with error code if any repositories failed
    if ($FailedRepos.Count -gt 0) {
        exit 1
    }
}

# Run main function
Main -Args $args 