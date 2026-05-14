' AI PRONOTE - silent start (no cmd window)
' Always Chrome --app self window (like a desktop app). Signup opens external web tab from inside.
Option Explicit
Dim sh, fso, basePath, pythonw, mainPy, http, i, candidates, p
Dim chrome, chromeCands, req

Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
basePath = fso.GetParentFolderName(WScript.ScriptFullName)
mainPy   = basePath & "\main.py"

' pythonw.exe absolute path (Windows Store stub bypass)
candidates = Array( _
    sh.ExpandEnvironmentStrings("%LOCALAPPDATA%\Programs\Python\Python312\pythonw.exe"), _
    sh.ExpandEnvironmentStrings("%LOCALAPPDATA%\Programs\Python\Python311\pythonw.exe"), _
    sh.ExpandEnvironmentStrings("%LOCALAPPDATA%\Programs\Python\Python310\pythonw.exe"), _
    "C:\Python312\pythonw.exe", _
    "C:\Python311\pythonw.exe", _
    "C:\Python310\pythonw.exe", _
    "pythonw.exe" _
)
pythonw = ""
For Each p In candidates
    If fso.FileExists(p) Then
        pythonw = p
        Exit For
    End If
Next
If pythonw = "" Then pythonw = "pythonw.exe"

' Chrome absolute path
chromeCands = Array( _
    "C:\Program Files\Google\Chrome\Application\chrome.exe", _
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe", _
    sh.ExpandEnvironmentStrings("%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe") _
)
chrome = ""
For Each p In chromeCands
    If fso.FileExists(p) Then
        chrome = p
        Exit For
    End If
Next

' 1. Kill any existing port 8765 server (silent)
sh.Run "cmd /c for /f ""tokens=5"" %a in ('netstat -ano ^| findstr :8765 ^| findstr LISTENING') do taskkill /PID %a /F > nul 2>&1", 0, True

' 2. pythonw.exe = main.py background (no console window)
sh.CurrentDirectory = basePath
sh.Run """" & pythonw & """ """ & mainPy & """", 0, False

' 3. Wait for server ready (HTTP polling, max 30 sec)
http = "http://localhost:8765/api/health"
For i = 1 To 30
    WScript.Sleep 1000
    On Error Resume Next
    Set req = CreateObject("MSXML2.XMLHTTP")
    req.Open "GET", http, False
    req.Send
    If Err.Number = 0 And req.Status = 200 Then
        Exit For
    End If
    On Error Goto 0
Next

' 4. Always launch as Chrome --app self window (like a desktop app)
' Signup = inside the app, "Sign up" button opens normal Chrome tab to web signup page
If chrome <> "" Then
    sh.Run """" & chrome & """ --app=http://localhost:8765 --window-size=1280,900", 1, False
Else
    ' No Chrome = default browser fallback
    sh.Run "http://localhost:8765", 1, False
End If

WScript.Quit 0
