$ErrorActionPreference = 'Stop'

$baseUrl = 'http://localhost:1880'
$newFlowPath = 'D:\NodeRed\flows\mqtt-telemetry-simulator.json'

$current = Invoke-RestMethod -Method Get -Uri "$baseUrl/flows"
$newNodes = Get-Content -Raw -Path $newFlowPath | ConvertFrom-Json

$tabId = 'b1f0f2e1a0c34d01'
$existing = @($current)
$withoutSimulator = $existing | Where-Object { $_.id -ne $tabId -and $_.z -ne $tabId }
$merged = @($withoutSimulator + $newNodes)

$body = $merged | ConvertTo-Json -Depth 100
Invoke-RestMethod -Method Post -Uri "$baseUrl/flows" -ContentType 'application/json' -Body $body | Out-Null
Write-Output 'Imported MQTT Telemetry Simulator flow successfully.'
