Set-StrictMode -Version Latest
$script:ErrorActionPreference = 'Stop'
$script:ProgressPreference = 'SilentlyContinue'

function Show-Menu {
    Write-Host '=== Menu ===' -ForegroundColor Green
    Write-Host '0. Install cygwin'
    Write-Host '1. Reset'
    Write-Host '2. Install iconv'
    Write-Host '3. Install curl'
    Write-Host '4. Install json-c'
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
                Install-Curl
            }
            '4' {
                Install-JsonC
            }
            '5' {
                Install-Gettext
            }
            '6' { 
                Install-Iconv
                if (-not($script:GettextVersion.StartsWith('0.'))) {
                    Install-Curl
                    Install-JsonC
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
                Set-Enviro -Bitness 32 -Link $script:Link -DebugMode (-not $script:DebugMode)
            }
            'D' {
                Set-Enviro -Bitness $(if ($script:Bitness -eq 64) { 32 } else { 64 }) -Link $script:Link -DebugMode $script:DebugMode
            }
            'E' {
                Set-Enviro -Bitness $script:Bitness -Link $(if ($script:Link -eq 'static') { 'shared' } else { 'static' }) -DebugMode $script:DebugMode
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
    Write-Section 'Resetting sources and installed files'
    Write-SectionStep 'Removing installed files'
    if (Test-Path -Path $script:WinInstalledDir -PathType Container) {
        Remove-Item -Path $script:WinInstalledDir -Recurse -Force
    }
    Write-SectionStep 'Removing source files'
    if (Test-Path -Path $script:WinSrcDir -PathType Container) {
        Remove-Item -Path $script:WinSrcDir -Recurse -Force
    }
}

function Install-Cygwin {
    Write-Section 'Installing Cygwin'
    Initialize-Paths
    $exe = Join-Paths $script:WinTempDir 'cygwin-installer.exe'
    if (-not(Test-Path -Path $exe -PathType Leaf)) {
        Write-SectionStep 'Downloading Cygwin installer'
        Invoke-WebRequest -Uri 'https://cygwin.com/setup-x86_64.exe' -OutFile $exe
    }
    Write-SectionStep 'Determining Cygwin configuration'
    $packageDir = Join-Paths $script:WinTempDir 'cygwin-packages'
    $packages = @(
        'file',
        'make',
        'unzip',
        'dos2unix',
        'patch',
        'cmake',
        # Required for building curl with --enable-debug
        'perl', 
        # Required for debugging
        'gdb'
    );
    foreach ($mingwArchitecture in @('i686', 'x86_64')) {
        $packages += "mingw64-$mingwArchitecture-gcc-core"
        $packages += "mingw64-$mingwArchitecture-gcc-g++"
        $packages += "mingw64-$mingwArchitecture-headers"
        $packages += "mingw64-$mingwArchitecture-runtime"
    }
    $argumentList = @(
        '-qnO',
        '-l', $packageDir,
        '-R', $script:CygwinPath,
        '-s', 'http://mirrors.kernel.org/sourceware/cygwin/',
        '-P', $($packages -join ',')
    )
    Write-SectionStep 'Installing Cygwin'
    $proc = Start-Process -FilePath $exe -ArgumentList $argumentList -Wait -PassThru
    $exitCode = $proc.ExitCode
    if ($exitCode -ne 0) {
        throw "Cygwin installation failed with exit code $exitCode"
    }
    Write-SectionStep 'Configuring Cygwin'
    Invoke-Bash -WindowsPath $script:CygwinPath -Command "exit"
    Update-CygwinEnvironment
}

function Update-CygwinEnvironment {
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
        "PATH=$($script:CygInstalledDir)/bin:/usr/$($script:MingWHost)/bin:/usr/$($script:MingWHost)/sys-root/mingw/bin:/usr/sbin:/usr/bin:/sbin:/bin:/cygdrive/c/Windows/System32:/cygdrive/c/Windows",
        'export PATH',
        ''
    ) -join "`n"
    [System.IO.File]::WriteAllText($bashProfilePath, $bashProfileContent)
}

function Install-Iconv {
    Write-Section "Installing iconv $($script:IconvVersion)"
    Initialize-Paths
    $winSrcDir = Join-Paths $script:WinSrcDir "libiconv-$($script:IconvVersion)"
    if (-not(Test-Path -Path $winSrcDir -PathType Container)) {
        $winTarball = Join-Paths $script:WinTempDir "libiconv-$($script:IconvVersion).tar.gz"
        if (-not(Test-Path -Path $winTarball -PathType Leaf)) {
            Write-SectionStep 'Downloading iconv tarball'
            if ($script:IconvVersion -match 'alpha|pre|rc') {
                $url = "https://alpha.gnu.org/gnu/libiconv/libiconv-$($script:IconvVersion).tar.gz"
            } else {
                $url = "https://ftp.gnu.org/pub/gnu/libiconv/libiconv-$($script:IconvVersion).tar.gz"
            }
            Invoke-WebRequest -Uri $url -OutFile $winTarball
        }
        Write-SectionStep 'Extracting iconv tarball'
        $cygTarball = ConvertTo-CygwinPath $winTarball
        Invoke-Bash -WindowsPath $script:WinSrcDir -Command "tar -xzf '$cygTarball'"
        Invoke-PatchSource "libiconv-$($script:IconvVersion)"
    }
    Write-SectionStep 'Configuring iconv'
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
    if ($script:Bitness -eq 32 -and $script:Link -eq 'shared') {
        $ldFlags = '-static-libgcc'
    } else {
        $ldFlags = ''
    }
    Invoke-Bash -WindowsPath $winBuildDir -Command $(@(
        '../configure',
        "CC='$($script:MingWHost)-gcc'",
        "CXX='$($script:MingWHost)-g++'",
        "LD='$($script:MingWHost)-ld'",
        "STRIP='$($script:MingWHost)-strip'",
        "CPPFLAGS='-I$($script:CygInstalledDir)/include -I/usr/$($script:MingWHost)/sys-root/mingw/include -DWINVER=0x0601 -D_WIN32_WINNT=0x0601'",
        "CFLAGS='$($flags)'",
        "CXXFLAGS='$($flags) -fno-exceptions -fno-rtti'",
        "LDFLAGS='-L$($script:CygInstalledDir)/lib -L/usr/$($script:MingWHost)/sys-root/mingw/lib $ldFlags'",
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
        $(if ($script:Link -eq 'static') { '--disable-shared' } else { '--disable-static' }
    )) -join ' ')
    Write-SectionStep 'Building iconv'
    Invoke-Bash -WindowsPath $winBuildDir -Command 'make'
    Write-SectionStep 'Installing iconv'
    Invoke-Bash -WindowsPath $winBuildDir -Command "make $(if ($script:DebugMode) { 'install' } else { 'install-strip' })"
    Write-SectionStep 'Done with iconv'
}

function Install-Curl {
    Write-Section "Installing curl $($script:CurlVersion)"
    Initialize-Paths
    $winSrcDir = Join-Paths $script:WinSrcDir "curl-$($script:CurlVersion)"
    if (-not(Test-Path -Path $winSrcDir -PathType Container)) {
        $winTarball = Join-Paths $script:WinTempDir "curl-$($script:CurlVersion).tar.gz"
        if (-not(Test-Path -Path $winTarball -PathType Leaf)) {
            Write-SectionStep 'Downloading curl tarball'
            Invoke-WebRequest -Uri "https://curl.se/download/curl-$($script:CurlVersion).tar.gz" -OutFile $winTarball
        }
        Write-SectionStep 'Extracting curl tarball'
        $cygTarball = ConvertTo-CygwinPath $winTarball
        Invoke-Bash -WindowsPath $script:WinSrcDir -Command "tar -xzf '$cygTarball'"
        Invoke-PatchSource "curl-$($script:CurlVersion)"
    }
    Write-SectionStep 'Configuring curl'
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
    if ($script:Bitness -eq 32 -and $script:Link -eq 'shared') {
        $ldFlags = '-static-libgcc'
    } else {
        $ldFlags = ''
    }
    Invoke-Bash -WindowsPath $winBuildDir -Command $(@(
        '../configure',
        "CC='$($script:MingWHost)-gcc'",
        "CXX='$($script:MingWHost)-g++'",
        "LD='$($script:MingWHost)-ld'",
        "STRIP='$($script:MingWHost)-strip'",
        "CPPFLAGS='-I$($script:CygInstalledDir)/include -I/usr/$($script:MingWHost)/sys-root/mingw/include -DWINVER=0x0601 -D_WIN32_WINNT=0x0601'",
        "CFLAGS='$($flags)'",
        "CXXFLAGS='$($flags) -fno-exceptions -fno-rtti'",
        "LDFLAGS='-L$($script:CygInstalledDir)/lib -L/usr/$($script:MingWHost)/sys-root/mingw/lib $ldFlags'",
        "--host=$($script:MingWHost)",
        '--enable-http',
        '--disable-file',
        '--disable-ftp',
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
        '--disable-websockets',
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
        $(if ($script:Link -eq 'static') { '--disable-shared' } else { '--disable-static' }),
        $(if ($script:DebugMode) { '--enable-debug' } else { '--disable-debug' })
    ) -join ' ')
    Write-SectionStep 'Libraries to be included into gettext'
    Invoke-Bash -WindowsPath $winBuildDir -Command "./curl-config $(if ($script:Link -eq 'static') { '--static-libs' } else { '--libs' })" -NoWriteCommand
    Write-SectionStep 'curl features:'
    Invoke-Bash -WindowsPath $winBuildDir -Command './curl-config --features' -NoWriteCommand
    Write-SectionStep 'Building libcurl'
    Invoke-Bash -WindowsPath $(Join-Paths $winBuildDir 'lib') -Command "make --jobs=$([System.Environment]::ProcessorCount)"
    Write-SectionStep 'Installing libcurl'
    Invoke-Bash -WindowsPath $(Join-Paths $winBuildDir 'lib') -Command "make $(if ($script:DebugMode) { 'install' } else { 'install-strip' })"
    Write-SectionStep 'Building include files'
    Invoke-Bash -WindowsPath $(Join-Paths $winBuildDir 'include') -Command "make --jobs=$([System.Environment]::ProcessorCount)"
    Write-SectionStep 'Installing include files'
    Invoke-Bash -WindowsPath $(Join-Paths $winBuildDir 'include') -Command "make $(if ($script:DebugMode) { 'install' } else { 'install-strip' })"
    Write-SectionStep 'Done with curl'
}

function Install-JsonC {
    Write-Section "Installing json-c $($script:JsonCVersion)"
    Initialize-Paths
    $winSrcDir = Join-Paths $script:WinSrcDir "json-c-$($script:JsonCVersion)"
    if (-not(Test-Path -Path $winSrcDir -PathType Container)) {
        $winTarball = Join-Paths $script:WinTempDir "json-c-$($script:JsonCVersion).tar.gz"
        if (-not(Test-Path -Path $winTarball -PathType Leaf)) {
            Write-SectionStep 'Downloading json-c tarball'
            Invoke-WebRequest -Uri "https://s3.amazonaws.com/json-c_releases/releases/json-c-$($script:JsonCVersion)-nodoc.tar.gz" -OutFile $winTarball
        }
        Write-SectionStep 'Extracting json-c tarball'
        $cygTarball = ConvertTo-CygwinPath $winTarball
        Invoke-Bash -WindowsPath $script:WinSrcDir -Command "tar -xzf '$cygTarball'"
        Invoke-PatchSource "json-c-$($script:JsonCVersion)"
    }
    Write-SectionStep 'Configuring json-c'
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
    if ($script:Bitness -eq 32 -and $script:Link -eq 'shared') {
        $ldFlags = '-static-libgcc'
    } else {
        $ldFlags = ''
    }
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
        '-DBUILD_APPS=OFF',
        '-DCMAKE_SYSTEM_NAME=Windows',
        "-DCMAKE_CXX_FLAGS='$flags -fno-exceptions -fno-rtti'",
        "-DCMAKE_SHARED_LINKER_FLAGS='$ldFlags'"
        $(if ($script:Link -eq 'static') { '-DBUILD_STATIC_LIBS=ON' } else { '-DBUILD_SHARED_LIBS=ON' }),
        $(if ($script:Link -eq 'static') { '-DBUILD_SHARED_LIBS=OFF' } else { '-DBUILD_STATIC_LIBS=OFF' }),
        '../'
    ) -join ' ')
    Write-SectionStep 'Building json-c'
    Invoke-Bash -WindowsPath $winBuildDir -Command "make --jobs=$([System.Environment]::ProcessorCount) all"
    Write-SectionStep 'Installing json-c'
    Invoke-Bash -WindowsPath $winBuildDir -Command "make $(if ($script:DebugMode) { 'install' } else { 'install/strip' })"
    Write-SectionStep 'Done with json-c'
}

function Install-Gettext {
    Write-Section "Installing gettext $($script:GettextVersion)"
    Initialize-Paths
    $winSrcDir = Join-Paths $script:WinSrcDir "gettext-$($script:GettextVersion)"
    if (-not(Test-Path -Path $winSrcDir -PathType Container)) {
        $winTarball = Join-Paths $script:WinTempDir "gettext-$($script:GettextVersion).tar.gz"
        if (-not(Test-Path -Path $winTarball -PathType Leaf)) {
            Write-SectionStep 'Downloading gettext tarball'
            if ($script:GettextVersion -match 'alpha|pre|rc') {
                $url = "https://alpha.gnu.org/gnu/gettext/gettext-$($script:GettextVersion).tar.gz"
            } else {
                $url = "https://ftp.gnu.org/pub/gnu/gettext/gettext-$($script:GettextVersion).tar.gz"
            }
            Invoke-WebRequest -Uri $url -OutFile $winTarball
        }
        Write-SectionStep 'Extracting gettext tarball'
        $cygTarball = ConvertTo-CygwinPath $winTarball
        Invoke-Bash -WindowsPath $script:WinSrcDir -Command "tar -xzf '$cygTarball'"
        Invoke-PatchSource "gettext-$($script:GettextVersion)"
    }
    Write-SectionStep 'Configuring gettext'
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
    if ($script:Bitness -eq 32 -and $script:Link -eq 'shared') {
        $ldFlags = '-static-libgcc'
    } else {
        $ldFlags = ''
    }
    $libs = ''
    if (-not($script:GettextVersion.StartsWith('0.'))) {
        if ($script:Link -eq 'static') {
            $flags += ' -DCURL_STATICLIB'
            $libs = Invoke-Bash -WindowsPath $(Join-Paths $script:WinSrcDir "curl-$($script:CurlVersion)" 'build') -Command './curl-config --static-libs' -CaptureOutput -NoWriteCommand
        } else {
            $libs = Invoke-Bash -WindowsPath $(Join-Paths $script:WinSrcDir "curl-$($script:CurlVersion)" 'build') -Command './curl-config --libs' -CaptureOutput -NoWriteCommand
        }
    }
    Invoke-Bash -WindowsPath $winBuildDir -Command $(@(
        '../configure',
        "CC='$($script:MingWHost)-gcc'",
        "CXX='$($script:MingWHost)-g++'",
        "LD='$($script:MingWHost)-ld'",
        "STRIP='$($script:MingWHost)-strip'",
        "CPPFLAGS='-I$($script:CygInstalledDir)/include -I/usr/$($script:MingWHost)/sys-root/mingw/include -DWINVER=0x0601 -D_WIN32_WINNT=0x0601'",
        "CFLAGS='$($flags)'",
        "CXXFLAGS='$($flags) -fno-exceptions -fno-rtti'",
        "LDFLAGS='-L$($script:CygInstalledDir)/lib -L/usr/$($script:MingWHost)/sys-root/mingw/lib $ldFlags'",
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
        '--disable-java',
        '--disable-native-java',
        '--disable-openmp',
        '--disable-curses',
        '--without-emacs',
        '--with-included-libxml',
        '--without-bzip2',
        '--without-xz',
        '--disable-csharp',
        "LIBS='$libs'"
    ) -join ' ')
    foreach ($subdir in @('gnulib-local', 'gettext-runtime', 'libtextstyle', 'gettext-tools')) {
        Write-SectionStep "Building gettext/$subdir"
        Invoke-Bash -WindowsPath $(Join-Paths $winBuildDir $subdir)  -Command 'make'
        Write-SectionStep "Installing gettext/$subdir"
        Invoke-Bash -WindowsPath $(Join-Paths $winBuildDir $subdir)  -Command "make $(if ($script:DebugMode) { 'install' } else { 'install-strip' })"
        Write-SectionStep "Done with gettext/$subdir"
    }
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
        [switch] $CaptureOutput,
        [switch] $NoWriteCommand


    )
    $CygwinPath = ConvertTo-CygwinPath $WindowsPath
    if (-not $NoWriteCommand) {
        Write-Host "Running inside $($CygwinPath):`n$Command" -ForegroundColor DarkGray
    }
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
        Write-SectionStep "Applying patch $($patch.Name)"
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

function Write-Section {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text
    )
    $line = '=' * ($Text.Length + 4)
    Write-Host $line -ForegroundColor Yellow -BackgroundColor Blue -NoNewline
    Write-Host ''
    Write-Host "= $Text =" -ForegroundColor Yellow -BackgroundColor Blue -NoNewline
    Write-Host ''
    Write-Host $line -ForegroundColor Yellow -BackgroundColor Blue -NoNewline
    Write-Host ''
}

function Write-SectionStep {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text
    )
    Write-Host "---- $Text ----" -ForegroundColor Yellow -BackgroundColor DarkBlue -NoNewline
    Write-Host ''
}

function Set-Enviro {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(32, 64)]
        [int] $Bitness,
        [Parameter(Mandatory = $true)]
        [ValidateSet('static', 'shared')]
        [string] $Link,
        [Parameter(Mandatory = $true)]
        [bool] $DebugMode
    )
    $script:Bitness = $Bitness
    $script:Link = $Link
    $script:DebugMode = $DebugMode
    if ($Bitness -eq 32) {
        $script:MingWHost = 'i686-w64-mingw32'
    } else {
        $script:MingWHost = 'x86_64-w64-mingw32'
    }
    $script:WinSrcDir = Join-Paths $PSScriptRoot 'w' "$Bitness-$Link-$(if ($DebugMode) { 'debug' } else { 'release' })" 'src'
    $script:CygSrcDir = ConvertTo-CygwinPath $script:WinSrcDir
    $script:WinInstalledDir = Join-Paths $PSScriptRoot 'w' "$Bitness-$Link-$(if ($DebugMode) { 'debug' } else { 'release' })" 'installed'
    $script:CygInstalledDir = ConvertTo-CygwinPath $script:WinInstalledDir
    if (Test-Path -Path $script:CygwinPath -PathType Container) {
        Update-CygwinEnvironment
    }
}

$env:CHERE_INVOKING = '1'
$env:CYGWIN_NOWINPATH = '1'

$script:IconvVersion = '1.17'
$script:CurlVersion = '8.18.0'
$script:JsonCVersion = '0.18'
$script:GettextVersion = '1.0'
$script:CygwinPath = Join-Paths $PSScriptRoot 'cygwin'
$script:WinTempDir = Join-Paths $PSScriptRoot 'temp'
$script:CygTempDir = ConvertTo-CygwinPath $script:WinTempDir

Set-Enviro -Bitness 32 -Link 'shared' -DebugMode $false

Show-Menu
