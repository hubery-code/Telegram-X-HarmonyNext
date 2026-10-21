# tools/native/build-tdlib.ps1 — Windows 上重建 TDLib (libtdjson.so) for HarmonyOS NEXT。
#
# 为什么有这个脚本：`build-tdlib.sh` 是按 macOS 主开发环境写的（bash + `sysctl -n hw.ncpu`
# + `/Applications/DevEco-Studio.app/...` 默认路径），在 Windows 上一步都跑不了。
# 本脚本是它的 PowerShell 等价物，**保持同样的产物路径与同样的编译参数**，这样
# entry 的 CMakeLists 与 BUILD-EVIDENCE.md 都不用改。
#
# 支持两个 ABI：
#   arm64-v8a —— ADR-001 的产线目标（真机）。仓库 `third_party/openssl` 里已有现成的
#                arm64 OpenSSL 产物，所以这条路**不需要重编 OpenSSL**。
#   x86_64    —— 模拟器镜像（HarmonyOS 7.0.0 phone_all_x86）只有 x86_64。
#                要重编 OpenSSL（见 -BuildOpenSsl）。
#
# 前置条件（本机已实测可行的组合）：
#   1. host 编译器：MinGW-w64 g++（`winget install BrechtSanders.WinLibs.POSIX.UCRT`）。
#      用途只有一件 —— 编译 TDLib 的**源码生成器**（tl_generate_common 等）。
#      NDK 的 clang 不能顶替：它没有 Windows 的 C++ 标准库头文件（`<cstdio>` 都找不到）。
#   2. `gperf`（`winget install oss-winget.gperf`）：tdutils 的 Hints 表生成器。
#   3. cmake + ninja：可用 WinLibs 自带的，也可用 NDK 的 build-tools。
#   4. 只有 `-BuildOpenSsl` 时才需要 perl（`winget install StrawberryPerl.StrawberryPerl`）
#      + make（WinLibs 的 mingw32-make 即可）+ ar（MSYS2 的 binutils）。
#
# 用法：
#   pwsh tools/native/build-tdlib.ps1                      # arm64-v8a（用现成 OpenSSL）
#   pwsh tools/native/build-tdlib.ps1 -Abi x86_64 -BuildOpenSsl   # 模拟器用
#   pwsh tools/native/build-tdlib.ps1 -Clean               # 清掉该 ABI 的 build 目录重来
#
# 完整踩坑记录见 docs/runbooks/tdlib-native-build-windows.md。
param(
    [ValidateSet('arm64-v8a', 'x86_64')]
    [string]$Abi = 'arm64-v8a',
    [switch]$Clean,
    [switch]$BuildOpenSsl
)

$ErrorActionPreference = 'Stop'
$ROOT = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$TDCORE = Join-Path $ROOT 'native\tdcore'
$SRC = Join-Path $TDCORE 'third_party\td'
$BUILD_DIR = Join-Path $TDCORE "build\$Abi"
$HOST_GEN_DIR = Join-Path $TDCORE 'build\host-generate'
$OPENSSL_SRC = Join-Path $TDCORE 'third_party\openssl'
$DEPS_SSL = Join-Path $TDCORE "build\deps\openssl\$Abi"
$NDK = if ($env:TDX_OHOS_NDK) { $env:TDX_OHOS_NDK } else { 'D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native' }

function Write-Step($msg) { Write-Host "== [build-tdlib:$Abi] $msg" }

# --- 0. 前置检查 -------------------------------------------------------------
if (-not (Test-Path (Join-Path $NDK 'build\cmake\ohos.toolchain.cmake'))) {
    throw "OHOS NDK toolchain 不存在于 $NDK（用 `$env:TDX_OHOS_NDK 指定）"
}
if (-not (Test-Path (Join-Path $SRC 'CMakeLists.txt'))) { throw "TDLib 源码缺失：$SRC" }
foreach ($tool in @('g++', 'gperf', 'cmake', 'ninja')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "缺少 host 工具 $tool。见脚本头部的前置条件。"
    }
}

# --- 1. OpenSSL --------------------------------------------------------------
# arm64 的产物随仓库而来（third_party/openssl 里就是 arm64 的 libcrypto.so.3）。
# x86_64 必须现编，因为仓库里没有 x86 版本。
if ($Abi -eq 'arm64-v8a' -and -not $BuildOpenSsl) {
    $sslReal = Join-Path $OPENSSL_SRC 'libcrypto.so.3'
    if (-not (Test-Path $sslReal)) { throw "arm64 OpenSSL 产物缺失：$sslReal" }
    # 幂等：目录可能已经存在但内容不全（例如上一轮构建到一半中断），
    # 所以按**文件**判断而不是按目录判断。
    if (-not (Test-Path (Join-Path $DEPS_SSL 'lib\libcrypto.so.3'))) {
        Write-Step "stage OpenSSL prefix at $DEPS_SSL"
        New-Item -ItemType Directory -Force -Path (Join-Path $DEPS_SSL 'lib') | Out-Null
        foreach ($f in @('libcrypto.so.3', 'libssl.so.3', 'libcrypto.a', 'libssl.a')) {
            $s = Join-Path $OPENSSL_SRC $f
            if (Test-Path $s) { Copy-Item $s (Join-Path $DEPS_SSL "lib\$f") -Force }
        }
        Copy-Item (Join-Path $OPENSSL_SRC 'include') $DEPS_SSL -Recurse -Force
    }
    # 关键：TDLib 的 CMake 直接把 **third_party/openssl** 当 OPENSSL_ROOT_DIR 用
    # （见下面 -DOPENSSL_ROOT_DIR），链接时找的是那里的 libssl.so / libcrypto.so，
    # 不是 deps/ 里的副本。两处都要修，否则 ninja 报 `libssl.so:1: unexpected EOF`。
    $sslDirsForSymlink = @($DEPS_SSL, $OPENSSL_SRC)
} else {
    # 从源码编 OpenSSL。这条路在 Windows 上踩过五个坑，全部在这里处理：
    # ① Strawberry Perl 的 `rel2abs` 产出反斜杠，Configurations/unix-checker.pm 直接 die
    #    （"doesn't produce Unix like paths"）。**不要改那个 .pm** —— 官方留了开关
    #    CONFIGURE_CHECKER_WARN=1，把 checkers 从 die 降级为 warn。
    # ② NDK 路径含空格（`D:\Program Files\...`），OpenSSL 的 Makefile 不给 CC 加引号，
    #    shell 按空格切开后报 `/d/Program: No such file or directory`。
    #    解法是用 8.3 短路径（PROGRA~1 那种），见下面的 Get-ShortPath。
    # ③ x86_64 的 `.s` 汇编里有 `.section .note.gnu.property`（GNU as 语法），
    #    NDK clang 的集成汇编器不认。解法是 `no-asm` —— 只是性能优化，不影响正确性。
    # ④ `ar` 来自 MSYS2 的 binutils，WinLibs 的 mingw32-make 环境里没有。
    # ⑤ linux-x86_64 默认装到 lib64/，而 napibridge 取 lib/ —— 装完做一次镜像。
    $perl = Get-Command perl -ErrorAction SilentlyContinue
    if (-not $perl) { throw "编 OpenSSL 需要 perl：winget install StrawberryPerl.StrawberryPerl" }

    # 用 MSYS2 的 bash 跑（Unix shell 语法 + 完整 perl + make + ar）。
    $msysBash = 'C:\msys64\usr\bin\bash.exe'
    if (-not (Test-Path $msysBash)) {
        throw "编 OpenSSL 需要 MSYS2：winget install MSYS2.MSYS2，然后 pacman -Sy --noconfirm make binutils"
    }

    $target = if ($Abi -eq 'arm64-v8a') { 'linux-aarch64' } else { 'linux-x86_64' }
    $triple = if ($Abi -eq 'arm64-v8a') { 'aarch64-linux-ohos' } else { 'x86_64-linux-ohos' }

    # 8.3 短路径：消掉路径里的空格（坑 ②）。
    $fso = New-Object -ComObject Scripting.FileSystemObject
    $ndkShort = $fso.GetFolder($NDK).ShortPath -replace '\\', '/'
    $ndkShort = "/" + $ndkShort.Substring(0, 1).ToLower() + $ndkShort.Substring(2)
    $sslShort = $fso.GetFolder($OPENSSL_SRC).ShortPath -replace '\\', '/'
    $sslShort = "/" + $sslShort.Substring(0, 1).ToLower() + $sslShort.Substring(2)
    $installShort = $DEPS_SSL -replace '\\', '/'
    $installShort = "/" + $installShort.Substring(0, 1).ToLower() + $installShort.Substring(2)

    # no-asm 只在 x86_64 需要（坑 ③）；arm64 的汇编走 GNU 兼容路径，能过。
    $asmFlag = if ($Abi -eq 'x86_64') { 'no-asm' } else { '' }

    Write-Step "build OpenSSL: $target -> $triple (via MSYS2)"

    # 关键：**不要把构建产物写进 third_party/openssl**。
    # 那个目录在 git 里被跟踪了 1617 个 `.o`（macOS 上编出来的 **arm64** 目标文件，
    # 属于历史误提交）。原地 `make` 会复用它们，于是编 x86_64 时链接器报
    # `libdefault-lib-pbkdf2_fips.o is incompatible with elf_x86_64` —— 报错指向单个
    # .o，根因却是「源码树里躺着另一个 ABI 的产物」。
    # 解法：把源码复制到 build/openssl-src-<abi> 再编，源码树只读。
    $sslWork = Join-Path $TDCORE "build\openssl-src-$Abi"
    if ($Clean -or -not (Test-Path (Join-Path $sslWork 'Configure'))) {
        Write-Step "stage OpenSSL sources -> $sslWork"
        if (Test-Path $sslWork) { Remove-Item -Recurse -Force $sslWork }
        New-Item -ItemType Directory -Force -Path $sslWork | Out-Null
        # 只复制构建需要的部分（apps/test/doc 已在 Configure 里 no-apps/no-tests/no-docs 关掉，
        # 但 Configure 仍会扫目录，所以整体复制最稳；174 MB 的量级可以接受）。
        Copy-Item (Join-Path $OPENSSL_SRC '*') $sslWork -Recurse -Force
        # 复制过来的陈旧 .o 必须清掉，否则还是混架构
        Get-ChildItem $sslWork -Recurse -Include '*.o', '*.d', '*.a' -File -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
    $workShort = $fso.GetFolder($sslWork).ShortPath -replace '\\', '/'
    $workShort = "/" + $workShort.Substring(0, 1).ToLower() + $workShort.Substring(2)

    $shLines = @(
        'set -e',
        ('export PATH="' + $ndkShort + '/llvm/bin:/usr/bin:$PATH"'),
        ('cd "' + $workShort + '"'),
        'export CONFIGURE_CHECKER_WARN=1',
        ('export CC="' + $ndkShort + '/llvm/bin/clang.exe"'),
        ('export CXX="' + $ndkShort + '/llvm/bin/clang++.exe"'),
        ('export CFLAGS="--target=' + $triple + ' --sysroot=' + $ndkShort + '/sysroot -O2 -ffunction-sections -fdata-sections -fstack-protector-strong -D_FORTIFY_SOURCE=2"'),
        ('export CXXFLAGS="--target=' + $triple + ' --sysroot=' + $ndkShort + '/sysroot -O2"'),
        ('export LDFLAGS="--target=' + $triple + ' --sysroot=' + $ndkShort + '/sysroot -Wl,-z,max-page-size=16384 -Wl,--build-id=sha1"'),
        ('perl Configure ' + $target + ' shared ' + $asmFlag + ' \'),
        '  no-tests no-docs no-apps no-legacy no-engine no-ssl3 no-ssl3-method \',
        '  no-ml-kem no-ml-dsa no-slh-dsa no-sm2 no-sm3 no-sm4 \',
        '  no-camellia no-aria no-cast no-idea no-mdc2 no-md4 no-rc2 no-rc5 no-seed \',
        '  no-whirlpool no-siphash no-ocb no-siv no-srp no-psk no-cms no-ts no-comp \',
        '  no-nextprotoneg no-async no-uplink no-autoerrinit no-autoload-config \',
        '  no-http no-quic no-gost no-fips no-padlockeng \',
        ('  --prefix="' + $installShort + '"'),
        'make -j8',
        'make install_sw'
    )
    $shPath = Join-Path $env:TEMP "tdx-build-ssl-$Abi.sh"
    # 去 BOM：MSYS 的 bash 会把 BOM 当成命令的一部分
    [System.IO.File]::WriteAllText($shPath, ($shLines -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
    $shMsys = ($shPath -replace '\\', '/') -replace '^([A-Za-z]):', '/$1'
    & $msysBash -lc "bash '$shMsys'"
    if ($LASTEXITCODE -ne 0) { throw "OpenSSL 编译失败（见 docs/runbooks/tdlib-native-build-windows.md 第 5 节）" }
    $sslDirsForSymlink = @($DEPS_SSL)
}

# --- 2. 修复 OpenSSL 的 symlink 检出问题 --------------------------------------
# git 里 libcrypto.so / libssl.so 是 120000 模式（symlink），Windows 默认
# `core.symlinks=false` 会把它们检出成十几字节的**文本文件**，内容是目标文件名。
# 链接器读到会报 `libcrypto.so:1: unexpected EOF` —— 报错完全看不出是 symlink 的问题。
# 两处都要修：TDLib 链接用 third_party/openssl，napibridge 用 deps/<abi>/。
foreach ($dir in $sslDirsForSymlink) {
    foreach ($pair in @(@('libcrypto.so', 'libcrypto.so.3'), @('libssl.so', 'libssl.so.3'))) {
        $link = Join-Path $dir $pair[0]
        $target = Join-Path $dir $pair[1]
        if (-not (Test-Path $target)) { continue }
        if (-not (Test-Path $link)) { continue }
        if ((Get-Item $link -Force).Length -ge 1024) { continue }   # 已经是真 .so
        Remove-Item $link -Force
        New-Item -ItemType HardLink -Path $link -Target $target | Out-Null
        Write-Step "fix symlink: $($pair[0]) -> $($pair[1]) in $(Split-Path $dir -Leaf)"
    }
}
# deps/<abi>/lib 的修复沿用同一个目录表
foreach ($pair in @(@('libcrypto.so', 'libcrypto.so.3'), @('libssl.so', 'libssl.so.3'))) {
    $link = Join-Path $DEPS_SSL "lib\$($pair[0])"
    $target = Join-Path $DEPS_SSL "lib\$($pair[1])"
    if ((Test-Path $target) -and (Test-Path $link) -and ((Get-Item $link -Force).Length -lt 1024)) {
        Remove-Item $link -Force
        New-Item -ItemType HardLink -Path $link -Target $target | Out-Null
        Write-Step "fix symlink: $($pair[0]) -> $($pair[1])"
    }
}

# linux-x86_64 的 OpenSSL 默认装到 lib64/，而 napibridge 的 CMakeLists 取
# ${OPENSSL_DIR}/lib/libcrypto.so.3。做一份 lib 镜像（硬链接，不额外占空间）。
$lib64 = Join-Path $DEPS_SSL 'lib64'
$lib = Join-Path $DEPS_SSL 'lib'
if ((Test-Path $lib64) -and -not (Test-Path (Join-Path $lib 'libcrypto.so.3'))) {
    Write-Step "mirror lib64 -> lib (napibridge expects lib/)"
    New-Item -ItemType Directory -Force -Path $lib | Out-Null
    Get-ChildItem $lib64 -File | ForEach-Object {
        New-Item -ItemType HardLink -Path (Join-Path $lib $_.Name) -Target $_.FullName -Force | Out-Null
    }
    Get-ChildItem $lib64 -Directory | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $lib $_.Name) -Recurse -Force
    }
}

# --- 3. host 侧生成 TDLib 源码（td/generate/auto）----------------------------
# 这一步与 ABI 无关，只在首次（或 third_party/td 更新后）需要。产物 13 MB / 49 文件。
$generated = Join-Path $SRC 'td\generate\auto\td\telegram\td_api.h'
if (-not (Test-Path $generated)) {
    Write-Step "generate TDLib sources (host g++, one-off)"
    New-Item -ItemType Directory -Force -Path $HOST_GEN_DIR | Out-Null
    & cmake -S $SRC -B $HOST_GEN_DIR -G Ninja `
        -DCMAKE_BUILD_TYPE=Release `
        -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ `
        -DTD_GENERATE_SOURCE_FILES=ON
    if ($LASTEXITCODE -ne 0) { throw "host 生成 configure 失败" }
    & cmake --build $HOST_GEN_DIR --parallel 8
    if ($LASTEXITCODE -ne 0) { throw "host 生成编译失败" }
    if (-not (Test-Path $generated)) { throw "生成完成但 $generated 不存在" }
}

# --- 4. 交叉编译 TDLib -------------------------------------------------------
if ($Clean) {
    Write-Step "remove $BUILD_DIR"
    Remove-Item -Recurse -Force $BUILD_DIR -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $BUILD_DIR | Out-Null

# try_compile 的子进程不继承 -D 缓存变量，只认环境变量 —— 工具链文件读 TDX_OHOS_NDK，
# 所以这两个都必须设，否则 try_compile 回落到 macOS 默认路径并报
# 「OHOS NDK toolchain not found at /Applications/...」。
$env:TDX_OHOS_NDK = $NDK
$env:OHOS_NDK_PATH = $NDK

$tripleDir = if ($Abi -eq 'arm64-v8a') { 'aarch64-linux-ohos' } else { 'x86_64-linux-ohos' }
$zlibInc = Join-Path $NDK 'sysroot\usr\include'
$zlibLib = Join-Path $NDK "sysroot\usr\lib\$tripleDir\libz.so"
if (-not (Test-Path (Join-Path $zlibInc 'zlib.h'))) { throw "NDK zlib 头文件缺失：$zlibInc" }
if (-not (Test-Path $zlibLib)) { throw "NDK libz 缺失：$zlibLib" }

Write-Step "configure cross-compile: $Abi"
& cmake -S $SRC -B $BUILD_DIR -G Ninja `
    -DCMAKE_TOOLCHAIN_FILE="$(Join-Path $TDCORE 'cmake\ohos-toolchain.cmake')" `
    -DOHOS_ARCH="$Abi" `
    -DOHOS_NDK_PATH="$NDK" `
    -DTDX_DEPS_PREFIX="$DEPS_SSL" `
    -DCMAKE_BUILD_TYPE=RelWithDebInfo `
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-soname,libtdjson.so" `
    -DTD_ENABLE_LTO=OFF `
    -DOPENSSL_ROOT_DIR="$DEPS_SSL" `
    -DZLIB_INCLUDE_DIR="$zlibInc" `
    -DZLIB_LIBRARY="$zlibLib" `
    -DTD_ENABLE_JNI=OFF
if ($LASTEXITCODE -ne 0) { throw "交叉编译 configure 失败" }

$n = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
Write-Step "build tdjson (parallel $n)"
& cmake --build $BUILD_DIR --target tdjson --parallel $n
if ($LASTEXITCODE -ne 0) { throw "tdjson 编译失败" }

# --- 5. strip 出打包用的副本 -------------------------------------------------
# napibridge 的 CMakeLists 引用的正是 stripped/libtdjson.so，路径不能改。
$stripped = Join-Path $BUILD_DIR 'stripped'
New-Item -ItemType Directory -Force -Path $stripped | Out-Null
$built = Get-ChildItem $BUILD_DIR -Filter 'libtdjson.so.*' |
    Sort-Object Length -Descending | Select-Object -First 1
if (-not $built) { throw "找不到编译产物 libtdjson.so.*" }
& (Join-Path $NDK 'llvm\bin\llvm-strip.exe') --strip-debug `
    $built.FullName -o (Join-Path $stripped 'libtdjson.so')
if ($LASTEXITCODE -ne 0) { throw "llvm-strip 失败" }

Write-Step "artifacts:"
Get-ChildItem $stripped -Filter 'libtdjson.so' |
    ForEach-Object { "  $Abi\stripped\libtdjson.so  $([math]::Round($_.Length/1MB,1)) MB" }
