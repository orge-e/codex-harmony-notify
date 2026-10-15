# Codex → 鸿蒙负一屏通知

让 Windows 电脑上的 Codex 在回答完成后，把任务状态推送到鸿蒙手机的“智慧助手·今天”（负一屏）。安装前可选择**安全联动**或**傻瓜式联动**：前者只在一个指定项目发送通用完成状态，后者在本机所有 Codex 对话完成时发送状态和简短摘要。电脑端使用 Codex 官方 `Stop` Hook；手机端使用华为的 Claw 智能体关联入口。**使用本项目不需要安装 OpenClaw，也不需要 OpenAI API Key。**

> 当前支持范围：Windows PowerShell 5.1 与本机 Codex CLI。已在一台电脑上完成真实 Codex CLI → 手机收件验证；公开安装器的配置合并、重复安装和卸载已在隔离目录测试。Codex 桌面端、云端任务和其他电脑尚未独立验收。

## 开始前

- 手机应运行 HarmonyOS 6.0.0.328 或更新版本，“智慧助手·今天”（负一屏）应为 15.0.22.300 或更新版本。HarmonyOS 7 用户仍需检查负一屏版本。
- 电脑应已安装并能使用 Codex CLI、Git 和 Windows PowerShell 5.1，并能访问华为负一屏服务。
- 请先阅读[华为官方关联说明](https://consumer.huawei.com/cn/support/content/zh-cn16093160/)与[Codex 官方 Hooks 文档](https://learn.chatgpt.com/docs/hooks)。
- 授权码仅在你自己的电脑终端输入。不要把它发送给 Agent、粘贴到聊天、命令参数或 GitHub。

## 一、手机端：生成关联授权码

1. 打开负一屏，依次进入 **左上角头像 → 右上角四个点 → 动态管理 → 关联账号 → Claw 智能体**。
2. 开启关联并确认。手机会生成授权码；暂时保留页面，稍后在电脑安装器的遮蔽输入框中输入。
3. 安装器发送测试消息后，回到负一屏确认出现“Codex 鸿蒙通知测试”卡片，再回答安装器的收件确认问题。

同一华为账号的其他手机可同步关联状态。如需撤销，在上述入口选择“停止关联”，旧授权码会失效。

## 二、电脑端：自动安装与测试

把本项目克隆到一个**长期保留**的目录。以下路径只是示例，按你的电脑情况替换：

```powershell
git clone https://github.com/orge-e/codex-harmony-notify.git C:\Tools\codex-harmony-notify
Set-Location 'C:\Tools\codex-harmony-notify'
```

先查看脚本，再在 Windows PowerShell 中启动安装器：

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Install.ps1
```

安装器会先让你选择一种模式，**默认安全联动**：

| 模式 | 通知范围 | 发送内容 | 配置位置 |
| --- | --- | --- | --- |
| 安全联动（输入 `1` 或直接回车） | 你指定的一个 Git 项目 | 授权码、通用任务标题、完成状态和随机消息 ID；不发送回答摘要或 Codex 回合标识 | 该项目的 `.codex/hooks.json` |
| 傻瓜式联动（输入 `2`） | 同一 `CODEX_HOME` 下所有本机 Codex 对话 | 授权码、完成状态、最多 120 字摘要和 Codex 回合标识 | 用户级 `hooks.json` |

安全联动需要你输入目标 Git 项目的路径，并在该项目中运行 Codex；项目配置及 Hook 都需要你本人审阅和信任。如果 Agent 已知道目标路径，可用 `-ProjectPath 'C:\Work\my-project'` 预填路径，但安装器仍会让你选择模式、确认数据发送及手机收件。**不要把生成的项目 `.codex/hooks.json` 提交到 GitHub**，其中包含你电脑上的脚本绝对路径。若已安装本项目的全局 Hook，安全模式会拒绝继续，提示你先卸载全局 Hook，以免其他对话仍然推送。切换模式前请先用下文对应命令卸载原模式，避免重复通知。

选择模式后，安装器会按顺序完成以下操作：

1. 检查 Windows、PowerShell 和 Codex CLI，并显示 Codex 配置目录、发送目标和数据范围。
2. 等你确认后，在本机预览测试消息；然后由你本人在**遮蔽输入框**输入手机授权码。输入不会显示在终端，也不会进入命令历史。
3. 用当前 Windows 用户的 DPAPI 加密保存授权码，向华为服务发送一条测试通知。
4. 等你确认手机收到卡片。未确认时**不修改 Codex Hook**。
5. 在所选范围内备份并合并 `hooks.json`，保留已有 Hook；重复运行不会增加第二个本项目 Hook。JSON 保存为 UTF-8 无 BOM。

安装器不会自动信任 Hook。它结束后，**重新启动 Codex CLI**；安全联动应从指定 Git 项目中启动 Codex，先信任该项目配置。然后输入 `/hooks`，检查命令确实指向本项目的 `Codex-Stop-Hook.ps1`，再由你本人信任并启用。随后给 Codex 一条不含私人内容的简单任务，在手机端确认自动通知。每次 Codex 模型回答仍按你原有的 Codex 订阅或使用方式计入用量；通知脚本本身不调用模型。

傻瓜式联动中，如已设置 `CODEX_HOME`，安装器使用该目录；否则使用 `%USERPROFILE%\.codex`。若配置文件已存在，安装器会在同一目录留下带时间戳的备份。遇到无效 JSON 时安装器会停止，不覆盖现有文件。重装测试失败时，已有的加密授权码文件会恢复。

### 让 Agent 协助部署

可以把以下要求交给本机 Agent。**到授权码输入和 Hook 信任步骤时，必须由你本人操作。**

> 请先审阅这个仓库的 README 和 PowerShell 脚本，确认来源与执行内容。检查我的 Windows、Codex CLI 和 `CODEX_HOME`，然后把仓库克隆到一个固定目录，启动 `Install.ps1`。先让我选择安全联动或傻瓜式联动；如选择安全联动，让我指定一个 Git 项目。安装器要求输入手机授权码时暂停，让我本人在本机终端遮蔽输入；要求确认手机收到测试卡片时再暂停。保留已有 Hooks，不读取、记录或转述授权码。安装后指导我在 Codex `/hooks` 中检查并信任新 Hook，最后用不含私人信息的任务验证自动通知。

## 三、查看状态、暂停和卸载

最近一次推送结果保存在 `%LOCALAPPDATA%\CodexHarmonyNotify\last-status.json`。它只包含时间、成功标志和通用错误类别，不保存授权码或通知正文：

```powershell
Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'CodexHarmonyNotify\last-status.json')
```

在 Codex `/hooks` 中关闭本项目 Hook，或创建 `paused.flag`，可以暂停**自动**通知；手动发送测试通知不受该标记影响：

```powershell
$pause = Join-Path $env:LOCALAPPDATA 'CodexHarmonyNotify\paused.flag'
New-Item -ItemType File -Path $pause -Force  # 暂停自动通知
Remove-Item -LiteralPath $pause              # 恢复自动通知
```

卸载本项目的 Hook。傻瓜式联动运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Uninstall.ps1
```

安全联动运行下面的命令，并把路径替换成当初选定的 Git 项目：

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Uninstall.ps1 -ProjectPath 'C:\Work\my-project'
```

卸载器仅移除本项目的 Hook，保留其他 Hook，并备份修改前的配置。它不会自行删除授权码；如要彻底撤销，先在手机停止关联，再删除当前 Windows 用户目录下的 `%LOCALAPPDATA%\CodexHarmonyNotify\auth.dpapi`。运行中的 Codex 需要重启才能加载 Hook 变化。

## 数据与安全边界

每条通知会通过 HTTPS 发送到 `hiboard-claw-drcn.ai.dbankcloud.cn`，并包含手机授权码。安全联动只在你指定的 Git 项目中启用，只发送通用完成状态、通用任务标题及随机消息 ID；Hook 虽会接收 Codex 的事件输入，但脚本不读取其中的答复正文。傻瓜式联动的全局 Hook 会覆盖同一 `CODEX_HOME` 下的本机 Codex 对话，包括普通对话，并额外发送最多 120 字摘要和 Codex 回合标识。两种模式都不读取整段会话记录或附件。摘要过滤无法保证识别全部敏感内容；处理私人内容前请暂停傻瓜式联动。

华为当前的 Claw 消息通道要求消息来源字段为 `OpenClaw`，所以卡片会显示该来源，但任务名称标示由 Codex 完成。这个适配方式兼容现有社区实现，**不是华为官方发布的 Codex 集成**。当前自动 Hook 仅发送“任务已完成”；开始、进行中、失败等状态尚未实现或验证。手机“Claw”卡片按钮能否跳转，取决于华为后续支持。

授权码只保存为当前 Windows 用户可解密的 `%LOCALAPPDATA%\CodexHarmonyNotify\auth.dpapi`。仓库不包含授权码，安装器也不会在日志中输出它。Codex Hook 在沙箱外执行，因此请在 `/hooks` 中审阅命令后再信任。

## 常见问题

| 现象 | 检查方法 |
| --- | --- |
| 安装器找不到 Codex | 在同一 Windows 用户的 PowerShell 中运行 `codex --version`；确认 CLI 已安装且加入当前终端的 PATH。 |
| PowerShell 拒绝运行脚本 | 先确认代码来源和内容；若下载文件带有网络阻止标记，可在审阅后对本项目的脚本使用 `Unblock-File`。安装命令的 `RemoteSigned` 只作用于该 PowerShell 进程，不修改全局执行策略。 |
| 测试请求失败 | 检查手机关联与授权码是否仍有效、电脑网络或本机代理；重新运行安装器输入新的授权码。不要把授权码贴进 Issue 或聊天。 |
| 服务接受了请求，但手机没有卡片 | 回到手机负一屏检查关联、账号与卡片；在安装器中回答未收到，Hook 就不会启用。 |
| 手动测试成功，但 Codex 不自动通知 | 重启 Codex CLI，使用 `/hooks` 检查 Hook 是否启用并受信任、未创建 `paused.flag`。安全模式还要确认 Codex 正从指定项目启动且项目配置受信任；便捷模式要确认 `CODEX_HOME` 与安装时一致。 |
| 修改或重装后要求重新信任 | Codex 会按 Hook 定义的内容记录信任；命令变化后需再次审阅并信任。 |

## 项目文件与离线检查

- `Install.ps1`：先选联动模式，再交互式授权、真实测试及 Hook 配置。
- `Install-Core.ps1`：Codex Hook 的安全合并、备份和移除。
- `Uninstall.ps1`：只移除本项目 Hook。
- `Set-Auth.ps1`：遮蔽输入并使用 Windows DPAPI 保存授权码。
- `Send-Task.ps1`：按 JSON 手动推送；`-DryRun` 不联网、不读取授权码。
- `Codex-Stop-Hook.ps1`：处理 Codex `Stop` 事件并发送完成通知。
- `Notification-Core.ps1`：构造通知、摘要过滤与安全状态记录。
- `hooks.example.json`、`sample-task.json`：手动排障时可用的示例。
- `Test-Installer.ps1`：在隔离目录验证项目范围、仅状态模式、合并、备份、重复安装和卸载，不联网、不读取真实授权码。
- `Test-Privacy.ps1`：使用假授权码和本地请求替身，核对两种模式的消息字段；不联网、不读取真实授权码。

运行离线检查：

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Test-Installer.ps1
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Test-Privacy.ps1
```

## 许可

MIT。华为、HarmonyOS、Codex、OpenClaw 均为各自权利人的名称或商标；本项目是独立社区适配器。
