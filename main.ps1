Set-StrictMode -Version Latest
$script:ErrorActionPreference = 'Stop'
$script:ProgressPreference = 'SilentlyContinue'

function Show-Menu {
    Write-Host '=== Menu ===' -ForegroundColor Green
    Write-Host '0. Install cygwin'
    Write-Host '1. Reset'
    Write-Host '2. Install iconv'
    Write-Host '3. Install json-c'
    Write-Host '4. Install curl'
    Write-Host '5. Install gettext'
    Write-Host '6. Install all'
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
                Reset-Sources
            }
            '2' {
                Install-Iconv
            }
            '3' {
                Install-JsonC
            }
            '4' {
                Install-Curl
            }
            '5' {
                Install-Gettext
            }
            '6' { 
                Install-Iconv
                if (-not($script:GettextVersion.StartsWith('0.'))) {
                    Install-JsonC
                    Install-Curl
                }
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

function Reset-Sources {
    Write-Host 'Resetting...' -ForegroundColor Yellow
    if (Test-Path -Path $script:WinInstalledDir -PathType Container) {
        Remove-Item -Path $script:WinInstalledDir -Recurse -Force
    }
    if (Test-Path -Path $script:WinSrcDir -PathType Container) {
        Remove-Item -Path $script:WinSrcDir -Recurse -Force
    }
}

function Install-Cygwin {
    Initialize-Paths
    $exe = Join-Path $script:WinTempDir 'cygwin-installer.exe'
    if (-not(Test-Path -Path $exe -PathType Leaf)) {
        Write-Host "Downloading Cygwin installer..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri 'https://cygwin.com/setup-x86_64.exe' -OutFile $exe
    }
    Write-Host "Installing Cygwin..." -ForegroundColor Cyan
    $packageDir = Join-Path $script:WinTempDir 'cygwin-packages'
    $architecture = 'x86_64'
    $mingwHost = "$architecture-w64-mingw32"
    $packages = "file,make,unzip,dos2unix,patch,mingw64-$architecture-gcc-core,mingw64-$architecture-gcc-g++,mingw64-$architecture-headers,mingw64-$architecture-runtime,cmake,gdb"
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
    Initialize-Paths
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
        Invoke-PatchSource "libiconv-$($script:IconvVersion)"
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

function Install-JsonC {
    Initialize-Paths
    $winSrcDir = Join-Path $script:WinSrcDir "json-c-$($script:JsonCVersion)"
    if (-not(Test-Path -Path $winSrcDir -PathType Container)) {
        $winTarball = Join-Path $script:WinTempDir "json-c-$($script:JsonCVersion).tar.gz"
        if (-not(Test-Path -Path $winTarball -PathType Leaf)) {
            Write-Host "Downloading json-c tarball..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri "https://s3.amazonaws.com/json-c_releases/releases/json-c-$($script:JsonCVersion)-nodoc.tar.gz" -OutFile $winTarball
        }
        Write-Host "Extracting json-c tarball..." -ForegroundColor Cyan
        $cygTarball = ConvertTo-CygwinPath $winTarball
        Invoke-Bash -WindowsPath $script:WinSrcDir -Command "tar -xzf '$cygTarball'"
        Invoke-PatchSource "json-c-$($script:JsonCVersion)"
    }
    $winBuildDir = Join-Path $winSrcDir 'build'
    if (Test-Path -Path $winBuildDir -PathType Container) {
        Remove-Item -Path $winBuildDir -Recurse -Force
    }
    New-Item -Path $winBuildDir -ItemType Directory | Out-Null
    Write-Host "Installing json-c $($script:JsonCVersion)..." -ForegroundColor Cyan
    if ($script:DebugMode) {
        $flags='-g -O0'
        $buildType='Debug'
    } else {
        $flags='-g0 -O2'
        $buildType='Release'
    }
    Invoke-Bash -WindowsPath $winBuildDir -Command "cmake -DCMAKE_BUILD_TYPE=$buildType '-DCMAKE_INSTALL_PREFIX=$($script:CygInstalledDir)' -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DBUILD_TESTING=OFF -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc -DCMAKE_C_FLAGS='$flags' -DBUILD_STATIC_LIBS=ON -DBUILD_SHARED_LIBS=OFF ../"
    Invoke-Bash -WindowsPath $winBuildDir -Command 'make --jobs=1 all'
    Invoke-Bash -WindowsPath $winBuildDir -Command 'make install'
}

function Install-Curl {
    Initialize-Paths
    $winSrcDir = Join-Path $script:WinSrcDir "curl-$($script:CurlVersion)"
    if (-not(Test-Path -Path $winSrcDir -PathType Container)) {
        $winTarball = Join-Path $script:WinTempDir "curl-$($script:CurlVersion).tar.gz"
        if (-not(Test-Path -Path $winTarball -PathType Leaf)) {
            Write-Host "Downloading curl tarball..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri "https://curl.se/download/curl-$($script:CurlVersion).tar.gz" -OutFile $winTarball
        }
        Write-Host "Extracting curl tarball..." -ForegroundColor Cyan
        $cygTarball = ConvertTo-CygwinPath $winTarball
        Invoke-Bash -WindowsPath $script:WinSrcDir -Command "tar -xzf '$cygTarball'"
        Invoke-PatchSource "curl-$($script:CurlVersion)"
    }
    $winBuildDir = Join-Path $winSrcDir 'build'
    if (Test-Path -Path $winBuildDir -PathType Container) {
        Remove-Item -Path $winBuildDir -Recurse -Force
    }
    New-Item -Path $winBuildDir -ItemType Directory | Out-Null
    if ($script:DebugMode) {        $flags='-g -O0'
    } else {
        $flags='-g0 -O2'
    }
    Write-Host "Configuring curl $($script:CurlVersion)..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $winBuildDir -Command "../configure CC='x86_64-w64-mingw32-gcc' CXX='x86_64-w64-mingw32-g++' LD='x86_64-w64-mingw32-ld' STRIP='x86_64-w64-mingw32-strip' CPPFLAGS='-I$($script:CygInstalledDir)/include -I/usr/x86_64-w64-mingw32/sys-root/mingw/include -DWINVER=0x0601 -D_WIN32_WINNT=0x0601' CFLAGS='$($flags)' CXXFLAGS='$($flags)' LDFLAGS='-L$($script:CygInstalledDir)/lib -L/usr/x86_64-w64-mingw32/sys-root/mingw/lib' --host=x86_64-w64-mingw32 --enable-http --disable-ftp --enable-file --disable-ldap --disable-ldaps --disable-rtsp --enable-proxy --disable-ipfs --disable-dict --disable-telnet --disable-tftp --disable-pop3 --disable-imap --disable-smb --disable-smtp --disable-gopher --disable-mqtt --disable-manual --disable-docs --enable-ipv6 --enable-windows-unicode --disable-cookies --with-schannel --without-gnutls --without-openssl --without-rustls --without-wolfssl --without-libpsl --with-winidn --disable-threaded-resolver --disable-kerberos-auth --disable-ntlm --disable-negotiate-auth --disable-sspi --disable-unix-sockets --disable-dependency-tracking --prefix=$($script:CygInstalledDir) --enable-static --disable-shared"
    Write-Host "Static libraries to be included into gettext:" -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $winBuildDir -Command './curl-config --static-libs'
    Write-Host "curl features:" -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $winBuildDir -Command './curl-config --features'
    Write-Host "Building curl $($script:CurlVersion) - lib..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $(Join-Path $winBuildDir 'lib') -Command "make --jobs=$([System.Environment]::ProcessorCount)"
    Write-Host "Installing curl $($script:CurlVersion) - lib..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $(Join-Path $winBuildDir 'lib') -Command 'make install'
    Write-Host "Building curl $($script:CurlVersion) - include..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $(Join-Path $winBuildDir 'include') -Command "make --jobs=$([System.Environment]::ProcessorCount)"
    Write-Host "Installing curl $($script:CurlVersion) - include..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $(Join-Path $winBuildDir 'include') -Command 'make install'
}

function Install-Gettext {
    Initialize-Paths
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
        Invoke-PatchSource "gettext-$($script:GettextVersion)"
    }
    $winBuildDir = Join-Path $winSrcDir 'build'
    if (Test-Path -Path $winBuildDir -PathType Container) {
        Remove-Item -Path $winBuildDir -Recurse -Force
    }
    New-Item -Path $winBuildDir -ItemType Directory | Out-Null
    if ($script:DebugMode) {
        $flags='-g -O0'
    } else {
        $flags='-g0 -O2'
    }
    $libs=''
    if (-not($script:GettextVersion.StartsWith('0.'))) {
        $flags += ' -DCURL_STATICLIB'
        $gettextBuildDir = Join-Path $script:WinSrcDir "curl-$($script:CurlVersion)" 'build'
        $libs = Invoke-Bash -WindowsPath $gettextBuildDir -Command './curl-config --static-libs' -CaptureOutput $true
    }
    Write-Host "Configuring gettext $GettextVersion..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $winBuildDir -Command "../configure LIBS='$libs' CC='x86_64-w64-mingw32-gcc' CXX='x86_64-w64-mingw32-g++' LD='x86_64-w64-mingw32-ld' STRIP='x86_64-w64-mingw32-strip' CPPFLAGS='-I$($script:CygInstalledDir)/include -I/usr/x86_64-w64-mingw32/sys-root/mingw/include -DWINVER=0x0601 -D_WIN32_WINNT=0x0601' CFLAGS='$($flags)' CXXFLAGS='$($flags) -fno-threadsafe-statics' LDFLAGS='-L$($script:CygInstalledDir)/lib -L/usr/x86_64-w64-mingw32/sys-root/mingw/lib' --host=x86_64-w64-mingw32 --enable-relocatable --config-cache --disable-dependency-tracking --enable-nls --disable-rpath --disable-acl --enable-threads=windows --prefix=$($script:CygInstalledDir) --disable-shared --enable-static --disable-java --disable-native-java --disable-openmp --disable-curses --disable-csharp --without-emacs --with-included-libxml --without-bzip2 --without-xz"
    Write-Host "Building gettext $GettextVersion..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $winBuildDir -Command 'make'
    Write-Host "Installing gettext $GettextVersion..." -ForegroundColor Cyan
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

function Initialize-Paths {
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
        [string] $Command,
        [Parameter(Mandatory = $false)]
        [bool] $CaptureOutput = $false

    )
    $CygwinPath = ConvertTo-CygwinPath $WindowsPath
    $argumentList = @(
        '--login',
        '-o', 'igncr',
        '-o', 'errexit',
        '-o', 'pipefail',
        '-c', "cd '$CygwinPath' && $Command"
    )
    if ($CaptureOutput) {
        $result = & $script:CygwinPath\bin\bash.exe $argumentList
    } else {
        & $script:CygwinPath\bin\bash.exe $argumentList
    }
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $message = "Bash command failed with exit code $($exitCode): $Command"
        if ($CaptureOutput) {
            $message += "`nOutput:`n$result"
        }
        throw $message
    }
    if ($CaptureOutput) {
        return $result
    }
}

function Invoke-PatchSource {
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

$script:IconvVersion = '1.17'
$script:CurlVersion = '8.18.0'
$script:JsonCVersion = '0.18'
$script:GettextVersion = '1.0-pre2'
$script:DebugMode = $true
$script:CygwinPath = 'D:\cygwin'
$script:WinTempDir = Join-Path  $PSScriptRoot 'temp'
$script:CygTempDir = ConvertTo-CygwinPath $script:WinTempDir
$script:WinSrcDir = Join-Path $PSScriptRoot 'src'
$script:CygSrcDir = ConvertTo-CygwinPath $script:WinSrcDir
$script:WinInstalledDir = Join-Path $PSScriptRoot 'installed'
$script:CygInstalledDir = ConvertTo-CygwinPath $script:WinInstalledDir

Show-Menu
