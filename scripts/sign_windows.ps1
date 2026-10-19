param([Parameter(Mandatory=$true)][string]$App, [Parameter(Mandatory=$true)][string]$Cli)
$ErrorActionPreference = 'Stop'
if (-not $env:WINDOWS_SIGN_PFX_BASE64 -or -not $env:WINDOWS_SIGN_PASSWORD) {
    throw 'Configure both Windows certificate secrets before signing.'
}
$certificatePath = Join-Path $env:RUNNER_TEMP 'crisper-windows-signing.pfx'
$tool = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe' | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $tool) { throw 'Windows SDK signtool.exe is required.' }
try {
    [IO.File]::WriteAllBytes($certificatePath, [Convert]::FromBase64String($env:WINDOWS_SIGN_PFX_BASE64))
    foreach ($root in @($App, $Cli)) {
        foreach ($file in Get-ChildItem $root -Recurse -File | Where-Object { $_.Extension -in @('.exe', '.dll') }) {
            & $tool.FullName sign /fd SHA256 /td SHA256 /tr 'http://timestamp.digicert.com' /f $certificatePath /p $env:WINDOWS_SIGN_PASSWORD $file.FullName
            if ($LASTEXITCODE -ne 0) { throw "Signing failed: $($file.Name)" }
            & $tool.FullName verify /pa $file.FullName
            if ($LASTEXITCODE -ne 0) { throw "Signature verification failed: $($file.Name)" }
        }
    }
} finally { Remove-Item $certificatePath -Force -ErrorAction SilentlyContinue }
