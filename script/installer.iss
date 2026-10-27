; The Windows installer: one Setup program carrying both the x64 and the arm64 build, installing the one that
; matches the PC into the user's own folder (no administrator prompt).
;
; Build it from the repository root with Inno Setup 6, after both script\package_windows.cmd zips have been
; extracted under dist\ (dist\OpenUsageLight-windows-x64 and dist\OpenUsageLight-windows-arm64):
;   iscc /DAppVersion=0.1.0 script\installer.iss
; The result is dist\OpenUsageLight-Setup.exe.

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

[Setup]
AppId={{FEFDB71B-43BE-4DC7-AE21-F6E2A1CF7772}
AppName=OpenUsage Light
AppVersion={#AppVersion}
AppPublisher=OpenUsage Light
DefaultDirName={autopf}\OpenUsage Light
DefaultGroupName=OpenUsage Light
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible or arm64
ArchitecturesInstallIn64BitMode=x64compatible or arm64
OutputDir=..\dist
OutputBaseFilename=OpenUsageLight-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\OpenUsageLight.exe
ChangesEnvironment=yes
; The tray app has no window to ask to close, so Setup ends it itself (see StopRunningApp).
CloseApplications=no

[Tasks]
Name: "startup"; Description: "Start OpenUsage Light when I sign in to Windows"; Flags: unchecked
Name: "addtopath"; Description: "Add the openusage command to my PATH"; Flags: unchecked

[Files]
Source: "..\dist\OpenUsageLight-windows-arm64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs; Check: IsArm64
Source: "..\dist\OpenUsageLight-windows-x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs; Check: not IsArm64

[Icons]
Name: "{autoprograms}\OpenUsage Light"; Filename: "{app}\OpenUsageLight.exe"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "OpenUsageLight"; ValueData: """{app}\OpenUsageLight.exe"""; Flags: uninsdeletevalue; Tasks: startup
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; Check: NeedsAddPath(ExpandConstant('{app}')); Tasks: addtopath

[Run]
Filename: "{app}\OpenUsageLight.exe"; Description: "Start OpenUsage Light now"; Flags: nowait postinstall skipifsilent

[Code]
// The user's accounts and credentials live in %APPDATA%\OpenUsage Light and are never touched by Setup,
// an upgrade, or an uninstall.

procedure StopRunningApp;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM OpenUsageLight.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopRunningApp;
  Result := '';
end;

function InitializeUninstall: Boolean;
begin
  StopRunningApp;
  Result := True;
end;

function NeedsAddPath(Param: String): Boolean;
var
  Paths: String;
begin
  if not RegQueryStringValue(HKCU, 'Environment', 'Path', Paths) then
    Paths := '';
  Result := Pos(';' + Uppercase(Param) + ';', ';' + Uppercase(Paths) + ';') = 0;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Paths, Entry: String;
  P: Integer;
begin
  if CurUninstallStep <> usPostUninstall then Exit;
  if not RegQueryStringValue(HKCU, 'Environment', 'Path', Paths) then Exit;
  Entry := ExpandConstant('{app}');
  P := Pos(';' + Uppercase(Entry) + ';', ';' + Uppercase(Paths) + ';');
  if P = 0 then Exit;
  // Drop the entry and the separator that joined it.
  Delete(Paths, P, Length(Entry) + 1);
  if (Length(Paths) > 0) and (Paths[Length(Paths)] = ';') then Delete(Paths, Length(Paths), 1);
  RegWriteExpandStringValue(HKCU, 'Environment', 'Path', Paths);
end;
