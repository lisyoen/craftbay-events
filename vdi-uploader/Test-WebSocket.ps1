<#
.SYNOPSIS
    CraftBay WebSocket 연결 테스트
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-WebSocket.ps1
#>

$ServerUrl = "wss://upload.craftbay.io"

Write-Host @"

+------------------------------------------+
|     WebSocket Connection Test            |
+------------------------------------------+

"@ -ForegroundColor Cyan

Write-Host "Server: $ServerUrl" -ForegroundColor Gray
Write-Host "`nTesting connection..." -ForegroundColor Yellow

try {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $cts = New-Object System.Threading.CancellationTokenSource
    $cts.CancelAfter(10000)
    
    $uri = [System.Uri]::new($ServerUrl)
    $connectTask = $ws.ConnectAsync($uri, $cts.Token)
    $connectTask.Wait()
    
    if ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        Write-Host "[OK] WebSocket connected!" -ForegroundColor Green
        
        $pingMsg = '{"type":"ping"}'
        $pingBytes = [System.Text.Encoding]::UTF8.GetBytes($pingMsg)
        $segment = New-Object System.ArraySegment[byte] -ArgumentList @(,$pingBytes)
        $ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait()
        
        $buffer = New-Object byte[] 1024
        $receiveSegment = New-Object System.ArraySegment[byte] -ArgumentList @(,$buffer)
        $receiveTask = $ws.ReceiveAsync($receiveSegment, $cts.Token)
        $receiveTask.Wait()
        
        $response = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $receiveTask.Result.Count)
        Write-Host "[<<] Server response: $response" -ForegroundColor Cyan
        
        $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $cts.Token).Wait()
        
        Write-Host "`n[SUCCESS] WebSocket is available!" -ForegroundColor Green
        Write-Host "   You can upload files now." -ForegroundColor Gray
    }
    else {
        Write-Host "[FAIL] Connection state: $($ws.State)" -ForegroundColor Red
    }
}
catch {
    Write-Host "[FAIL] Connection failed!" -ForegroundColor Red
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "`n   WebSocket may be blocked in this network." -ForegroundColor Yellow
}
finally {
    if ($ws) { $ws.Dispose() }
    if ($cts) { $cts.Dispose() }
}

Read-Host "`nPress Enter to exit"
