; 1.0.0-beta.27: instalador da versão Windows (Inno Setup 6), por usuário — não pede administrador.
; Compilado por windows/build/publish.ps1:  ISCC /DAppVersion=x.y.z /DPublishDir=... /DOutputDir=... IMPCriativos.iss
; Os dados (lotes, clientes, chaves) ficam em %LOCALAPPDATA%\IMP Criativos e NÃO são apagados ao desinstalar.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef PublishDir
  #define PublishDir "..\artifacts\publish"
#endif
#ifndef OutputDir
  #define OutputDir "..\artifacts\dist"
#endif

[Setup]
AppId={{6E1B3C52-8F4A-4D7B-9C21-1A5F0E3D7B94}
AppName=IMP Criativos
AppVersion={#AppVersion}
AppVerName=IMP Criativos {#AppVersion}
AppPublisher=Impera Services
AppPublisherURL=https://github.com/marcelolucas11/imp-criativos
AppSupportURL=https://github.com/marcelolucas11/imp-criativos
AppUpdatesURL=https://github.com/marcelolucas11/imp-criativos/releases
DefaultDirName={localappdata}\Programs\IMP Criativos
DefaultGroupName=IMP Criativos
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
OutputDir={#OutputDir}
OutputBaseFilename=IMP-Criativos-Setup-{#AppVersion}-windows-x64
SetupIconFile=..\src\IMPCriativos.App\Resources\AppIcon.ico
UninstallDisplayIcon={app}\IMP Criativos.exe
UninstallDisplayName=IMP Criativos
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=force
RestartApplications=no
ShowLanguageDialog=no

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na Área de Trabalho"; GroupDescription: "Atalhos:"; Flags: unchecked

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\IMP Criativos"; Filename: "{app}\IMP Criativos.exe"; AppUserModelID: "ImperaServices.IMPCriativos"
Name: "{autodesktop}\IMP Criativos"; Filename: "{app}\IMP Criativos.exe"; Tasks: desktopicon

[Run]
; abre o app no fim, também na atualização silenciosa feita pelo próprio app
Filename: "{app}\IMP Criativos.exe"; Description: "Abrir o IMP Criativos"; Flags: nowait postinstall

[UninstallDelete]
; só a pasta do programa; os dados em %LOCALAPPDATA%\IMP Criativos ficam
Type: filesandordirs; Name: "{app}"

[Registry]
; tira o "Iniciar com o Windows" ao desinstalar
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "IMP Criativos"; Flags: uninsdeletevalue dontcreatekey
