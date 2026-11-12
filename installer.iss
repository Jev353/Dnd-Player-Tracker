; Inno Setup script for D&D Player Tracker.
; Normally compiled via build_release.ps1, which passes /DMyAppVersion=<pubspec version>.
; To compile by hand, open this file in Inno Setup and press Compile.

#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

#define MyAppName "D&D Player Tracker"
#define MyAppExeName "dnd_tracker.exe"
#define MyBuildDir "build\windows\x64\runner\Release"

[Setup]
; IMPORTANT: never change this AppId. It is how Windows recognises an upgrade
; of the same app instead of a second install.
AppId={{B7E2C1A4-5D3F-4E8A-9C61-2F4A7D9E1B35}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=DnD Tracker
DefaultDirName={autopf}\DnDPlayerTracker
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=installer_output
OutputBaseFilename=DnDTracker_Setup_{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
; Per-user install if the user declines admin rights; no admin prompt needed.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
; The whole Release folder: exe, flutter_windows.dll, plugin DLLs and data\.
Source: "{#MyBuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

; Note: character files live in <Documents>\DnDPlayerTracker\characters\ and are
; deliberately NOT listed here, so installing, upgrading or uninstalling never
; touches them.
