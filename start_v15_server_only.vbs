Option Explicit
Dim shell, scriptDir, command
Set shell = CreateObject("WScript.Shell")
scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & scriptDir & "\start_v15_server_only.ps1" & Chr(34)
shell.Run command, 0, False
