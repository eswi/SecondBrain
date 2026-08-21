# ⛔⛔ 웹 v0 세대 — **지금은 쓰지 않는다** (2026-08-21 표시)
#    수집은 네이티브 v1(`native/`)로 넘어갔다. 이 파일은 그 이전 세대의 Windows 입구다.
#    ⚠️ 다만 위 ⛔들과 성질이 다르다 — 이것은 **원문 한 줄을 덧붙일 뿐**이고
#    분류 필드(type·due·…)를 쓰지 않는다. 즉 08-18/08-21 결정을 되돌리지 않는다.
#    경로가 `C:\Users\me\...`로 박혀 있어 맥에서는 애초에 돌지 않는다.
#    지우지 말 것 — 표시만 해 둔다. 근거: CLAUDE.md 항시 규칙 8
#
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