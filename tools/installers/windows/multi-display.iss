#ifndef AppVersion
  #error AppVersion must be provided
#endif
#ifndef FileVersion
  #error FileVersion must be provided
#endif
#ifndef ArtifactVersion
  #error ArtifactVersion must be provided
#endif
#ifndef ReleaseDir
  #error ReleaseDir must be provided
#endif
#ifndef OutputDir
  #error OutputDir must be provided
#endif

[Setup]
AppId={{E59D045D-1DA4-4915-85BF-7371F988BE89}
AppName=Multi Display
AppVersion={#AppVersion}
VersionInfoVersion={#FileVersion}
DefaultDirName={localappdata}\Programs\Multi Display
DefaultGroupName=Multi Display
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
OutputDir={#OutputDir}
OutputBaseFilename=Multi-Display-{#ArtifactVersion}-windows-x64-setup
SetupIconFile=..\..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\display_controller.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
DisableProgramGroupPage=yes

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Multi Display"; Filename: "{app}\display_controller.exe"
Name: "{autodesktop}\Multi Display"; Filename: "{app}\display_controller.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\display_controller.exe"; Description: "Launch Multi Display"; Flags: nowait postinstall skipifsilent
