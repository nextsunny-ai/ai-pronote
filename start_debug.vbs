' 디버그용 = 메시지 박스로 단계별 표시
Option Explicit
Dim sh, fso, basePath, pythonw, mainPy, p, candidates, found

Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
basePath = fso.GetParentFolderName(WScript.ScriptFullName)
mainPy   = basePath & "\main.py"

candidates = Array( _
    sh.ExpandEnvironmentStrings("%LOCALAPPDATA%\Programs\Python\Python312\pythonw.exe"), _
    sh.ExpandEnvironmentStrings("%LOCALAPPDATA%\Programs\Python\Python311\pythonw.exe"), _
    "pythonw.exe" _
)
pythonw = ""
For Each p In candidates
    If fso.FileExists(p) Then
        pythonw = p
        Exit For
    End If
Next

WScript.Echo "basePath: " & basePath
WScript.Echo "mainPy: " & mainPy & " · exists: " & fso.FileExists(mainPy)
WScript.Echo "pythonw: " & pythonw

Dim cmd
cmd = """" & pythonw & """ """ & mainPy & """"
WScript.Echo "Run command: " & cmd
sh.CurrentDirectory = basePath
Dim rc
rc = sh.Run(cmd, 0, False)
WScript.Echo "Run rc: " & rc
