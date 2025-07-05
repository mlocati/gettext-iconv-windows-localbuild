Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-Menu {
    Write-Host '=== Menu ===' -ForegroundColor Green
    Write-Host '0. Install cygwin'
    Write-Host '1. Reset'
    Write-Host '2. Install iconv'
    Write-Host '3. Install gettext'
    Write-Host '4. Install iconv + gettext + iconv'
    Write-Host "A. iconv version: $IconvVersion"
    Write-Host "B. gettext version: $gettextVersion"
    $debugText = if ($DebugMode) { 'on' } else { 'off' }
    Write-Host "C. Debug: $debugText"
    Write-Host 'Q. Quit'
    while ($true) {
        $choice = Read-Host 'Your option'
        $choice = $choice.Trim().ToUpper()
        switch ($choice) {
            '0' {
                Install-Cygwin
            }
            '1' {
                Make-Clean
            }
            '2' {
                Install-Iconv
            }
            '3' {
                Install-Gettext
            }
            '4' { 
                Install-Iconv
                Install-Gettext
                Install-Iconv
            }
            'A' {
                Set-IconvVersion
            }
            'B' {
                Set-GettextVersion
            }
            'C' {
                Switch-Debug
            }
            'Q' {
                break 2
            }
            default {
                Write-Host 'Invalid choiche' -ForegroundColor Red
            }
        }
        Write-Host ''
        Show-Menu
    }
}

function Make-Clean {
    Write-Host 'Resetting...' -ForegroundColor Yellow
    if (Test-Path -Path $script:WinInstalledDir -PathType Container) {
        Remove-Item -Path $script:WinInstalledDir -Recurse -Force
    }
    if (Test-Path -Path $script:WinSrcDir -PathType Container) {
        Remove-Item -Path $script:WinSrcDir -Recurse -Force
    }
}

function Install-Cygwin {
    Ensure-Paths
    $exe = Join-Path $script:WinTempDir 'cygwin-installer.exe'
    if (-not(Test-Path -Path $exe -PathType Leaf)) {
        Write-Host "Downloading Cygwin installer..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri 'https://cygwin.com/setup-x86_64.exe' -OutFile $exe
    }
    Write-Host "Installing Cygwin..." -ForegroundColor Cyan
    $packageDir = Join-Path $script:WinTempDir 'cygwin-packages'
    $architecture = 'x86_64'
    $mingwHost = "$architecture-w64-mingw32"
    $packages = "wget,file,make,unzip,dos2unix,patch,mingw64-$architecture-gcc-core,mingw64-$architecture-gcc-g++,mingw64-$architecture-headers,mingw64-$architecture-runtime,gdb"
    $argumentList = @(
        '-qnO',
        '-l', $packageDir,
        '-R', $script:CygwinPath,
        '-s', 'http://mirrors.kernel.org/sourceware/cygwin/',
        '-P', $packages
    )
    $proc = Start-Process -FilePath $exe -ArgumentList $argumentList -Wait -PassThru
    $exitCode = $proc.ExitCode
    if ($exitCode -ne 0) {
        throw "Cygwin installation failed with exit code $exitCode"
    }
    Invoke-Bash -WindowsPath $script:CygwinPath -Command "exit"
    $dirs = Get-ChildItem -Path "$($script:CygwinPath)\home" -Directory
    if (-not($dirs)) {
        throw "No home directories found in $($script:CygwinPath)\home"
    }
    if ($dirs -is [System.Array]) { 
        if ($dirs.Length -ne 1) {
            throw "Expected just 1 home directory, found $($dirs.Length)"
        }
        $homeDir = $dirs[0].FullName
    } else {
        $homeDir = $dirs.FullName
    }
    $bashProfilePath = Join-Path $homeDir '.bash_profile'
    $bashProfileContent = @(
        'source "${HOME}/.bashrc"',
        "PATH=$($script:CygInstalledDir):/usr/$mingwHost/bin:/usr/$mingwHost/sys-root/mingw/bin:/usr/sbin:/usr/bin:/sbin:/bin:/cygdrive/c/Windows/System32:/cygdrive/c/Windows",
        'export PATH',
        ''
    ) -join "`n"
    [System.IO.File]::WriteAllText($bashProfilePath, $bashProfileContent)
}

function Install-Iconv {
    Ensure-Paths
    $winSrcDir = Join-Path $script:WinSrcDir "libiconv-$($script:IconvVersion)"
    if (-not(Test-Path -Path $winSrcDir -PathType Container)) {
        $winTarball = Join-Path $script:WinTempDir "libiconv-$($script:IconvVersion).tar.gz"
        if (-not(Test-Path -Path $winTarball -PathType Leaf)) {
            Write-Host "Downloading iconv tarball..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri "https://ftp.gnu.org/pub/gnu/libiconv/libiconv-$($script:IconvVersion).tar.gz" -OutFile $winTarball
        }
        Write-Host "Extracting iconv tarball..." -ForegroundColor Cyan
        $cygTarball = ConvertTo-CygwinPath $winTarball
        Invoke-Bash -WindowsPath $script:WinSrcDir -Command "tar -xzf '$cygTarball'"
        Apply-SrcPatches "libiconv-$($script:IconvVersion)"
    }
    $winBuildDir = Join-Path $winSrcDir 'build'
    if (Test-Path -Path $winBuildDir -PathType Container) {
        Remove-Item -Path $winBuildDir -Recurse -Force
    }
    New-Item -Path $winBuildDir -ItemType Directory | Out-Null
    Write-Host "Installing iconv $IconvVersion..." -ForegroundColor Cyan
    if ($script:DebugMode) {
        $flags='-g -O0'
    } else {
        $flags='-g0 -O2'
    }
    Invoke-Bash -WindowsPath $winBuildDir -Command "../configure CC='x86_64-w64-mingw32-gcc' CXX='x86_64-w64-mingw32-g++' LD='x86_64-w64-mingw32-ld' STRIP='x86_64-w64-mingw32-strip' CPPFLAGS='-I$($script:CygInstalledDir)/include -I/usr/x86_64-w64-mingw32/sys-root/mingw/include -DWINVER=0x0601 -D_WIN32_WINNT=0x0601' CFLAGS='$($flags)' CXXFLAGS='$($flags) -fno-threadsafe-statics' LDFLAGS='-L$($script:CygInstalledDir)/lib -L/usr/x86_64-w64-mingw32/sys-root/mingw/lib' --host=x86_64-w64-mingw32 --enable-relocatable --config-cache --disable-dependency-tracking --enable-nls --disable-rpath --disable-acl --enable-threads=windows --prefix=$($script:CygInstalledDir) --disable-shared --enable-static --enable-extra-encodings"
    Invoke-Bash -WindowsPath $winBuildDir -Command 'make install'
}

function Install-Gettext {
    Ensure-Paths
    $winSrcDir = Join-Path $script:WinSrcDir "gettext-$($script:GettextVersion)"
    if (-not(Test-Path -Path $winSrcDir -PathType Container)) {
        $winTarball = Join-Path $script:WinTempDir "gettext-$($script:GettextVersion).tar.gz"
        if (-not(Test-Path -Path $winTarball -PathType Leaf)) {
            Write-Host "Downloading gettext tarball..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri "https://ftp.gnu.org/pub/gnu/gettext/gettext-$($script:GettextVersion).tar.gz" -OutFile $winTarball
        }
        Write-Host "Extracting gettext tarball..." -ForegroundColor Cyan
        $cygTarball = ConvertTo-CygwinPath $winTarball
        Invoke-Bash -WindowsPath $script:WinSrcDir -Command "tar -xzf '$cygTarball'"
        Apply-SrcPatches "gettext-$($script:GettextVersion)"
    }
    $winBuildDir = Join-Path $winSrcDir 'build'
    if (Test-Path -Path $winBuildDir -PathType Container) {
        Remove-Item -Path $winBuildDir -Recurse -Force
    }
    New-Item -Path $winBuildDir -ItemType Directory | Out-Null
    Write-Host "Installing gettext $GettextVersion..." -ForegroundColor Cyan
    if ($script:DebugMode) {
        $flags='-g -O0'
    } else {
        $flags='-g0 -O2'
    }
    Invoke-Bash -WindowsPath $winBuildDir -Command "../configure CC='x86_64-w64-mingw32-gcc' CXX='x86_64-w64-mingw32-g++' LD='x86_64-w64-mingw32-ld' STRIP='x86_64-w64-mingw32-strip' CPPFLAGS='-I$($script:CygInstalledDir)/include -I/usr/x86_64-w64-mingw32/sys-root/mingw/include -DWINVER=0x0601 -D_WIN32_WINNT=0x0601' CFLAGS='$($flags)' CXXFLAGS='$($flags) -fno-threadsafe-statics' LDFLAGS='-L$($script:CygInstalledDir)/lib -L/usr/x86_64-w64-mingw32/sys-root/mingw/lib' --host=x86_64-w64-mingw32 --enable-relocatable --config-cache --disable-dependency-tracking --enable-nls --disable-rpath --disable-acl --enable-threads=windows --prefix=$($script:CygInstalledDir) --disable-shared --enable-static --disable-java --disable-native-java --disable-openmp --disable-curses --disable-csharp --without-emacs --with-included-libxml --without-bzip2 --without-xz"
    Invoke-Bash -WindowsPath $winBuildDir -Command 'make install'
}

function Set-IconvVersion {
    $newVersion = Read-Host "Enter new iconv version (current: $IconvVersion)"
    if ($newVersion) {
        $script:IconvVersion = $newVersion
    }
    else {
        Write-Host 'No version entered, keeping current version.' -ForegroundColor Yellow
    }
}

function Set-GettextVersion {
    $newVersion = Read-Host "Enter new gettext version (current: $GettextVersion)"
    if ($newVersion) {
        $script:GettextVersion = $newVersion
    }
    else {
        Write-Host 'No version entered, keeping current version.' -ForegroundColor Yellow
    }
}

function Switch-Debug {
    $script:DebugMode = -not $script:DebugMode
}

function ConvertTo-CygwinPath()
{
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $WindowsPath
    )
    $match = Select-String -InputObject $WindowsPath -Pattern '^([A-Za-z]):(\\.*)$'
    if (!$match) {
        throw "Invalid value of WindowsPath '$WindowsPath'"
    }
    return '/cygdrive/' + $match.Matches.Groups[1].Value.ToLowerInvariant() + $match.Matches.Groups[2].Value.Replace('\', '/')
}

function Ensure-Paths {
    if (-not (Test-Path -Path $script:WinTempDir -PathType Container)) {
        New-Item -Path $script:WinTempDir -ItemType Directory | Out-Null
    }
    if (-not (Test-Path -Path $script:WinSrcDir -PathType Container)) {
        New-Item -Path $script:WinSrcDir -ItemType Directory | Out-Null
    }
    if (-not (Test-Path -Path $script:WinInstalledDir -PathType Container)) {
        New-Item -Path $script:WinInstalledDir -ItemType Directory | Out-Null
    }
}

function Invoke-Bash {
    param(
        [Parameter(Mandatory = $true)]
        [string] $WindowsPath,
        [Parameter(Mandatory = $true)]
        [string] $Command
    )
    $CygwinPath = ConvertTo-CygwinPath $WindowsPath
    $argumentList = @(
        '--login',
        '-o', 'igncr',
        '-o', 'errexit',
        '-o', 'pipefail',
        '-c', "cd '$CygwinPath' && $Command"
    )
    & $script:CygwinPath\bin\bash.exe $argumentList
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Bash command failed with exit code $($exitCode): $Command"
    }
}

function Apply-SrcPatches {
    param(
        [Parameter(Mandatory = $true)]
        [string] $DirName
    )
    $patchesDir = Join-Path (Join-Path $PSScriptRoot 'patches') $DirName
    if (-not (Test-Path -Path $patchesDir -PathType Container)) {
        return
    }
    $patches = Get-ChildItem -Path $patchesDir -Filter '*.patch'
    if (-not($patches)) {
        return
    }
    if (-not($patches -is [System.Array])) {
        $patches = @($patches)
    }
    foreach ($patch in $patches) {
        Write-Host "Applying patch: $($patch.Name)" -ForegroundColor Cyan 
        $cygPatch = ConvertTo-CygwinPath $patch.FullName
        $winSrcDir = Join-Path $script:WinSrcDir $DirName
        Invoke-Bash -WindowsPath $winSrcDir -Command "patch -p1 < '$cygPatch'"
    }
}

$env:CHERE_INVOKING = '1'
$env:CYGWIN_NOWINPATH = '1'

$script:IconvVersion = '1.18'
$script:GettextVersion = '0.25.1'
$script:DebugMode = $true
$script:CygwinPath = 'C:\cygwin'
$script:WinTempDir = Join-Path  $PSScriptRoot 'temp'
$script:CygTempDir = ConvertTo-CygwinPath $script:WinTempDir
$script:WinSrcDir = Join-Path $PSScriptRoot 'src'
$script:CygSrcDir = ConvertTo-CygwinPath $script:WinSrcDir
$script:WinInstalledDir = Join-Path $PSScriptRoot 'installed'
$script:CygInstalledDir = ConvertTo-CygwinPath $script:WinInstalledDir

Show-Menu
