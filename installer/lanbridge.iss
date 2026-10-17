#define MyAppName "LanBridge"
#define MyAppVersion "0.1.0"
#define MyAppExeName "lanbridge.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{B3F2C1A4-6D7E-4F89-9A12-5C3E8D7B1F20}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=LanBridge
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=LanBridge-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Allow LAN discovery (UDP 38941) and file receiving (TCP 38942) through Windows Firewall
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""LanBridge TCP"" dir=in action=allow protocol=TCP localport=38942 profile=private"; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""LanBridge UDP"" dir=in action=allow protocol=UDP localport=38941 profile=private"; Flags: runhidden
Filename: "{app}\{#MyAppExeName}"; Description: "Launch LanBridge"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""LanBridge TCP"""; Flags: runhidden; RunOnceId: "DelFwTcp"
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""LanBridge UDP"""; Flags: runhidden; RunOnceId: "DelFwUdp"
