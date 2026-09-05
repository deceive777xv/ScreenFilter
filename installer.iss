[Setup]
AppId=ScreenFilterApp
AppName=ScreenFilter
AppVersion=1.0.0
DefaultDirName={localappdata}\Programs\ScreenFilter
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=dist
OutputBaseFilename=ScreenFilter-Setup-1.0.0
SetupIconFile=assets\screenfilter_icon.ico
UninstallDisplayIcon={app}\screen_filter_app.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Icons]
Name: "{userprograms}\ScreenFilter"; Filename: "{app}\screen_filter_app.exe"; WorkingDir: "{app}"
Name: "{userdesktop}\ScreenFilter"; Filename: "{app}\screen_filter_app.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\screen_filter_app.exe"; Description: "Launch ScreenFilter"; Flags: nowait postinstall skipifsilent