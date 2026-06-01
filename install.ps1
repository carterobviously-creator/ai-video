[CmdletBinding()]
param(
    [ValidateSet('Install','Launcher','AI Video Studio','Local Agent','Open Models','Open Outputs','PowerShell','CMD','WSL','Generate')]
    [string]$Action = 'Install'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ScriptRoot = Split-Path -Parent $PSCommandPath
$script:DefaultConfigPath = Join-Path $script:ScriptRoot 'config/default-config.json'
$script:AppsConfigPath = Join-Path $script:ScriptRoot 'config/apps.json'
$script:GenerateScript = Join-Path $script:ScriptRoot 'generate.py'
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
    
    # Ensure new config fields exist (upgrade path)
    $defaultConfig = Read-JsonFile -Path $script:DefaultConfigPath
    $needsSave = $false
    
    if (-not (Get-Member -InputObject $config -Name 'sdOnnxModelId' -MemberType NoteProperty)) {
        $config | Add-Member -NotePropertyName 'sdOnnxModelId' -NotePropertyValue $defaultConfig.sdOnnxModelId
        $needsSave = $true
    }
    if (-not (Get-Member -InputObject $config -Name 'sdOnnxModelRevision' -MemberType NoteProperty)) {
        $config | Add-Member -NotePropertyName 'sdOnnxModelRevision' -NotePropertyValue $defaultConfig.sdOnnxModelRevision
        $needsSave = $true
    }
    if (-not (Get-Member -InputObject $config -Name 'pythonPackages' -MemberType NoteProperty)) {
        $config | Add-Member -NotePropertyName 'pythonPackages' -NotePropertyValue $defaultConfig.pythonPackages
        $needsSave = $true
    }
    if (-not (Get-Member -InputObject $config -Name 'generation' -MemberType NoteProperty)) {
        $config | Add-Member -NotePropertyName 'generation' -NotePropertyValue $defaultConfig.generation
        $needsSave = $true
    }

    if ([string]::IsNullOrWhiteSpace([string]$config.appHomePath)) {
        $config.appHomePath = $AppHome
        $needsSave = $true
    }
    if ([string]::IsNullOrWhiteSpace([string]$config.outputPath)) {
        $config.outputPath = Join-Path $AppHome 'outputs'
        $needsSave = $true
    }

    if ($needsSave) {
        Save-JsonFile -Object $config -Path $ConfigPath
    }
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
    # Always update apps.json from source to keep it current
    Copy-Item -LiteralPath $script:AppsConfigPath -Destination $targetPath -Force
}

function Find-Python {
    # Try python, then python3, then py launcher
    $candidates = @('python', 'python3', 'py')
    foreach ($cmd in $candidates) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) {
            # Verify it's Python 3
            try {
                $version = & $cmd --version 2>&1
                if ($version -match 'Python 3') {
                    return $cmd
                }
            } catch {}
        }
    }
    return $null
}

function Install-PythonDependencies {
    param([Parameter(Mandatory = $true)]$Config)

    $pythonCmd = Find-Python
    if (-not $pythonCmd) {
        Write-Log "Python 3 is not installed or not in PATH." 'ERROR'
        Write-Log "Please install Python 3.10+ from https://www.python.org/downloads/" 'ERROR'
        Write-Log "Make sure to check 'Add Python to PATH' during installation." 'ERROR'
        return $false
    }

    Write-Log "Found Python: $pythonCmd"

    $packages = $Config.pythonPackages
    if (-not $packages -or $packages.Count -eq 0) {
        $packages = @('onnxruntime', 'diffusers', 'transformers', 'numpy', 'Pillow')
    }

    Write-Log "Installing Python packages: $($packages -join ', ')"
    $packageList = $packages -join ' '

    try {
        $proc = Start-Process -FilePath $pythonCmd -ArgumentList "-m pip install --upgrade pip" -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -ne 0) {
            Write-Log "pip upgrade failed (non-fatal), continuing..." 'WARN'
        }
        $proc = Start-Process -FilePath $pythonCmd -ArgumentList "-m pip install $packageList" -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -ne 0) {
            Write-Log "pip install failed with exit code $($proc.ExitCode)" 'ERROR'
            return $false
        }
        Write-Log "Python dependencies installed successfully."
        return $true
    }
    catch {
        Write-Log "Failed to install Python packages: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Download-OnnxRuntime {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$AppHome
    )

    $url = [string]$Config.onnxRuntimeUrl
    if ([string]::IsNullOrWhiteSpace($url)) {
        Write-Log "No ONNX Runtime URL configured, skipping standalone runtime download." 'WARN'
        return
    }

    $runtimeDir = Join-Path $AppHome 'runtime'
    $archivePath = Join-Path $runtimeDir 'onnxruntime-win-x64.zip'
    $extractedMarker = Join-Path $runtimeDir '.extracted'

    if (Test-Path -LiteralPath $extractedMarker) {
        Write-Log "ONNX Runtime already extracted."
        return
    }

    if (-not (Test-Path -LiteralPath $archivePath)) {
        Write-Log "Downloading ONNX Runtime from $url"
        Ensure-Directory -Path $runtimeDir
        Invoke-WebRequest -Uri $url -OutFile $archivePath -UseBasicParsing
        Write-Log "Downloaded ONNX Runtime archive."
    }

    Write-Log "Extracting ONNX Runtime..."
    Expand-Archive -Path $archivePath -DestinationPath $runtimeDir -Force
    Set-Content -Path $extractedMarker -Value (Get-Date -Format 'o')
    Write-Log "ONNX Runtime extracted to $runtimeDir"
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

function Invoke-Generate {
    param(
        [Parameter(Mandatory = $true)][string]$Mode,
        [string]$Prompt
    )

    $pythonCmd = Find-Python
    if (-not $pythonCmd) {
        Write-Log "Python 3 not found. Run Install action first." 'ERROR'
        return
    }

    if (-not (Test-Path -LiteralPath $script:GenerateScript)) {
        Write-Log "generate.py not found at $script:GenerateScript" 'ERROR'
        return
    }

    if ($Mode -eq 'interactive') {
        $arguments = "`"$script:GenerateScript`" --interactive"
    } else {
        $arguments = "`"$script:GenerateScript`" --prompt `"$Prompt`""
    }

    Start-Process -FilePath $pythonCmd -ArgumentList $arguments -WorkingDirectory $script:ScriptRoot -NoNewWindow -Wait
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
            @{ Name = 'Generate Image'; Action = 'Generate' },
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
        Write-Host '1) Generate Image (interactive)'
        Write-Host '2) Open outputs folder'
        Write-Host '3) Open model cache folder'
        Write-Host '4) Re-install Python dependencies'
        Write-Host '5) Open PowerShell'
        Write-Host '6) Open CMD'
        Write-Host '7) Open WSL'
        Write-Host '8) Exit'

        $choice = Read-Host 'Choose an option (1-8)'

        switch ($choice) {
            '1' { Invoke-Generate -Mode 'interactive' }
            '2' { Open-Folder -Path ([string]$Config.outputPath) }
            '3' { Open-Folder -Path (Join-Path $AppHome 'models') }
            '4' { Install-PythonDependencies -Config $Config }
            '5' { Open-PowerShell -WorkingDirectory $AppHome }
            '6' { Open-Cmd -WorkingDirectory $AppHome }
            '7' { Open-WSL }
            '8' { return }
            default { Write-Log 'Invalid selection. Choose 1-8.' 'WARN' }
        }
    }
}

function Invoke-Action {
    param(
        [Parameter(Mandatory = $true)][string]$ChosenAction,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$AppHome
    )

    switch ($ChosenAction) {
        'Install' {
            Write-Log "Setting up AI Video Studio..."
            $pyOk = Install-PythonDependencies -Config $Config
            if ($pyOk) {
                Download-OnnxRuntime -Config $Config -AppHome $AppHome
                Write-Log ""
                Write-Log "============================================"
                Write-Log " Setup complete! You're ready to generate."
                Write-Log " The first generation will download the SD 1.5"
                Write-Log " ONNX model (~5 GB) automatically."
                Write-Log "============================================"
            }
            if ($Config.launcher -and $Config.launcher.openMenuOnInstall) {
                Show-LauncherMenu -Config $Config -AppHome $AppHome
            }
        }
        'Launcher' { Show-LauncherMenu -Config $Config -AppHome $AppHome }
        'AI Video Studio' { Invoke-Generate -Mode 'interactive' }
        'Local Agent' { Invoke-Generate -Mode 'interactive' }
        'Generate' { Invoke-Generate -Mode 'interactive' }
        'Open Models' { Open-Folder -Path (Join-Path $AppHome 'models') }
        'Open Outputs' { Open-Folder -Path ([string]$Config.outputPath) }
        'PowerShell' { Open-PowerShell -WorkingDirectory $AppHome }
        'CMD' { Open-Cmd -WorkingDirectory $AppHome }
        'WSL' { Open-WSL }
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

Invoke-Action -ChosenAction $Action -Config $config -AppHome $appHome
