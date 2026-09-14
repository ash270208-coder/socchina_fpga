# ============================================================
# One-click push to GitHub: https://github.com/ash270208-coder/socchina_fpga
# Usage: right-click this file -> "Run with PowerShell"
# First push opens a GitHub login window (Git Credential Manager)
# ============================================================
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host "== remote =="
git remote -v

Write-Host "== fetch =="
git fetch origin 2>&1 | Out-String

# If remote already has main/master (e.g. README created with repo), merge first
$remoteBranch = git ls-remote --heads origin 2>$null |
    Select-String -Pattern 'refs/heads/(main|master)$' |
    ForEach-Object { $_.Matches[0].Groups[1].Value } |
    Select-Object -First 1

if ($remoteBranch) {
    Write-Host "remote has branch: $remoteBranch, merging..."
    git merge "origin/$remoteBranch" --allow-unrelated-histories -m "merge remote $remoteBranch" 2>&1 | Out-String
}

Write-Host "== push =="
git push -u origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "PUSH OK -> https://github.com/ash270208-coder/socchina_fpga"
} else {
    Write-Host ""
    Write-Host "PUSH FAILED - send the error above to your assistant"
}
Read-Host "Press Enter to exit"
