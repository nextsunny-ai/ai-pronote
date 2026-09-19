#ifndef AppName
#define AppName "AI PRONOTE"
#endif
#define AppVersion "1.0.1"
#define AppPublisher "㈜써니엔터테인먼트"
#define AppExeName "ai_pronote_app.exe"
#ifndef AppIdValue
#define AppIdValue "17D39F9A-B85A-420C-B5EB-60541A663B31"
#endif
#ifndef ShortcutName
#define ShortcutName "AI PRONOTE"
#endif
#ifndef InstallerFilename
#define InstallerFilename "AI_PRONOTE_1.0.1_windows_x64_setup"
#endif

[Setup]
AppId={{{#AppIdValue}}
AppName={#AppName}
AppVersion=1.0.1
AppVerName={#AppName} {#AppVersion}
AppPublisher=㈜써니엔터테인먼트
AppPublisherURL=https://nextsunny-ai.github.io/ai-pronote/
AppSupportURL=https://nextsunny-ai.github.io/ai-pronote/#guide
AppUpdatesURL=https://nextsunny-ai.github.io/ai-pronote/#download
DefaultDirName={localappdata}\Programs\AI PRONOTE
DefaultGroupName={#ShortcutName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir=..\build\installer
OutputBaseFilename={#InstallerFilename}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
AppMutex=AI_PRONOTE_17D39F9A_B85A_420C_B5EB_60541A663B31
VersionInfoVersion=1.0.1.2
VersionInfoCompany={#AppPublisher}
VersionInfoDescription=AI PRONOTE Windows Installer
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "바탕화면에 AI PRONOTE 아이콘 만들기"; GroupDescription: "바로가기:"; Flags: checkedonce

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#ShortcutName}"; Filename: "{app}\ai_pronote_app.exe"; WorkingDir: "{app}"; IconFilename: "{app}\ai_pronote_app.exe"
Name: "{autodesktop}\{#ShortcutName}"; Filename: "{app}\ai_pronote_app.exe"; WorkingDir: "{app}"; IconFilename: "{app}\ai_pronote_app.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\ai_pronote_app.exe"; Description: "AI PRONOTE 실행"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
