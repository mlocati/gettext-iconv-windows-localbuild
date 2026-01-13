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
    Write-Host "D. Bitness: $($script:Bitness)"
    Write-Host "E. Link: $($script:Link)"
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
            'D' {
                if ($script:Bitness -eq 64) {
                    Set-Enviro -Bitness 32 -Link $script:Link
                } else {
                    Set-Enviro -Bitness 64 -Link $script:Link
                }
            }
            'E' {
                if ($script:Link -eq 'static') {
                    Set-Enviro -Bitness $script:Bitness -Link 'shared'
                } else {
                    Set-Enviro -Bitness $script:Bitness -Link 'static'
                }
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
    $exe = Join-Paths $script:WinTempDir 'cygwin-installer.exe'
    if (-not(Test-Path -Path $exe -PathType Leaf)) {
        Write-Host "Downloading Cygwin installer..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri 'https://cygwin.com/setup-x86_64.exe' -OutFile $exe
    }
    Write-Host "Installing Cygwin..." -ForegroundColor Cyan
    $packageDir = Join-Paths $script:WinTempDir 'cygwin-packages'
    if ($script:Bitness -eq 32) {
        $mingwArchitecture = 'i686'
    } else {
        $mingwArchitecture = 'x86_64'
    }
    $packages = "file,make,unzip,dos2unix,patch,mingw64-$mingwArchitecture-gcc-core,mingw64-$mingwArchitecture-gcc-g++,mingw64-$mingwArchitecture-headers,mingw64-$mingwArchitecture-runtime,cmake,gdb"
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
    $bashProfilePath = Join-Paths $homeDir '.bash_profile'
    $bashProfileContent = @(
        'source "${HOME}/.bashrc"',
        "PATH=$($script:CygInstalledDir):/usr/$($script:MingWHost)/bin:/usr/$($script:MingWHost)/sys-root/mingw/bin:/usr/sbin:/usr/bin:/sbin:/bin:/cygdrive/c/Windows/System32:/cygdrive/c/Windows",
        'export PATH',
        ''
    ) -join "`n"
    [System.IO.File]::WriteAllText($bashProfilePath, $bashProfileContent)
}

function Install-Iconv {
    Initialize-Paths
    $winSrcDir = Join-Paths $script:WinSrcDir "libiconv-$($script:IconvVersion)"
    if (-not(Test-Path -Path $winSrcDir -PathType Container)) {
        $winTarball = Join-Paths $script:WinTempDir "libiconv-$($script:IconvVersion).tar.gz"
        if (-not(Test-Path -Path $winTarball -PathType Leaf)) {
            Write-Host "Downloading iconv tarball..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri "https://ftp.gnu.org/pub/gnu/libiconv/libiconv-$($script:IconvVersion).tar.gz" -OutFile $winTarball
        }
        Write-Host "Extracting iconv tarball..." -ForegroundColor Cyan
        $cygTarball = ConvertTo-CygwinPath $winTarball
        Invoke-Bash -WindowsPath $script:WinSrcDir -Command "tar -xzf '$cygTarball'"
        Invoke-PatchSource "libiconv-$($script:IconvVersion)"
    }
    $winBuildDir = Join-Paths $winSrcDir 'build'
    if (Test-Path -Path $winBuildDir -PathType Container) {
        Remove-Item -Path $winBuildDir -Recurse -Force
    }
    New-Item -Path $winBuildDir -ItemType Directory | Out-Null
    if ($script:DebugMode) {
        $flags='-g -O0'
    } else {
        $flags='-g0 -O2'
    }
    Write-Host "Configuring iconv $IconvVersion..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $winBuildDir -Command $(@(
        '../configure',
        "CC='$($script:MingWHost)-gcc'",
        "CXX='$($script:MingWHost)-g++'",
        "LD='$($script:MingWHost)-ld'",
        "STRIP='$($script:MingWHost)-strip'",
        "CPPFLAGS='-I$($script:CygInstalledDir)/include -I/usr/$($script:MingWHost)/sys-root/mingw/include -DWINVER=0x0601 -D_WIN32_WINNT=0x0601'",
        "CFLAGS='$($flags)'",
        "CXXFLAGS='$($flags) -fno-threadsafe-statics'",
        "LDFLAGS='-L$($script:CygInstalledDir)/lib -L/usr/$($script:MingWHost)/sys-root/mingw/lib'",
        "--host=$($script:MingWHost)",
        '--enable-relocatable',
        '--config-cache',
        '--disable-dependency-tracking',
        '--enable-nls',
        '--disable-rpath',
        '--disable-acl',
        '--enable-threads=windows',
        "--prefix=$($script:CygInstalledDir)",
        $(if ($script:Link -eq 'static') { '--enable-static' } else { '--enable-shared' }),
        $(if ($script:Link -eq 'static') { '--disable-shared' } else { '--disable-static' }),
        '--enable-extra-encodings'
    ) -join ' ')
    Write-Host "Building iconv $IconvVersion..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $winBuildDir -Command 'make'
    Write-Host "Installing iconv $IconvVersion..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $winBuildDir -Command 'make install'
}

function Install-JsonC {
    Initialize-Paths
    $winSrcDir = Join-Paths $script:WinSrcDir "json-c-$($script:JsonCVersion)"
    if (-not(Test-Path -Path $winSrcDir -PathType Container)) {
        $winTarball = Join-Paths $script:WinTempDir "json-c-$($script:JsonCVersion).tar.gz"
        if (-not(Test-Path -Path $winTarball -PathType Leaf)) {
            Write-Host "Downloading json-c tarball..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri "https://s3.amazonaws.com/json-c_releases/releases/json-c-$($script:JsonCVersion)-nodoc.tar.gz" -OutFile $winTarball
        }
        Write-Host "Extracting json-c tarball..." -ForegroundColor Cyan
        $cygTarball = ConvertTo-CygwinPath $winTarball
        Invoke-Bash -WindowsPath $script:WinSrcDir -Command "tar -xzf '$cygTarball'"
        Invoke-PatchSource "json-c-$($script:JsonCVersion)"
    }
    $winBuildDir = Join-Paths $winSrcDir 'build'
    if (Test-Path -Path $winBuildDir -PathType Container) {
        Remove-Item -Path $winBuildDir -Recurse -Force
    }
    New-Item -Path $winBuildDir -ItemType Directory | Out-Null
    if ($script:DebugMode) {
        $flags = '-g -O0'
        $buildType = 'Debug'
    } else {
        $flags = '-g0 -O2'
        $buildType = 'Release'
    }
    Write-Host "Configuring json-c $($script:JsonCVersion)..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $winBuildDir -Command $(@(
        'cmake',
        "-DCMAKE_BUILD_TYPE=$buildType",
        "'-DCMAKE_INSTALL_PREFIX=$($script:CygInstalledDir)'",
        '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
        '-DBUILD_TESTING=OFF',
        "-DCMAKE_C_COMPILER=$($script:MingWHost)-gcc",
        "-DCMAKE_C_FLAGS='$flags'",
        '-DDISABLE_THREAD_LOCAL_STORAGE=ON',
        '-DENABLE_THREADING=OFF',
        $(if ($script:Link -eq 'static') { '-DBUILD_STATIC_LIBS=ON' } else { '-DBUILD_SHARED_LIBS=ON' }),
        $(if ($script:Link -eq 'static') { '-DBUILD_SHARED_LIBS=OFF' } else { '-DBUILD_STATIC_LIBS=OFF' }),
        '../'
    ) -join ' ')
    Write-Host "Building json-c $($script:JsonCVersion)..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $winBuildDir -Command "make --jobs=$([System.Environment]::ProcessorCount) all"
    Write-Host "Installing json-c $($script:JsonCVersion)..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $winBuildDir -Command 'make install'
}

function Install-Curl {
    Initialize-Paths
    $winSrcDir = Join-Paths $script:WinSrcDir "curl-$($script:CurlVersion)"
    if (-not(Test-Path -Path $winSrcDir -PathType Container)) {
        $winTarball = Join-Paths $script:WinTempDir "curl-$($script:CurlVersion).tar.gz"
        if (-not(Test-Path -Path $winTarball -PathType Leaf)) {
            Write-Host "Downloading curl tarball..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri "https://curl.se/download/curl-$($script:CurlVersion).tar.gz" -OutFile $winTarball
        }
        Write-Host "Extracting curl tarball..." -ForegroundColor Cyan
        $cygTarball = ConvertTo-CygwinPath $winTarball
        Invoke-Bash -WindowsPath $script:WinSrcDir -Command "tar -xzf '$cygTarball'"
        Invoke-PatchSource "curl-$($script:CurlVersion)"
    }
    $winBuildDir = Join-Paths $winSrcDir 'build'
    if (Test-Path -Path $winBuildDir -PathType Container) {
        Remove-Item -Path $winBuildDir -Recurse -Force
    }
    New-Item -Path $winBuildDir -ItemType Directory | Out-Null
    if ($script:DebugMode) {
        $flags='-g -O0'
    } else {
        $flags='-g0 -O2'
    }
    Write-Host "Configuring curl $($script:CurlVersion)..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $winBuildDir -Command $(@(
        '../configure',
        "CC='$($script:MingWHost)-gcc'",
        "CXX='$($script:MingWHost)-g++'",
        "LD='$($script:MingWHost)-ld'",
        "STRIP='$($script:MingWHost)-strip'",
        "CPPFLAGS='-I$($script:CygInstalledDir)/include -I/usr/$($script:MingWHost)/sys-root/mingw/include -DWINVER=0x0601 -D_WIN32_WINNT=0x0601'",
        "CFLAGS='$($flags)'",
        "CXXFLAGS='$($flags)'",
        "LDFLAGS='-L$($script:CygInstalledDir)/lib -L/usr/$($script:MingWHost)/sys-root/mingw/lib'",
        "--host=$($script:MingWHost)",
        '--enable-http',
        '--disable-ftp',
        '--enable-file',
        '--disable-ldap',
        '--disable-ldaps',
        '--disable-rtsp',
        '--enable-proxy',
        '--disable-ipfs',
        '--disable-dict',
        '--disable-telnet',
        '--disable-tftp',
        '--disable-pop3',
        '--disable-imap',
        '--disable-smb',
        '--disable-smtp',
        '--disable-gopher',
        '--disable-mqtt',
        '--disable-manual',
        '--disable-docs',
        '--enable-ipv6',
        '--enable-windows-unicode',
        '--disable-cookies',
        '--with-schannel',
        '--without-gnutls',
        '--without-openssl',
        '--without-rustls',
        '--without-wolfssl',
        '--without-libpsl',
        '--with-winidn',
        '--disable-threaded-resolver',
        '--disable-kerberos-auth',
        '--disable-ntlm',
        '--disable-negotiate-auth',
        '--disable-sspi',
        '--disable-unix-sockets',
        '--disable-dependency-tracking',
        "--prefix=$($script:CygInstalledDir)",
        $(if ($script:Link -eq 'static') { '--enable-static' } else { '--enable-shared' }),
        $(if ($script:Link -eq 'static') { '--disable-shared' } else { '--disable-static' })
    ) -join ' ')
    Write-Host "Static libraries to be included into gettext:" -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $winBuildDir -Command './curl-config --static-libs'
    Write-Host "curl features:" -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $winBuildDir -Command './curl-config --features'
    Write-Host "Building curl $($script:CurlVersion) - lib..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $(Join-Paths $winBuildDir 'lib') -Command "make --jobs=$([System.Environment]::ProcessorCount)"
    Write-Host "Installing curl $($script:CurlVersion) - lib..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $(Join-Paths $winBuildDir 'lib') -Command 'make install'
    Write-Host "Building curl $($script:CurlVersion) - include..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $(Join-Paths $winBuildDir 'include') -Command "make --jobs=$([System.Environment]::ProcessorCount)"
    Write-Host "Installing curl $($script:CurlVersion) - include..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $(Join-Paths $winBuildDir 'include') -Command 'make install'
}

function Install-Gettext {
    Initialize-Paths
    $winSrcDir = Join-Paths $script:WinSrcDir "gettext-$($script:GettextVersion)"
    if (-not(Test-Path -Path $winSrcDir -PathType Container)) {
        $winTarball = Join-Paths $script:WinTempDir "gettext-$($script:GettextVersion).tar.gz"
        if (-not(Test-Path -Path $winTarball -PathType Leaf)) {
            Write-Host "Downloading gettext tarball..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri "https://ftp.gnu.org/pub/gnu/gettext/gettext-$($script:GettextVersion).tar.gz" -OutFile $winTarball
        }
        Write-Host "Extracting gettext tarball..." -ForegroundColor Cyan
        $cygTarball = ConvertTo-CygwinPath $winTarball
        Invoke-Bash -WindowsPath $script:WinSrcDir -Command "tar -xzf '$cygTarball'"
        Invoke-PatchSource "gettext-$($script:GettextVersion)"
    }
    $winBuildDir = Join-Paths $winSrcDir 'build'
    if (Test-Path -Path $winBuildDir -PathType Container) {
        Remove-Item -Path $winBuildDir -Recurse -Force
    }
    New-Item -Path $winBuildDir -ItemType Directory | Out-Null
    if ($script:DebugMode) {
        $flags='-g -O0'
    } else {
        $flags='-g0 -O2'
    }
    $libs = ''
    if (-not($script:GettextVersion.StartsWith('0.'))) {
        $flags += ' -DCURL_STATICLIB'
        $libs = Invoke-Bash -WindowsPath $(Join-Paths $script:WinSrcDir "curl-$($script:CurlVersion)" 'build') -Command './curl-config --static-libs' -CaptureOutput $true
    }
    Write-Host "Configuring gettext $GettextVersion..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $winBuildDir -Command $(@(
        '../configure',
        "LIBS='$libs'",
        "CC='$($script:MingWHost)-gcc'",
        "CXX='$($script:MingWHost)-g++'",
        "LD='$($script:MingWHost)-ld'",
        "STRIP='$($script:MingWHost)-strip'",
        "CPPFLAGS='-I$($script:CygInstalledDir)/include -I/usr/$($script:MingWHost)/sys-root/mingw/include -DWINVER=0x0601 -D_WIN32_WINNT=0x0601'",
        "CFLAGS='$($flags)'",
        "CXXFLAGS='$($flags) -fno-threadsafe-statics'",
        "LDFLAGS='-L$($script:CygInstalledDir)/lib -L/usr/$($script:MingWHost)/sys-root/mingw/lib'",
        "--host=$($script:MingWHost)",
        '--enable-relocatable',
        '--config-cache',
        '--disable-dependency-tracking',
        '--enable-nls',
        '--disable-rpath',
        '--disable-acl',
        '--enable-threads=windows',
        "--prefix=$($script:CygInstalledDir)",
        '--disable-java',
        '--disable-native-java',
        '--disable-openmp',
        '--disable-curses',
        '--disable-csharp',
        '--without-emacs',
        '--with-included-libxml',
        '--without-bzip2',
        '--without-xz',
        '--disable-csharp',
        $(if ($script:Link -eq 'static') { '--enable-static' } else { '--enable-shared' }),
        $(if ($script:Link -eq 'static') { '--disable-shared' } else { '--disable-static' })

    ) -join ' ')
    Write-Host "Building gettext/gnulib-local $GettextVersion..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $(Join-Paths $winBuildDir 'gnulib-local')  -Command 'make'
    Write-Host "Installing gettext/gnulib-local $GettextVersion..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $(Join-Paths $winBuildDir 'gnulib-local')  -Command 'make install'
    Write-Host "Building gettext/gettext-runtime $GettextVersion..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $(Join-Paths $winBuildDir 'gettext-runtime')  -Command 'make'
    Write-Host "Installing gettext/gettext-runtime $GettextVersion..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $(Join-Paths $winBuildDir 'gettext-runtime')  -Command 'make install'
    Write-Host "Building gettext/libtextstyle $GettextVersion..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $(Join-Paths $winBuildDir 'libtextstyle')  -Command 'make'
    Write-Host "Installing gettext/libtextstyle $GettextVersion..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $(Join-Paths $winBuildDir 'libtextstyle')  -Command 'make install'
    Write-Host "Building gettext/gettext-tools $GettextVersion..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $(Join-Paths $winBuildDir 'gettext-tools')  -Command 'make'
    Write-Host "Installing gettext/gettext-tools $GettextVersion..." -ForegroundColor Cyan
    Invoke-Bash -WindowsPath $(Join-Paths $winBuildDir 'gettext-tools')  -Command 'make install'
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
    $patchesDir = Join-Paths $PSScriptRoot 'patches' $DirName
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
        $winSrcDir = Join-Paths $script:WinSrcDir $DirName
        Invoke-Bash -WindowsPath $winSrcDir -Command "patch -p1 < '$cygPatch'"
    }
}

function Join-Paths {
    param(
        [Parameter(Mandatory, ValueFromRemainingArguments)]
        [string[]] $Paths
    )

    [System.IO.Path]::Combine($Paths)
}

function Set-Enviro {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(32, 64)]
        [int] $Bitness,
        [Parameter(Mandatory = $true)]
        [ValidateSet('static', 'shared')]
        [string] $Link
    )
    $script:Bitness = $Bitness
    $script:Link = $Link
    if ($Bitness -eq 32) {
        $script:MingWHost = 'i686-w64-mingw32'
    } else {
        $script:MingWHost = 'x86_64-w64-mingw32'
    }
    $script:CygwinPath = "D:\cygwin$Bitness"
    $script:WinSrcDir = Join-Paths $PSScriptRoot "$Bitness-$Link" 'src'
    $script:CygSrcDir = ConvertTo-CygwinPath $script:WinSrcDir
    $script:WinInstalledDir = Join-Paths $PSScriptRoot "$Bitness-$Link" 'installed'
    $script:CygInstalledDir = ConvertTo-CygwinPath $script:WinInstalledDir
}

$env:CHERE_INVOKING = '1'
$env:CYGWIN_NOWINPATH = '1'

$script:IconvVersion = '1.17'
$script:CurlVersion = '8.18.0'
$script:JsonCVersion = '0.18'
$script:GettextVersion = '1.0-pre2'
$script:DebugMode = $true
$script:WinTempDir = Join-Paths $PSScriptRoot 'temp'
$script:CygTempDir = ConvertTo-CygwinPath $script:WinTempDir

Set-Enviro -Bitness 64 -Link 'shared'

Show-Menu
