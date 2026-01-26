<#
.SYNOPSIS
    Upload files to CraftBay server via HTTP
.DESCRIPTION
    HTTP multipart/form-data upload (WebSocket replaced for compatibility)
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Upload-ToCraftBay.ps1
#>

param(
    [string[]]$FilePaths,
    [string]$ServerUrl = "https://upload.craftbay.io"
)

# Client version
$CLIENT_VERSION = "3.0.0"
$DOWNLOAD_PAGE = "https://events.craftbay.io/vdi-uploader/"

# Check client version against server minimum
function Test-ClientVersion {
    param([string]$ServerUrl)

    try {
        $versionUrl = "$ServerUrl/api/version"
        $response = Invoke-RestMethod -Uri $versionUrl -TimeoutSec 10

        if ($response.minClientVersion) {
            $minVersion = [Version]$response.minClientVersion
            $currentVersion = [Version]$CLIENT_VERSION

            if ($currentVersion -lt $minVersion) {
                Write-Host "[!] Client update required" -ForegroundColor Red
                Write-Host "    Current: $CLIENT_VERSION / Minimum: $($response.minClientVersion)" -ForegroundColor Yellow
                Write-Host "    Download: $DOWNLOAD_PAGE" -ForegroundColor Cyan
                Start-Process $DOWNLOAD_PAGE
                return $false
            }
        }
        return $true
    }
    catch {
        Write-Host "[!] Version check failed (continuing...)" -ForegroundColor Yellow
        return $true
    }
}

# Test HTTP connection
function Test-HttpConnection {
    param([string]$Url)
    
    try {
        $versionUrl = "$Url/api/version"
        $response = Invoke-RestMethod -Uri $versionUrl -TimeoutSec 10
        return $response
    }
    catch {
        return $null
    }
}

# File selection dialog (multi-select)
function Select-FilesToUpload {
    Add-Type -AssemblyName System.Windows.Forms
    
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select files to upload (Ctrl+Click for multiple)"
    $dialog.Filter = "All Files (*.*)|*.*"
    $dialog.Multiselect = $true
    
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileNames
    }
    return $null
}

# Format file size
function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -lt 1KB) { return "$Bytes B" }
    if ($Bytes -lt 1MB) { return "$([math]::Round($Bytes/1KB, 1)) KB" }
    if ($Bytes -lt 1GB) { return "$([math]::Round($Bytes/1MB, 1)) MB" }
    return "$([math]::Round($Bytes/1GB, 2)) GB"
}

# Upload single file via HTTP multipart/form-data
function Send-FileViaHttp {
    param(
        [string]$FilePath,
        [string]$ServerUrl
    )
    
    $fileName = [System.IO.Path]::GetFileName($FilePath)
    $fileSize = (Get-Item $FilePath).Length
    $fileSizeStr = Format-FileSize -Bytes $fileSize
    
    Write-Host "`n[>>] Upload: $fileName ($fileSizeStr)" -ForegroundColor Cyan
    
    try {
        $uploadUrl = "$ServerUrl/api/upload"
        $startTime = Get-Date
        
        Write-Host "[..] Uploading..." -ForegroundColor Yellow
        
        # Create multipart form data
        Add-Type -AssemblyName System.Net.Http
        
        $httpClient = New-Object System.Net.Http.HttpClient
        $httpClient.Timeout = [TimeSpan]::FromMinutes(30)
        
        $form = New-Object System.Net.Http.MultipartFormDataContent
        
        # Add file
        $fileStream = [System.IO.File]::OpenRead($FilePath)
        $fileContent = New-Object System.Net.Http.StreamContent($fileStream)
        $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")
        $form.Add($fileContent, "file", $fileName)
        
        # Add project field (optional)
        $projectContent = New-Object System.Net.Http.StringContent("vdi")
        $form.Add($projectContent, "project")
        
        # Send request
        $response = $httpClient.PostAsync($uploadUrl, $form).Result
        $responseBody = $response.Content.ReadAsStringAsync().Result
        
        $fileStream.Close()
        $fileStream.Dispose()
        $httpClient.Dispose()
        
        $elapsed = (Get-Date) - $startTime
        
        if ($response.IsSuccessStatusCode) {
            $result = $responseBody | ConvertFrom-Json
            $avgSpeed = if ($elapsed.TotalSeconds -gt 0) { $fileSize / $elapsed.TotalSeconds } else { 0 }
            
            Write-Host "[OK] Complete! $fileSizeStr in $([math]::Round($elapsed.TotalSeconds, 1))s ($(Format-FileSize -Bytes $avgSpeed)/s)" -ForegroundColor Green
            Write-Host "     Download: $ServerUrl$($result.downloadUrl)" -ForegroundColor Gray
            return $true
        }
        else {
            Write-Host "[FAIL] Server error: $($response.StatusCode)" -ForegroundColor Red
            Write-Host "       $responseBody" -ForegroundColor Gray
            return $false
        }
    }
    catch {
        Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Main
Write-Host @"

+------------------------------------------+
|     CraftBay File Uploader v3.0          |
|     HTTP multipart upload                |
+------------------------------------------+

"@ -ForegroundColor Cyan

# Connection test
Write-Host "[..] Testing connection..." -ForegroundColor Yellow
$testResult = Test-HttpConnection -Url $ServerUrl

if ($testResult) {
    Write-Host "[OK] Server connected! (v$($testResult.version))" -ForegroundColor Green
}
else {
    Write-Host "[FAIL] Cannot connect to server" -ForegroundColor Red
    Write-Host "   URL: $ServerUrl" -ForegroundColor Gray
    Read-Host "`nPress Enter to exit"
    exit 1
}

# Version check
if (-not (Test-ClientVersion -ServerUrl $ServerUrl)) {
    Read-Host "Press Enter to exit"
    exit 1
}

# File selection
if (-not $FilePaths -or $FilePaths.Count -eq 0) {
    $FilePaths = Select-FilesToUpload
    if (-not $FilePaths -or $FilePaths.Count -eq 0) {
        Write-Host "`nCancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Show selected files
Write-Host "`n[i] Selected $($FilePaths.Count) file(s):" -ForegroundColor Cyan
$totalSize = 0
foreach ($f in $FilePaths) {
    $size = (Get-Item $f).Length
    $totalSize += $size
    Write-Host "   - $([System.IO.Path]::GetFileName($f)) ($(Format-FileSize -Bytes $size))" -ForegroundColor Gray
}
Write-Host "   Total: $(Format-FileSize -Bytes $totalSize)" -ForegroundColor White

# Upload
$successCount = 0
$failCount = 0
$totalFiles = $FilePaths.Count

Write-Host "`n========================================" -ForegroundColor White
Write-Host "Starting upload ($totalFiles files)" -ForegroundColor White
Write-Host "========================================" -ForegroundColor White

for ($i = 0; $i -lt $FilePaths.Count; $i++) {
    $filePath = $FilePaths[$i]
    Write-Host "`n[$($i+1)/$totalFiles]" -NoNewline -ForegroundColor White
    
    if (-not (Test-Path $filePath)) {
        Write-Host " File not found: $filePath" -ForegroundColor Red
        $failCount++
        continue
    }
    
    if (Send-FileViaHttp -FilePath $filePath -ServerUrl $ServerUrl) {
        $successCount++
    } else {
        $failCount++
    }
    
    if ($i -lt $FilePaths.Count - 1) { Start-Sleep -Milliseconds 500 }
}

# Summary
Write-Host "`n========================================" -ForegroundColor White
Write-Host "Summary: $successCount success" -NoNewline -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host ", $failCount failed" -ForegroundColor Red
} else {
    Write-Host ""
}
Write-Host "========================================" -ForegroundColor White
Write-Host "`nDownload files at: $ServerUrl" -ForegroundColor Cyan

Read-Host "`nPress Enter to exit"
