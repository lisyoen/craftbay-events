<#
.SYNOPSIS
    Upload files to CraftBay server via WebSocket
.DESCRIPTION
    Bypasses HTTP POST restrictions using WebSocket protocol.
    Files are stored with UUID names, original names preserved in DB.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Upload-ToCraftBay.ps1
#>

param(
    [string[]]$FilePaths,
    [string]$ServerUrl = "wss://upload.craftbay.io"
)

# Test WebSocket connection
function Test-WebSocketConnection {
    param([string]$Url)
    
    try {
        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        $cts = New-Object System.Threading.CancellationTokenSource
        $cts.CancelAfter(10000)
        
        $uri = [System.Uri]::new($Url)
        $connectTask = $ws.ConnectAsync($uri, $cts.Token)
        $connectTask.Wait()
        
        if ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $pingMsg = '{"type":"ping"}'
            $pingBytes = [System.Text.Encoding]::UTF8.GetBytes($pingMsg)
            $segment = New-Object System.ArraySegment[byte] -ArgumentList @(,$pingBytes)
            $ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait()
            
            $buffer = New-Object byte[] 1024
            $receiveSegment = New-Object System.ArraySegment[byte] -ArgumentList @(,$buffer)
            $receiveTask = $ws.ReceiveAsync($receiveSegment, $cts.Token)
            $receiveTask.Wait()
            
            $response = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $receiveTask.Result.Count)
            $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $cts.Token).Wait()
            
            return $response
        }
    }
    catch { return $null }
    finally {
        if ($ws) { $ws.Dispose() }
        if ($cts) { $cts.Dispose() }
    }
    return $null
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

# Upload single file via WebSocket
function Send-FileViaWebSocket {
    param(
        [string]$FilePath,
        [string]$ServerUrl
    )
    
    $fileName = [System.IO.Path]::GetFileName($FilePath)
    $fileSize = (Get-Item $FilePath).Length
    $fileSizeStr = Format-FileSize -Bytes $fileSize
    
    Write-Host "`n[>>] Upload: $fileName ($fileSizeStr)" -ForegroundColor Cyan
    
    try {
        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        $cts = New-Object System.Threading.CancellationTokenSource
        $cts.CancelAfter(1800000)  # 30 min
        
        $uri = [System.Uri]::new($ServerUrl)
        Write-Host "[..] Connecting..." -ForegroundColor Yellow
        $ws.ConnectAsync($uri, $cts.Token).Wait()
        
        if ($ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
            throw "Connection failed"
        }
        
        Write-Host "[OK] Connected" -ForegroundColor Green
        
        # Send file info (no targetFolder - server handles it)
        $fileInfo = @{
            type = "file-start"
            filename = $fileName
            size = $fileSize
            targetFolder = ""
        } | ConvertTo-Json
        
        $infoBytes = [System.Text.Encoding]::UTF8.GetBytes($fileInfo)
        $segment = New-Object System.ArraySegment[byte] -ArgumentList @(,$infoBytes)
        $ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait()
        
        # Wait for ready
        $buffer = New-Object byte[] 1024
        $receiveSegment = New-Object System.ArraySegment[byte] -ArgumentList @(,$buffer)
        $receiveTask = $ws.ReceiveAsync($receiveSegment, $cts.Token)
        $receiveTask.Wait()
        
        # Send chunks
        $chunkSize = 64KB
        $fileStream = [System.IO.File]::OpenRead($FilePath)
        $totalSent = 0
        $chunkBuffer = New-Object byte[] $chunkSize
        $startTime = Get-Date
        
        Write-Host "[..] Sending..." -ForegroundColor Yellow
        
        while ($true) {
            $bytesRead = $fileStream.Read($chunkBuffer, 0, $chunkSize)
            if ($bytesRead -eq 0) { break }
            
            $dataToSend = $chunkBuffer[0..($bytesRead-1)]
            $dataSegment = New-Object System.ArraySegment[byte] -ArgumentList @(,$dataToSend)
            $ws.SendAsync($dataSegment, [System.Net.WebSockets.WebSocketMessageType]::Binary, $true, $cts.Token).Wait()
            
            $totalSent += $bytesRead
            $progress = [math]::Round(($totalSent / $fileSize) * 100)
            $elapsed = (Get-Date) - $startTime
            $speed = if ($elapsed.TotalSeconds -gt 0) { $totalSent / $elapsed.TotalSeconds } else { 0 }
            $speedStr = Format-FileSize -Bytes $speed
            
            Write-Progress -Activity "Uploading $fileName" -Status "$progress% - $speedStr/s" -PercentComplete $progress
        }
        
        $fileStream.Close()
        Write-Progress -Activity "Uploading" -Completed
        
        $elapsed = (Get-Date) - $startTime
        $avgSpeed = if ($elapsed.TotalSeconds -gt 0) { $totalSent / $elapsed.TotalSeconds } else { 0 }
        
        $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $cts.Token).Wait()
        
        Write-Host "[OK] Complete! $(Format-FileSize -Bytes $totalSent) in $([math]::Round($elapsed.TotalSeconds, 1))s ($(Format-FileSize -Bytes $avgSpeed)/s)" -ForegroundColor Green
        
        return $true
    }
    catch {
        Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    finally {
        if ($fileStream) { $fileStream.Dispose() }
        if ($ws) { $ws.Dispose() }
        if ($cts) { $cts.Dispose() }
    }
}

# Main
Write-Host @"

+------------------------------------------+
|     CraftBay File Uploader v2.0          |
|     UUID-based file storage              |
+------------------------------------------+

"@ -ForegroundColor Cyan

# Connection test
Write-Host "[..] Testing connection..." -ForegroundColor Yellow
$testResult = Test-WebSocketConnection -Url $ServerUrl

if ($testResult) {
    Write-Host "[OK] Server connected!" -ForegroundColor Green
}
else {
    Write-Host "[FAIL] Cannot connect to server" -ForegroundColor Red
    Write-Host "   URL: $ServerUrl" -ForegroundColor Gray
    Read-Host "`nPress Enter to exit"
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
    
    if (Send-FileViaWebSocket -FilePath $filePath -ServerUrl $ServerUrl) {
        $successCount++
    } else {
        $failCount++
    }
    
    if ($i -lt $FilePaths.Count - 1) { Start-Sleep -Seconds 1 }
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
Write-Host "`nDownload files at: https://events.craftbay.io/vdi-uploader/" -ForegroundColor Cyan

Read-Host "`nPress Enter to exit"
