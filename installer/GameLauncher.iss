; Script de Instalador para Inno Setup 6+
; Instala GameLauncher Neon sin requerir permisos de administrador

#define MyAppName "GameLauncher Neon"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "GameLauncher Neon"
#define MyAppExeName "GameLauncher.exe"

[Setup]
AppId={{8D4E9C21-5F3A-4E19-9B12-7C8A901F2E3D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\GameLauncherNeon
DefaultGroupName={#MyAppName}
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\dist\Installer
OutputBaseFilename=GameLauncherNeon_Setup_x64
SetupIconFile=..\Assets\app.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\GameLauncher.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Assets\*"; DestDir: "{app}\Assets"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\Assets\app.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\Assets\app.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    DataDir := ExpandConstant('{localappdata}\GameLauncherNeon');
    if DirExists(DataDir) then
    begin
      if MsgBox('¿Deseas eliminar también tu biblioteca guardada y la configuración de usuario?' + #13#10 + #13#10 +
                '• Sí: Elimina la carpeta de datos (' + DataDir + ').' + #13#10 +
                '• No: Conserva tu lista de juegos para futuras instalaciones.' + #13#10 + #13#10 +
                '(Nota: Los juegos instalados en tu PC nunca se borran ni se modifican).',
                mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      begin
        DelTree(DataDir, True, True, True);
      end;
    end;
  end;
end;
