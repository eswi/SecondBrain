# add-2-inbox.ps1
Add-Type -AssemblyName Microsoft.VisualBasic
$inbox = "C:\Users\me\iCloudDrive\SecondBrain\inbox.md"
$clip = Get-Clipboard -Raw
$clip = ($clip -replace "\s*\r?\n\s*", " ").Trim()   # 여러 줄 → 한 줄로

while ($true) {
    $why = [Microsoft.VisualBasic.Interaction]::InputBox(
             "왜 잡았나? (이걸로 뭘)`n빈칸으로 확인하거나 취소하면 종료`n`n클립보드:`n$clip",
             "받은함에 추가", "")
    if ([string]::IsNullOrEmpty($why)) { break }
    $date = Get-Date -Format "yyyy-MM-dd HH:mm"
    $line = "- $date | web | $clip — 왜: $why"
    Add-Content -Path $inbox -Value $line -Encoding UTF8
}