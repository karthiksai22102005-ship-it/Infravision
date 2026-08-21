$targetPath = "C:\Users\Dell\OneDrive\Desktop\Final Year project\infravision\build\windows\x64\runner\Release\infravision.exe"
$workingDir = "C:\Users\Dell\OneDrive\Desktop\Final Year project\infravision\build\windows\x64\runner\Release"
$iconPath = "C:\Users\Dell\OneDrive\Desktop\Final Year project\infravision\windows\runner\resources\app_icon.ico"

$wshShell = New-Object -ComObject WScript.Shell

$destinations = @(
    [Environment]::GetFolderPath('Desktop'),
    "C:\Users\Dell\OneDrive\Desktop",
    "C:\Users\Dell\Desktop"
) | Select-Object -Unique

foreach ($dir in $destinations) {
    if (Test-Path $dir) {
        $shortcutPath = Join-Path $dir "InfraVision.lnk"
        $shortcut = $wshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $targetPath
        $shortcut.WorkingDirectory = $workingDir
        if (Test-Path $iconPath) {
            $shortcut.IconLocation = "$iconPath,0"
        } else {
            $shortcut.IconLocation = "$targetPath,0"
        }
        $shortcut.Description = "InfraVision - AI Infrastructure Defect Inspection Workstation"
        $shortcut.Save()
        Write-Host "Created Desktop Shortcut: $shortcutPath"
    }
}
