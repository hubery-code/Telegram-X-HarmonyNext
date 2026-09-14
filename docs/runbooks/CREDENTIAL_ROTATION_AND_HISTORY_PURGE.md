# Runbook：凭据轮换与 Git 历史清理操作手册

> **文档属性**：架构负责人/项目维护者专用敏感操作指南  
> **关联缺陷**：P0-SEC-001、P0-SEC-002（SEC-002 质量恢复工作包）  
> **特别注意**：本操作涉及线上凭据吊销、本地签名重置及 Git 提交历史重写（强推远端），**严禁由 AI 自行执行**，必须由仓库所有者/架构负责人人工确认后执行。

---

## 1. 影响清单（Impact Assessment）

1. **凭据层面**：
   - 历史进入代码的 Telegram `api_hash` 已视为暴露，必须在 Telegram 开发者后台作废/轮换。
   - 历史提交中的调试签名口令与绝对路径已进入 Git 历史，需从全历史中脱敏。
2. **Git 历史层面**：
   - 首次引入敏感签名的提交为 `3a2a5195859b8c9d2ac2c4e19d7c8033bea98191`（2026-09-08）。
   - 首次引入 `EntryAbility.ets` 硬编码凭据的提交为 `7a81158564db73d5ca7608678d462db94d1f2b60`（2026-09-10）。
   - 执行历史重写后，自 `3a2a519` 开始的所有后续提交的 Commit Hash 均会改变。
3. **协作团队层面**：
   - 所有团队成员与协同 AI 需要重新拉取 `origin/master` 并重置本地分支（`git fetch origin && git reset --hard origin/master`）。
   - 本地未合并的临时分支需使用 `git rebase --onto` 移植到新的基线提交上。

---

## 2. 步骤一：Telegram API 凭据轮换

1. 使用申请对应凭据的 Telegram 手机号登录：
   👉 [https://my.telegram.org](https://my.telegram.org)
2. 进入 **API development tools**。
3. 若允许重新生成 Hash 或删除现有 App，请立即吊销旧 App 并创建新的应用，获取崭新的 `api_id` 与 `api_hash`。
4. 将新凭据写入本地 `local.properties`（该文件已在 `.gitignore` 中被忽略，永不入库）：
   ```bash
   cat << 'EOF' > local.properties
   telegram.api_id=<NEW_TELEGRAM_API_ID>
   telegram.api_hash=<NEW_TELEGRAM_API_HASH>
   EOF
   chmod 600 local.properties
   ```
5. 运行验证命令，确保本地构建能正常注入新凭据：
   ```bash
   ./tools/ci/inject-credentials.sh
   ```

---

## 3. 步骤二：本地调试签名材料轮换

1. 删除当前未受版本控制但曾泄露过口令的本地调试材料（若需重新生成）：
   ```bash
   rm -rf signing/debug.p12 signing/debug.cer signing/debug.p7b
   ```
2. 打开 DevEco Studio，进入：
   `File` → `Project Structure` → `Project` → `Signing Configs`
3. 重新勾选 **Automatically generate signature** 重新生成，或配置独立的本地安全存储。
4. 确保 `build-profile.json5` 中的 `signingConfigs` 保持为 `[]`，不要将新口令提交至版本控制。

---

## 4. 步骤三：使用 git-filter-repo 重写 Git 历史

> 推荐使用官方维护且性能优异的 [`git-filter-repo`](https://github.com/newren/git-filter-repo)（可通过 `brew install git-filter-repo` 安装）。

### 4.1 操作准备
在干净的独立目录建立完整备份镜像：
```bash
cd /tmp
git clone --mirror /Users/mbjpeng-yu01/androidProjects/Telegram-X-HarmonyNext repo_backup.git
```

### 4.2 编写替换表达式文件 `expressions.txt`
创建文本文件 `expressions.txt`，声明需要从全历史中抹去的精确敏感字符串（仅在架构负责人本地环境执行，严禁提交此文件）：
```text
# 将历史中的真实 api_hash 替换为脱敏占位符
<OLD_API_HASH_LITERAL>==><REVOKED_API_HASH_PLACEHOLDER>

# 将历史 build-profile.json5 中的敏感口令字面量替换为占位符
<OLD_KEY_PASSWORD_LITERAL>==><REVOKED_DEBUG_PASSWORD>
<OLD_STORE_PASSWORD_LITERAL>==><REVOKED_DEBUG_PASSWORD>

# 将历史中的绝对路径替换为相对路径占位符
/Users/mbjpeng-yu01/androidProjects/Telegram-X-HarmonyNext/signing/==>./signing/
/Users/mbjpeng-yu01/.ohos/config/==>./signing/
```

### 4.3 执行历史替换
```bash
cd /Users/mbjpeng-yu01/androidProjects/Telegram-X-HarmonyNext
git filter-repo --replace-text expressions.txt --force
rm expressions.txt
```

### 4.4 校验全历史秘密消除
使用强化后的秘密扫描工具校验全历史：
```bash
# 验证当前工作区
./tools/ci/secret-scan.sh

# 验证 Git 全量提交历史中无残留
git log -p | python3 -c "
import sys, re
content = sys.stdin.read()
patterns = [
    re.compile(r'api[_-]?hash\s*[:=]\s*[\"\' ][0-9a-fA-F]{16,}'),
    re.compile(r'(keyPassword|storePassword)\s*[:=]\s*[\"\' ][0-9a-zA-Z]{16,}'),
    re.compile(r'/Users/mbjpeng-yu01/')
]
hits = 0
for p in patterns:
    m = p.findall(content)
    if m:
        hits += len(m)
        print(f'Found {len(m)} residual occurrences of pattern')
if hits == 0:
    print('ALL GIT HISTORY CLEAN! Zero leaks detected.')
    sys.exit(0)
else:
    print(f'FAIL: {hits} residuals found in git log.')
    sys.exit(1)
"
```

---

## 5. 步骤四：推送到远端仓库与团队同步

1. 确认无误后，强制推送至远端主干：
   ```bash
   git push origin master --force
   ```
2. 通知所有协作者及其他运行中的 AI Agent：
   ```text
   【紧急通知】由于安全凭据轮换与 Git 历史脱敏重写，origin/master 提交历史已更新。
   请所有协作者在本地执行：
       git fetch origin
       git reset --hard origin/master
   若有未提交的工作，请先使用 git stash 或 format-patch 暂存，并在重置后重新 apply。
   ```
