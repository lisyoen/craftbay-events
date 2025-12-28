<#
.SYNOPSIS
    Upload files to CraftBay server via WebSocket
.DESCRIPTION
    Bypasses HTTP POST restrictions using WebSocket protocol.
    Supports multiple files and large files with chunked transfer.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Upload-ToCraftBay.ps1
    # Opens file selection dialog (multi-select enabled)
#>

param(
    [string[]]$FilePaths,
    [string]$TargetFolder = "",
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
            $sendTask = $ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token)
            $sendTask.Wait()
            
            $buffer = New-Object byte[] 1024
            $receiveSegment = New-Object System.ArraySegment[byte] -ArgumentList @(,$buffer)
            $receiveTask = $ws.ReceiveAsync($receiveSegment, $cts.Token)
            $receiveTask.Wait()
            
            $response = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $receiveTask.Result.Count)
            $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $cts.Token).Wait()
            
            return $response
        }
    }
    catch {
        return $null
    }
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

# Folder selection dialog
function Select-TargetFolder {
    Add-Type -AssemblyName System.Windows.Forms
    
    $folders = @(
        @{Name="(Root folder)"; Value=""},
        @{Name="documents"; Value="documents"},
        @{Name="images"; Value="images"},
        @{Name="data"; Value="data"},
        @{Name="backup"; Value="backup"},
        @{Name="temp"; Value="temp"},
        @{Name="polilog"; Value="polilog"}
    )
    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Select target folder"
    $form.Size = New-Object System.Drawing.Size(320, 280)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Select upload destination folder:"
    $label.Location = New-Object System.Drawing.Point(10, 10)
    $label.Size = New-Object System.Drawing.Size(280, 20)
    $form.Controls.Add($label)
    
    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.Location = New-Object System.Drawing.Point(10, 35)
    $listBox.Size = New-Object System.Drawing.Size(280, 120)
    foreach ($folder in $folders) {
        $listBox.Items.Add($folder.Name) | Out-Null
    }
    $listBox.SelectedIndex = 0
    $form.Controls.Add($listBox)
    
    $customLabel = New-Object System.Windows.Forms.Label
    $customLabel.Text = "Or enter custom folder name:"
    $customLabel.Location = New-Object System.Drawing.Point(10, 165)
    $customLabel.Size = New-Object System.Drawing.Size(280, 20)
    $form.Controls.Add($customLabel)
    
    $customTextBox = New-Object System.Windows.Forms.TextBox
    $customTextBox.Location = New-Object System.Drawing.Point(10, 185)
    $customTextBox.Size = New-Object System.Drawing.Size(280, 25)
    $form.Controls.Add($customTextBox)
    
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Location = New-Object System.Drawing.Point(120, 215)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($okButton)
    $form.AcceptButton = $okButton
    
    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        if ($customTextBox.Text.Trim() -ne "") {
            return $customTextBox.Text.Trim()
        }
        $selectedIndex = $listBox.SelectedIndex
        if ($selectedIndex -ge 0 -and $selectedIndex -lt $folders.Count) {
            return $folders[$selectedIndex].Value
        }
        return ""
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
        [string]$TargetFolder,
        [string]$ServerUrl
    )
    
    $fileName = [System.IO.Path]::GetFileName($FilePath)
    $fileSize = (Get-Item $FilePath).Length
    $fileSizeStr = Format-FileSize -Bytes $fileSize
    
    Write-Host "`n[>>] Upload starting: $fileName ($fileSizeStr)" -ForegroundColor Cyan
    
    try {
        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        $cts = New-Object System.Threading.CancellationTokenSource
        $cts.CancelAfter(1800000)  # 30 min timeout
        
        $uri = [System.Uri]::new($ServerUrl)
        Write-Host "[..] Connecting to server..." -ForegroundColor Yellow
        $connectTask = $ws.ConnectAsync($uri, $cts.Token)
        $connectTask.Wait()
        
        if ($ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
            throw "WebSocket connection failed"
        }
        
        Write-Host "[OK] Connected" -ForegroundColor Green
        
        # Send file info
        $fileInfo = @{
            type = "file-start"
            filename = $fileName
            size = $fileSize
            targetFolder = $TargetFolder
        } | ConvertTo-Json
        
        $infoBytes = [System.Text.Encoding]::UTF8.GetBytes($fileInfo)
        $segment = New-Object System.ArraySegment[byte] -ArgumentList @(,$infoBytes)
        $ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait()
        
        # Wait for server response
        $buffer = New-Object byte[] 1024
        $receiveSegment = New-Object System.ArraySegment[byte] -ArgumentList @(,$buffer)
        $receiveTask = $ws.ReceiveAsync($receiveSegment, $cts.Token)
        $receiveTask.Wait()
        $response = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $receiveTask.Result.Count)
        Write-Host "[<<] Server: $response" -ForegroundColor Gray
        
        # Send file chunks (64KB chunks)
        $chunkSize = 64KB
        $fileStream = [System.IO.File]::OpenRead($FilePath)
        $totalSent = 0
        $chunkBuffer = New-Object byte[] $chunkSize
        $startTime = Get-Date
        
        Write-Host "[..] Sending file..." -ForegroundColor Yellow
        
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
        
        # Close connection
        $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $cts.Token).Wait()
        
        Write-Host "[OK] Upload complete!" -ForegroundColor Green
        Write-Host "   File: $fileName" -ForegroundColor Gray
        Write-Host "   Size: $(Format-FileSize -Bytes $totalSent)" -ForegroundColor Gray
        Write-Host "   Time: $([math]::Round($elapsed.TotalSeconds, 1)) seconds" -ForegroundColor Gray
        Write-Host "   Speed: $(Format-FileSize -Bytes $avgSpeed)/s" -ForegroundColor Gray
        
        return $true
    }
    catch {
        Write-Host "[FAIL] Upload failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    finally {
        if ($fileStream) { $fileStream.Dispose() }
        if ($ws) { $ws.Dispose() }
        if ($cts) { $cts.Dispose() }
    }
}

# Main execution
Write-Host @"

+------------------------------------------+
|     CraftBay File Uploader v1.2          |
|     Multi-file WebSocket transfer        |
+------------------------------------------+

"@ -ForegroundColor Cyan

# Connection test
Write-Host "[..] Testing server connection..." -ForegroundColor Yellow
$testResult = Test-WebSocketConnection -Url $ServerUrl

if ($testResult) {
    Write-Host "[OK] WebSocket connection successful!" -ForegroundColor Green
}
else {
    Write-Host "[FAIL] WebSocket connection failed!" -ForegroundColor Red
    Write-Host "   Server URL: $ServerUrl" -ForegroundColor Gray
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
foreach ($f in $FilePaths) {
    $size = Format-FileSize -Bytes (Get-Item $f).Length
    Write-Host "   - $([System.IO.Path]::GetFileName($f)) ($size)" -ForegroundColor Gray
}

# Folder selection
if (-not $TargetFolder) {
    $TargetFolder = Select-TargetFolder
    if ($null -eq $TargetFolder) {
        Write-Host "`nCancelled." -ForegroundColor Yellow
        exit 0
    }
}

if ($TargetFolder) {
    Write-Host "`n[i] Target folder: $TargetFolder" -ForegroundColor Cyan
} else {
    Write-Host "`n[i] Target folder: (root)" -ForegroundColor Cyan
}

# Upload each file
$successCount = 0
$failCount = 0
$totalFiles = $FilePaths.Count

Write-Host "`n========================================" -ForegroundColor White
Write-Host "Starting upload of $totalFiles file(s)" -ForegroundColor White
Write-Host "========================================" -ForegroundColor White

for ($i = 0; $i -lt $FilePaths.Count; $i++) {
    $filePath = $FilePaths[$i]
    Write-Host "`n[$($i+1)/$totalFiles] " -NoNewline -ForegroundColor White
    
    if (-not (Test-Path $filePath)) {
        Write-Host "File not found: $filePath" -ForegroundColor Red
        $failCount++
        continue
    }
    
    $result = Send-FileViaWebSocket -FilePath $filePath -TargetFolder $TargetFolder -ServerUrl $ServerUrl
    
    if ($result) {
        $successCount++
    } else {
        $failCount++
    }
    
    # Small delay between files
    if ($i -lt $FilePaths.Count - 1) {
        Start-Sleep -Seconds 1
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor White
Write-Host "Upload Summary" -ForegroundColor White
Write-Host "========================================" -ForegroundColor White
Write-Host "   Total:   $totalFiles file(s)" -ForegroundColor Gray
Write-Host "   Success: $successCount" -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host "   Failed:  $failCount" -ForegroundColor Red
}

Read-Host "`nPress Enter to exit"
