# Windows 上的 native 构建链（NATIVE-WIN-101）

> 本文记录**在 Windows 主机上从零重建 TDLib native 库**所需的全部环境、命令与踩过的坑。
> 主开发环境是 macOS，`tools/native/*.sh` 按 macOS 写；本文与 `tools/native/build-tdlib.ps1`
> 是它的 Windows 等价物。目标：换一台 Windows 机器时不必再摸一遍。

---

## 1. 为什么需要单独一套

`tools/native/build-tdlib.sh` 里有三处 macOS 专属假设，在 Windows 上一步都跑不了：

| 假设 | 在 Windows 上的后果 |
|---|---|
| `sysctl -n hw.ncpu` 取核数 | `sysctl` 不存在，脚本在第 72 行中断 |
| 默认 NDK 路径 `/Applications/DevEco-Studio.app/Contents/sdk/...` | 回落到不存在的目录，报「OHOS NDK toolchain not found」 |
| bash + Unix shell 语法 | PowerShell 下没有 bash；即便用 Git 自带的 bash，perl 模块也不完整 |

另外 `build-tdlib-deps.sh` 会**重编 OpenSSL**（`./Configure` + `make`），这在 Windows 上是最难的一步。

---

## 2. 环境清单（本机实测可行）

| 组件 | 用途 | 安装方式 | 版本（实测） |
|---|---|---|---|
| DevEco Studio | NDK（clang/llvm-strip/cmake/ninja） | 官方安装包 | NDK 26.0.0 / clang 15.0.4 |
| MinGW-w64 g++ | **只**用于编译 TDLib 的源码生成器 | `winget install BrechtSanders.WinLibs.POSIX.UCRT` | gcc 16.2.0 |
| gperf | tdutils 的 Hints 表生成 | `winget install oss-winget.gperf` | 3.1 |
| MSYS2 | 提供 `make` / `ar` / 完整 perl（仅编 OpenSSL 时需要） | `winget install MSYS2.MSYS2` | pacman 6.1.0 |
| Strawberry Perl | OpenSSL 的 `Configure` | `winget install StrawberryPerl.StrawberryPerl` | 5.42.3 |

MSYS2 装完还要补两个包：

```bash
C:\msys64\usr\bin\bash.exe -lc "pacman -Sy --noconfirm make binutils"
```

> **为什么 host 编译器不能用 NDK 的 clang 顶替**：NDK clang 没有 Windows 的 C++
> 标准库头文件，连 `#include <cstdio>` 都失败。它只能产出 OHOS 目标，产不出能在
> Windows 本机跑的 `.exe`。

---

## 3. 两个 ABI

| ABI | 用途 | OpenSSL 从哪来 |
|---|---|---|
| `arm64-v8a` | ADR-001 的产线目标（真机） | 仓库 `third_party/openssl` 里**已有**现成的 arm64 产物，不用重编 |
| `x86_64` | **模拟器**（HarmonyOS 7.0.0 的 `phone_all_x86` 镜像只有 x86_64） | 必须现编，仓库里没有 x86 版本 |

模拟器 ABI 这件事值得写死：`hdc install` 报 `code:9568347 install parse native so failed`
时**不是签名问题**，而是设备 ABI 与 HAP 内 `.so` 不匹配。先查设备：

```bash
hdc shell param get const.product.cpu.abilist    # 模拟器返回 x86_64
```

---

## 4. 构建命令

```powershell
# arm64-v8a（真机；用仓库自带的 OpenSSL，不需要 perl/make）
pwsh tools/native/build-tdlib.ps1

# x86_64（模拟器；需要先编 OpenSSL）
pwsh tools/native/build-tdlib.ps1 -Abi x86_64 -BuildOpenSsl
```

产物落在：

```
native/tdcore/build/<abi>/stripped/libtdjson.so     # 打包用（napibridge 引用这个）
native/tdcore/build/deps/openssl/<abi>/lib/         # OpenSSL 前缀（napibridge 引用这个）
```

---

## 5. 踩过的坑（按出现顺序）

### 5.1 git 把 symlink 检出成文本文件

`libcrypto.so` / `libssl.so` 在 git 里是 **120000 模式**（symlink）。Windows 默认
`core.symlinks=false`，于是检出成十几字节的**文本文件**，内容是目标文件名：

```
libcrypto.so     size=14    head=libcrypto.so.3
```

链接器报 `ld.lld: error: libcrypto.so:1: unexpected EOF` —— 报错完全指不出是 symlink 的问题。
修法：删掉后用 `New-Item -ItemType HardLink` 指向 `libcrypto.so.3`。

### 5.2 cmake 的 `try_compile` 不继承 `-D` 缓存变量

`-DOHOS_NDK_PATH=...` 对主项目生效，但 `try_compile` 起的子工程读不到，于是回落到
工具链文件里写死的 macOS 路径，报「OHOS NDK toolchain not found at /Applications/...」。
修法：**同时**设环境变量 `TDX_OHOS_NDK` 与 `OHOS_NDK_PATH`（工具链文件第 19-20 行读前者）。

### 5.3 OpenSSL 的 `unix-checker` 拒绝 Windows perl

`Configurations/unix-checker.pm` 检查 `rel2abs('.')` 里有没有 `/`，Strawberry Perl 返回
`D:\...`，于是直接 `die`：

```
This perl implementation doesn't produce Unix like paths
```

**不要去改那个 `.pm`**。OpenSSL 留了官方开关 `CONFIGURE_CHECKER_WARN=1`，把 checkers
从 `die` 降级为 `warn` —— 这正是为交叉编译准备的。

### 5.4 含空格的路径被 Makefile 截断

`D:\Program Files\...` 传进 OpenSSL 的 Makefile 后，`CC=/d/Program Files/...` 没被引号
保护，shell 按空格切开，报 `/d/Program: No such file or directory`。

修法：用 **8.3 短路径**。取法：

```powershell
(New-Object -ComObject Scripting.FileSystemObject).GetFolder($path).ShortPath
# D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native
# -> D:\PROGRA~1\Huawei\DEVECO~1\sdk\default\OPENHA~1\native
```

### 5.5 x86_64 汇编与 NDK clang 不兼容

OpenSSL 为 x86_64 生成的 `.s` 里有 `.section .note.gnu.property`（GNU as 语法），
NDK clang 的集成汇编器不认，报 `error: expected identifier or '('`。

修法：`./Configure linux-x86_64 **no-asm**`。代价只是加解密变慢，不影响正确性 ——
模拟器上的验证不关心这个。

### 5.6 `mingw32-make -j$n` 在 PowerShell 里被拆成两个参数

`& mingw32-make -j$n` 会传成 `-j` 和 `12`，make 把 `12` 当成构建目标，打印一大段
usage。修法：写成**一个字符串** `& mingw32-make "-j$n"`。

### 5.7 OpenSSL 装到 `lib64` 而 napibridge 要 `lib`

`linux-x86_64` 的默认安装布局是 `lib64/`，而 `native/tdcore/napibridge/CMakeLists.txt`
取 `${OPENSSL_DIR}/lib/libcrypto.so.3`。修法：把 `lib64` 的内容硬链接一份到 `lib/`。

### 5.8 napibridge 的 CMakeLists 曾把 ABI 写死成 arm64-v8a

原第 61/64 行硬编码 `arm64-v8a` 路径，导致 x86_64 构建时找不到 tdjson/openssl。
已改成按 `${OHOS_ARCH}` 取（该文件第 29-35 行本来就在处理 x86_64 的 triple，
只是下面两处漏了）。

---

## 6. 构建产物校验

```powershell
# 架构必须是目标 ABI
python -c "import struct;h=open(r'...\libtdjson.so','rb').read(20);print(hex(struct.unpack('<H',h[18:20])[0]))"
# 0xb7 = AArch64, 0x3e = x86-64
```

arm64 的对照基准（`BUILD-EVIDENCE.md`）：strip 后 **45.9 MB**，TDLib 1.8.67，
build-id `7b9c054b`。本次 Windows 重建得到 **45.7 MB**，一致。
