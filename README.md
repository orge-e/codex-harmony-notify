# Codex → 鸿蒙负一屏通知

让 Windows 电脑上的 Codex 在回答完成后，把任务状态推送到鸿蒙手机的“智慧助手·今天”（负一屏）。安装前可选择**安全联动**或**傻瓜式联动**：前者只在一个指定项目发送通用完成状态，后者在本机所有 Codex 对话完成时发送状态和简短摘要。电脑端使用 Codex 官方 `Stop` Hook；手机端使用华为的 Claw 智能体关联入口。**使用本项目不需要安装 OpenClaw，也不需要 OpenAI API Key。**

> 当前支持范围：Windows PowerShell 5.1 与本机 Codex CLI。已在一台电脑上完成真实 Codex CLI → 手机收件验证；公开安装器的配置合并、重复安装和卸载已在隔离目录测试。Codex 桌面端、云端任务和其他电脑尚未独立验收。

## 快速安装

1. 在手机负一屏进入 **左上角头像 → 右上角四个点 → 动态管理 → 关联账号 → Claw 智能体**，开启关联，保留手机显示的授权码。手机和负一屏版本要求见[华为官方说明](https://consumer.huawei.com/cn/support/content/zh-cn16093160/)。
2. 在电脑的 Windows PowerShell 中运行下列命令。需要已安装 Codex CLI 和 Git；安装目录请长期保留。

```powershell
$installDir = Join-Path $env:USERPROFILE 'codex-harmony-notify'
git clone https://github.com/orge-e/codex-harmony-notify.git $installDir
Set-Location $installDir
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Install.ps1
```

3. 选择模式，在遮蔽输入框中亲自输入手机授权码。安装器会自动测试华为服务并配置 Codex Hook；无需再次确认测试消息或重复输入授权码。
4. 手机确认收到测试卡片。然后重新启动 **Codex CLI**，输入 `/hooks`，审阅并信任 `Codex-Stop-Hook.ps1`。让 Codex 回答一条简单问题，再检查手机是否收到自动通知。安全模式还需先信任目标项目的 `.codex` 配置。

> 不要把授权码发给 Agent，或写进聊天、命令行参数和 GitHub。安装器无法代替你确认手机收件，也不能绕过 Codex 的 Hook 信任步骤。[官方 Hooks 文档](https://learn.chatgpt.com/docs/hooks)说明了这一机制。

## 两种模式

安装时选择一种，**默认安全联动**：

| 模式 | 通知范围 | 发送内容 | 配置位置 |
| --- | --- | --- | --- |
| 安全联动（输入 `1` 或直接回车） | 你指定的一个 Git 项目 | 授权码、通用任务标题、完成状态和随机消息 ID；不发送回答摘要或 Codex 回合标识 | 该项目的 `.codex/hooks.json` |
| 傻瓜式联动（输入 `2`） | 同一 `CODEX_HOME` 下所有本机 Codex 对话 | 授权码、完成状态、根据答复生成的任务标题、最多 500 字摘要和 Codex 回合标识 | 用户级 `hooks.json` |

傻瓜式联动会从 Codex 的最终答复中提取一条简短、有内容的句子作为通知标题，例如“Codex：修复导出失败问题”；安全联动仍使用通用标题。Codex 的 `Stop` 事件不包含原始提问，因此标题依据最终答复生成；答复没有可用文字时回退为“Codex 任务”。提取标题不额外调用模型。

安全联动需要输入一个 Git 项目路径，并在该项目中运行 Codex。可用 `-ProjectPath 'C:\Work\my-project'` 预填路径。**不要把生成的项目 `.codex/hooks.json` 提交到 GitHub**，其中包含本机脚本的绝对路径。安装器会拒绝修改已被 Git 跟踪的同名文件。切换模式前先按下文卸载原模式，避免重复通知。

选择模式后，安装器会按顺序完成以下操作：

1. 检查系统、Codex CLI、项目范围及已有 Hook 配置；配置无效时提前停止。
2. 显示发送目标和数据范围；你在**遮蔽输入框**输入授权码，即授权发送固定测试消息。授权码不会出现在终端或命令历史。
3. 用当前 Windows 用户的 DPAPI 加密保存授权码，向华为服务发送测试通知。测试失败时恢复原有加密文件；首次安装则删除本次新建的文件。
4. 服务接受请求后，备份并合并 `hooks.json`，保留其他 Hook。重复运行不会添加第二个本项目 Hook。JSON 保存为 UTF-8 无 BOM。

安装器不能确认手机实际收件。若手机没有测试卡片，先不要信任 Hook，检查关联和网络。确认收件后按快速安装的第 4 步操作。每次 Codex 模型回答仍按原有订阅或使用方式计入用量；通知脚本本身不调用模型。

傻瓜式联动中，如已设置 `CODEX_HOME`，安装器使用该目录；否则使用 `%USERPROFILE%\.codex`。若配置文件已存在，安装器会在同一目录留下带时间戳的备份。遇到无效 JSON 时安装器会停止，不覆盖现有文件。重装测试失败时，已有的加密授权码文件会恢复。

### 让 Agent 协助部署

可以把以下要求交给本机 Agent。**到授权码输入和 Hook 信任步骤时，必须由你本人操作。**

> 请审阅本仓库的脚本，把它克隆到长期保留的目录并运行 `Install.ps1`。让我选择安全或傻瓜式联动；需要授权码时暂停，让我亲自在本机终端输入。保留已有 Hook，不读取或转述授权码。安装后提醒我核对手机测试卡片，并在 Codex `/hooks` 中审阅和信任新 Hook，最后完成一次自动通知测试。

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

每条通知会通过 HTTPS 发送到 `hiboard-claw-drcn.ai.dbankcloud.cn`，并包含手机授权码。安全联动只在你指定的 Git 项目中启用，只发送通用完成状态、通用任务标题及随机消息 ID；Hook 虽会接收 Codex 的事件输入，但脚本不读取其中的答复正文。傻瓜式联动的全局 Hook 会覆盖同一 `CODEX_HOME` 下的本机 Codex 对话，包括普通对话，并额外发送最多 500 字摘要和 Codex 回合标识。脚本会局部遮蔽常见授权码、邮箱、手机号、证件号、链接、路径和代码块，尽量保留其余摘要。两种模式都不读取整段会话记录或附件。摘要过滤无法保证识别全部敏感内容；处理私人内容前请暂停傻瓜式联动。500 字是本项目的发送上限，华为卡片实际能显示多少需以手机测试为准。

华为当前的 Claw 消息通道要求消息来源字段为 `OpenClaw`，所以卡片会显示该来源，但任务名称标示由 Codex 完成。这个适配方式兼容现有社区实现，**不是华为官方发布的 Codex 集成**。当前自动 Hook 仅发送“任务已完成”；开始、进行中、失败等状态尚未实现或验证。手机“Claw”卡片按钮能否跳转，取决于华为后续支持。

授权码只保存为当前 Windows 用户可解密的 `%LOCALAPPDATA%\CodexHarmonyNotify\auth.dpapi`。仓库不包含授权码，安装器也不会在日志中输出它。Codex Hook 在沙箱外执行，因此请在 `/hooks` 中审阅命令后再信任。

此外，运行时会从卡片标题和正文中精确遮蔽本机已保存的授权码，即使答复未写“授权码”标签；该码仍需作为请求凭据发给华为服务。

## 常见问题

| 现象 | 检查方法 |
| --- | --- |
| 安装器找不到 Codex | 在同一 Windows 用户的 PowerShell 中运行 `codex --version`；确认 CLI 已安装且加入当前终端的 PATH。 |
| PowerShell 拒绝运行脚本 | 先确认代码来源和内容；若下载文件带有网络阻止标记，可在审阅后对本项目的脚本使用 `Unblock-File`。安装命令的 `RemoteSigned` 只作用于该 PowerShell 进程，不修改全局执行策略。 |
| 测试请求失败 | 检查手机关联与授权码是否仍有效、电脑网络或本机代理；重新运行安装器输入新的授权码。不要把授权码贴进 Issue 或聊天。 |
| 服务接受了请求，但手机没有卡片 | 回到手机负一屏检查关联、账号与卡片；在安装器中回答未收到，Hook 就不会启用。 |
| 摘要在手机卡片上被截短或未通过内容审核 | 本项目最多发送 500 字，手机展示上限和华为服务审核规则由华为决定；可改用安全联动，只发送通用状态。不要拆分消息或改写内容来规避审核。 |
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
