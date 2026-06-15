# ─────────────────────────────────────────────────────────────────────────────
# AI Usage Counter — Windows setup script (PowerShell)
# Run: powershell -ExecutionPolicy Bypass -File install.ps1
# ─────────────────────────────────────────────────────────────────────────────

function Ok($msg)   { Write-Host "✔ $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "⚠  $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "✘ $msg" -ForegroundColor Red; exit 1 }
function Step($msg) { Write-Host "`n▸ $msg" -ForegroundColor White }

Write-Host "AI Usage Counter — Install Script" -ForegroundColor Cyan
Write-Host "────────────────────────────────────"

# ── 1. Rust ───────────────────────────────────────────────────────────────────
Step "Checking Rust"
$cargoPath = "$env:USERPROFILE\.cargo\bin"
$env:PATH = "$cargoPath;$env:PATH"

if (Get-Command rustc -ErrorAction SilentlyContinue) {
    Ok "Rust $(rustc --version)"
} else {
    Warn "Rust not found — installing via winget..."
    winget install --id Rustlang.Rustup -e --accept-package-agreements --accept-source-agreements
    $env:PATH = "$cargoPath;$env:PATH"
    if (Get-Command rustc -ErrorAction SilentlyContinue) {
        Ok "Rust installed: $(rustc --version)"
    } else {
        Fail "Rust install failed. Please restart PowerShell and re-run this script."
    }
}

# ── 2. Node.js ────────────────────────────────────────────────────────────────
Step "Checking Node.js"
if (Get-Command node -ErrorAction SilentlyContinue) {
    Ok "Node.js $(node --version) / npm $(npm --version)"
} else {
    Warn "Node.js not found — installing via winget..."
    winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements
    if (Get-Command node -ErrorAction SilentlyContinue) {
        Ok "Node.js installed: $(node --version)"
    } else {
        Fail "Node.js install failed. Please restart PowerShell and re-run this script."
    }
}

# ── 3. WebView2 (required by Tauri on Windows) ───────────────────────────────
Step "Checking WebView2"
$wv2Key = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
if (Test-Path $wv2Key) {
    Ok "WebView2 already installed"
} else {
    Warn "WebView2 not found — installing..."
    winget install --id Microsoft.EdgeWebView2Runtime -e --accept-package-agreements --accept-source-agreements
    Ok "WebView2 installed"
}

# ── 4. Visual Studio Build Tools (required for Rust on Windows) ──────────────
Step "Checking MSVC Build Tools"
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vsWhere) {
    Ok "Visual Studio Build Tools found"
} else {
    Warn "MSVC Build Tools not found — installing..."
    winget install --id Microsoft.VisualStudio.2022.BuildTools -e `
        --override "--quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" `
        --accept-package-agreements --accept-source-agreements
    Ok "Build Tools installed (restart may be required)"
}

# ── 5. npm install ────────────────────────────────────────────────────────────
Step "Installing npm dependencies"
Set-Location $PSScriptRoot
npm install
Ok "npm packages installed"

# ── 6. Tauri icons ───────────────────────────────────────────────────────────
Step "Generating app icons"
$iconPath = "..\icon.png"
if (Test-Path $iconPath) {
    npm run tauri icon $iconPath
    Ok "Icons generated from $iconPath"
} else {
    Warn "icon.png not found at project root — skipping"
    Warn "Run manually: npm run tauri icon <path-to-icon.png>"
}

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host "────────────────────────────────────"
Write-Host "  Dev mode : npm run tauri dev"
Write-Host "  Build    : npm run tauri build"
Write-Host ""
Write-Host "  Built app → src-tauri\target\release\bundle\msi\"
