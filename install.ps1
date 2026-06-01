[CmdletBinding()]
param(
    [ValidateSet('Install','Launcher','AI Video Studio','Local Agent','Open Models','Open Outputs','PowerShell','CMD','WSL','Configure SD ONNX')]
    [string]$Action = 'Install'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ScriptRoot = Split-Path -Parent $PSCommandPath
$script:DefaultConfigPath = Join-Path $script:ScriptRoot 'config/default-config.json'
$script:AppsConfigPath = Join-Path $script:ScriptRoot 'config/apps.json'
$script:LogFile = $null

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $line
    }
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Save-JsonFile {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $Object | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Resolve-AppHome {
    if ($env:LOCALAPPDATA) {
        return (Join-Path $env:LOCALAPPDATA 'AI-Video')
    }

    return (Join-Path $script:ScriptRoot 'local-ai-video')
}

function Get-ConfigPath {
    param([Parameter(Mandatory = $true)][string]$AppHome)
    Join-Path $AppHome 'config.json'
}

function Initialize-Config {
    param(
        [Parameter(Mandatory = $true)][string]$AppHome,
        [Parameter(Mandatory = $true)][string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $script:DefaultConfigPath)) {
        throw "Missing default config file: $script:DefaultConfigPath"
    }

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        $defaultConfig = Read-JsonFile -Path $script:DefaultConfigPath
        $defaultConfig.appHomePath = $AppHome
        $defaultConfig.outputPath = Join-Path $AppHome 'outputs'
        $defaultConfig.selectedModelPath = Join-Path $AppHome 'models\sd15\model.onnx'
        Save-JsonFile -Object $defaultConfig -Path $ConfigPath
        Write-Log "Created config at $ConfigPath"
    }

    $config = Read-JsonFile -Path $ConfigPath

    if ([string]::IsNullOrWhiteSpace([string]$config.appHomePath)) {
        $config.appHomePath = $AppHome
    }
    if ([string]::IsNullOrWhiteSpace([string]$config.outputPath)) {
        $config.outputPath = Join-Path $AppHome 'outputs'
    }

    Save-JsonFile -Object $config -Path $ConfigPath
    return $config
}

function Initialize-AppFolders {
    param([Parameter(Mandatory = $true)][string]$AppHome)

    $folders = @('models','runtime','outputs','agent-data','shortcuts','logs')
    foreach ($folder in $folders) {
        Ensure-Directory -Path (Join-Path $AppHome $folder)
    }
}

function Ensure-AppsConfigCopy {
    param([Parameter(Mandatory = $true)][string]$AppHome)

    if (-not (Test-Path -LiteralPath $script:AppsConfigPath)) {
        throw "Missing apps metadata file: $script:AppsConfigPath"
    }

    $targetPath = Join-Path $AppHome 'apps.json'
    if (-not (Test-Path -LiteralPath $targetPath)) {
        Copy-Item -LiteralPath $script:AppsConfigPath -Destination $targetPath -Force
        Write-Log "Created app metadata at $targetPath"
    }
}

function Is-PlaceholderUrl {
    param([AllowNull()][string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return $true }
    return ($Url -match 'example.com|placeholder|your-url-here|TODO')
}

function Download-AssetIfConfigured {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (Test-Path -LiteralPath $Destination) {
        Write-Log "$Label already exists: $Destination"
        return $true
    }

    if (Is-PlaceholderUrl -Url $Url) {
        Write-Log "$Label URL is a placeholder. Update config.json to enable auto-download." 'WARN'
        return $false
    }

    Ensure-Directory -Path (Split-Path -Parent $Destination)
    Write-Log "Downloading $Label from $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
    Write-Log "Saved $Label to $Destination"
    return $true
}

function Detect-OnnxModel {
    param([Parameter(Mandatory = $true)][string]$ModelsRoot)

    $model = Get-ChildItem -Path $ModelsRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -ieq '.onnx' } |
        Select-Object -First 1

    if ($model) {
        return $model.FullName
    }

    return $null
}

function Open-Folder {
    param([Parameter(Mandatory = $true)][string]$Path)

    Ensure-Directory -Path $Path
    Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$Path`""
}

function Open-PowerShell {
    param([Parameter(Mandatory = $true)][string]$WorkingDirectory)

    Start-Process -FilePath 'powershell.exe' -WorkingDirectory $WorkingDirectory
}

function Open-Cmd {
    param([Parameter(Mandatory = $true)][string]$WorkingDirectory)

    Start-Process -FilePath 'cmd.exe' -WorkingDirectory $WorkingDirectory
}

function Open-WSL {
    if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
        Start-Process -FilePath 'wsl.exe'
    }
    else {
        Write-Log 'WSL is not installed or not available in PATH.' 'WARN'
    }
}

function Invoke-ConfiguredApp {
    param(
        [Parameter(Mandatory = $true)][string]$AppId,
        [Parameter(Mandatory = $true)][string]$AppHome
    )

    $appsPath = Join-Path $AppHome 'apps.json'
    if (-not (Test-Path -LiteralPath $appsPath)) {
        Write-Log "Missing apps metadata at $appsPath" 'WARN'
        return
    }

    $apps = Read-JsonFile -Path $appsPath
    $app = $apps.apps | Where-Object { $_.id -eq $AppId } | Select-Object -First 1
    if (-not $app) {
        Write-Log "App entry '$AppId' was not found in $appsPath" 'WARN'
        return
    }

    if ([string]::IsNullOrWhiteSpace([string]$app.executable)) {
        Write-Log "No executable configured for '$($app.name)'. Update $appsPath first." 'WARN'
        return
    }

    if (-not (Test-Path -LiteralPath $app.executable)) {
        Write-Log "Configured executable was not found: $($app.executable)" 'WARN'
        return
    }

    $args = if ($app.args) { [string]$app.args } else { '' }
    Start-Process -FilePath $app.executable -ArgumentList $args -WorkingDirectory $AppHome
    Write-Log "Launched '$($app.name)'"
}

function Ensure-StartMenuShortcuts {
    param([Parameter(Mandatory = $true)][string]$ScriptPath)

    try {
        if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
            Write-Log 'APPDATA is not available; skipping Start Menu shortcut creation.' 'WARN'
            return
        }

        $shortcutDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\AI Video'
        Ensure-Directory -Path $shortcutDir

        $shell = New-Object -ComObject WScript.Shell
        $actions = @(
            @{ Name = 'AI Video Launcher'; Action = 'Launcher' },
            @{ Name = 'AI Video Studio'; Action = 'AI Video Studio' },
            @{ Name = 'Local Agent'; Action = 'Local Agent' },
            @{ Name = 'Open Models Folder'; Action = 'Open Models' },
            @{ Name = 'Open Outputs Folder'; Action = 'Open Outputs' }
        )

        foreach ($entry in $actions) {
            $shortcutPath = Join-Path $shortcutDir ("{0}.lnk" -f $entry.Name)
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = 'powershell.exe'
            $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Action `"$($entry.Action)`""
            $shortcut.WorkingDirectory = Split-Path -Parent $ScriptPath
            $shortcut.IconLocation = '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe,0'
            $shortcut.Save()
        }

        Write-Log "Start Menu shortcuts are ready at $shortcutDir"
    }
    catch {
        Write-Log "Could not create Start Menu shortcuts: $($_.Exception.Message)" 'WARN'
    }
}

function Show-LauncherMenu {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$AppHome
    )

    while ($true) {
        Write-Host ''
        Write-Host '=== AI Video Local Launcher ==='
        Write-Host '1) AI Video Studio'
        Write-Host '2) Local Agent'
        Write-Host '3) Open model folder'
        Write-Host '4) Open outputs folder'
        Write-Host '5) Open PowerShell'
        Write-Host '6) Open CMD'
        Write-Host '7) Open WSL'
        Write-Host '8) Configure SD ONNX / runtime download'
        Write-Host '9) Exit'

        $choice = Read-Host 'Choose an option (1-9)'

        switch ($choice) {
            '1' { Invoke-ConfiguredApp -AppId 'ai-video-studio' -AppHome $AppHome }
            '2' { Invoke-ConfiguredApp -AppId 'local-agent' -AppHome $AppHome }
            '3' { Open-Folder -Path (Join-Path $AppHome 'models') }
            '4' { Open-Folder -Path ([string]$Config.outputPath) }
            '5' { Open-PowerShell -WorkingDirectory $AppHome }
            '6' { Open-Cmd -WorkingDirectory $AppHome }
            '7' { Open-WSL }
            '8' { Invoke-SdOnnxSetup -Config ([ref]$Config) -AppHome $AppHome }
            '9' { return }
            default { Write-Log 'Invalid selection. Choose 1-9.' 'WARN' }
        }
    }
}

function Invoke-SdOnnxSetup {
    param(
        [Parameter(Mandatory = $true)][ref]$Config,
        [Parameter(Mandatory = $true)][string]$AppHome
    )

    $runtimeArchive = Join-Path $AppHome 'runtime\onnxruntime-win-x64.zip'
    $modelArchive = Join-Path $AppHome 'models\sd-onnx\sd-model.zip'

    [void](Download-AssetIfConfigured -Url ([string]$Config.Value.onnxRuntimeUrl) -Destination $runtimeArchive -Label 'ONNX Runtime bundle')
    [void](Download-AssetIfConfigured -Url ([string]$Config.Value.sdOnnxModelUrl) -Destination $modelArchive -Label 'Stable Diffusion ONNX model package')

    $detected = Detect-OnnxModel -ModelsRoot (Join-Path $AppHome 'models')
    if ($detected) {
        $Config.Value.selectedModelPath = $detected
        Write-Log "Detected ONNX model: $detected"
    }
    else {
        Write-Log 'No .onnx file detected yet. Add/extract an SD ONNX model under the models folder.' 'WARN'
    }

    Save-JsonFile -Object $Config.Value -Path (Get-ConfigPath -AppHome $AppHome)
}

function Invoke-Action {
    param(
        [Parameter(Mandatory = $true)][string]$ChosenAction,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$AppHome
    )

    switch ($ChosenAction) {
        'Install' {
            Invoke-SdOnnxSetup -Config ([ref]$Config) -AppHome $AppHome
            if ($Config.launcher -and $Config.launcher.openMenuOnInstall) {
                Show-LauncherMenu -Config $Config -AppHome $AppHome
            }
        }
        'Launcher' { Show-LauncherMenu -Config $Config -AppHome $AppHome }
        'AI Video Studio' { Invoke-ConfiguredApp -AppId 'ai-video-studio' -AppHome $AppHome }
        'Local Agent' { Invoke-ConfiguredApp -AppId 'local-agent' -AppHome $AppHome }
        'Open Models' { Open-Folder -Path (Join-Path $AppHome 'models') }
        'Open Outputs' { Open-Folder -Path ([string]$Config.outputPath) }
        'PowerShell' { Open-PowerShell -WorkingDirectory $AppHome }
        'CMD' { Open-Cmd -WorkingDirectory $AppHome }
        'WSL' { Open-WSL }
        'Configure SD ONNX' { Invoke-SdOnnxSetup -Config ([ref]$Config) -AppHome $AppHome }
    }
}

$appHome = Resolve-AppHome
Initialize-AppFolders -AppHome $appHome
$script:LogFile = Join-Path $appHome 'logs\install.log'
Ensure-Directory -Path (Split-Path -Parent $script:LogFile)

$configPath = Get-ConfigPath -AppHome $appHome
$config = Initialize-Config -AppHome $appHome -ConfigPath $configPath
Ensure-AppsConfigCopy -AppHome $appHome
Ensure-StartMenuShortcuts -ScriptPath $PSCommandPath

Write-Log "App home: $appHome"
Write-Log "Config path: $configPath"
Write-Log 'This repository provides a Windows-first installer/launcher scaffold only.'
Write-Log 'Stable Diffusion ONNX and ONNX Runtime downloads depend on URLs configured in config.json.'

Invoke-Action -ChosenAction $Action -Config $config -AppHome $appHome
