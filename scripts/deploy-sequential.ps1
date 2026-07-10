﻿# deploy-sequential.ps1
#
# Runs each manifest in manifest/sequential/ in order: retrieve from source,
# check if anything actually changed (via git), and only deploy to target if
# real changes were found. Stops immediately if any deploy fails, so you
# always know exactly which layer broke.
#
# Requires: this folder must be a git repo (git init already run), since
# change detection relies on comparing against the last commit.
#
# Usage:
#   .\scripts\deploy-sequential.ps1 -SourceOrg source-org1 -TargetOrg target-org1
#   .\scripts\deploy-sequential.ps1 -SourceOrg source-org1 -TargetOrg target-org1 -TestLevel RunLocalTests
#   .\scripts\deploy-sequential.ps1 -SourceOrg source-org1 -TargetOrg target-org1 -ContinueOnError

param(
    [Parameter(Mandatory = $true)][string]$SourceOrg,
    [Parameter(Mandatory = $true)][string]$TargetOrg,
    [string]$TestLevel = "NoTestRun",
    [switch]$ContinueOnError
)

$stages = Get-ChildItem -Path "manifest\sequential" -Filter "*.xml" | Sort-Object Name
$failedStages = @()
$skippedStages = @()
$deployedStages = @()

foreach ($stage in $stages) {
    $stageName = $stage.BaseName
    Write-Host ""
    Write-Host "=================================================="
    Write-Host " STAGE: $stageName"
    Write-Host "=================================================="

    Write-Host "--> Retrieving from $SourceOrg using $($stage.Name)..."
    sf project retrieve start --manifest $stage.FullName --target-org $SourceOrg
    if ($LASTEXITCODE -ne 0) {
        Write-Host "RETRIEVE FAILED for stage $stageName" -ForegroundColor Red
        $failedStages += $stageName
        if (-not $ContinueOnError) { break }
        else { continue }
    }

    # --- Change detection: did this retrieve actually change anything? ---
    git add -A
    git diff --cached --quiet
    $hasChanges = ($LASTEXITCODE -ne 0)

    if (-not $hasChanges) {
        Write-Host "No changes detected for stage $stageName - skipping deploy." -ForegroundColor Yellow
        $skippedStages += $stageName
        continue
    }

    Write-Host "Changes detected for stage $stageName. Committing snapshot before deploy..."
    git commit -m "Pull ($stageName): $(Get-Date -Format 'yyyy-MM-dd HH:mm')" | Out-Null

    Write-Host "--> Deploying to $TargetOrg using $($stage.Name)..."
    sf project deploy start --manifest $stage.FullName --target-org $TargetOrg --test-level $TestLevel --ignore-warnings
    if ($LASTEXITCODE -ne 0) {
        Write-Host "DEPLOY FAILED for stage $stageName" -ForegroundColor Red
        $failedStages += $stageName
        if (-not $ContinueOnError) { break }
    } else {
        Write-Host "Stage $stageName deployed successfully." -ForegroundColor Green
        $deployedStages += $stageName
    }
}

Write-Host ""
Write-Host "=================================================="
Write-Host " SUMMARY"
Write-Host "=================================================="
Write-Host " Deployed (had changes): $($deployedStages -join ', ')" -ForegroundColor Green
Write-Host " Skipped (no changes):   $($skippedStages -join ', ')" -ForegroundColor Yellow
if ($failedStages.Count -gt 0) {
    Write-Host " Failed:                 $($failedStages -join ', ')" -ForegroundColor Red
    Write-Host " Fix the errors above before re-running." -ForegroundColor Red
}
Write-Host "=================================================="
