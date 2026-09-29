# SSH Image Paste

[English](README.md)

在 **Windows Terminal** 中按 **Ctrl+Alt+V**，将 Windows 剪贴板里的图片上传到 Linux SSH 服务器，并把远程图片路径粘贴到当前输入框。适用于远程 Codex CLI，以及其他能读取远程图片文件的工具。

这是一个独立的 Windows 辅助脚本，不是 Codex 扩展。无需在服务器部署剪贴板服务、X11 转发、Python 或 Node.js。

## 原理

```text
截图进入 Windows 剪贴板
  → 本地辅助程序接收 Ctrl+Alt+V
  → 保存临时 PNG
  → 新建 SSH 连接，通过标准输入传输图片字节
  → 服务器保存图片，返回绝对路径
  → 本地把剪贴板改成路径文本
  → 模拟 Ctrl+Shift+V，填入终端
  → 你补充问题并按回车
```

**上传目标由配置决定，不会自动识别或复用当前终端的 SSH 会话。** 终端中的服务器和用户必须与配置一致。容器内的 `/tmp` 也不一定能看到宿主机上传的图片。

## 环境要求

- Windows 10/11、Windows Terminal、Windows PowerShell 5.1 与 .NET Framework。
- Windows OpenSSH 客户端，路径为 `%WINDIR%\System32\OpenSSH\ssh.exe`。
- 静默启动使用 Windows Script Host（`Start.vbs`），也支持直接运行 PowerShell。
- Linux 服务器提供 POSIX shell、`mktemp`、`cat`，并可写入 `/tmp`。
- 已配置 SSH 密钥或 SSH agent，能在不输入密码的情况下连接。先手动连接并核对主机密钥。
- Windows Terminal 的 `Ctrl+Shift+V` 保持为粘贴；终端与辅助程序以相同权限运行，通常都不需要管理员权限。

## 安装与使用

下载或克隆仓库，放在一个长期保留、可写的目录中。以下命令在这个目录的**本地 Windows PowerShell**中运行，不能在 SSH 远程会话中运行。

**1. 配置 SSH 连接**

推荐在 `%USERPROFILE%\.ssh\config` 中添加别名：

```sshconfig
Host my-server
    HostName server.example.com
    User your-user
    IdentityFile ~/.ssh/id_ed25519
    # Port 2222
    # ProxyJump bastion
```

也可以直接使用 `your-user@server.example.com`。端口、密钥、IPv6 地址和跳板机写在 SSH 配置中，不要把命令参数拼进上传目标。

**2. 验证连接**

```powershell
ssh my-server
# 核对主机身份并登录，然后退出远程会话，在本地运行：
ssh -T -o BatchMode=yes -o StrictHostKeyChecking=yes my-server "printf ready"
```

第二条命令应直接输出 `ready`，不要求输入密码。

**3. 安装并启动**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Destination my-server
```

安装会生成本地 `config.json`，添加当前用户的登录自启动快捷方式，并启动托盘程序。`-ExecutionPolicy Bypass` 只作用于本次进程，不修改系统策略；组织策略仍可能限制运行。快捷方式指向当前目录，安装后不要直接移动目录。

**4. 粘贴截图**

1. 用 `Win+Shift+S` 截图，或复制实际图片内容。
2. 切到 Windows Terminal 中远程工具的输入框。
3. 按 `Ctrl+Alt+V` 并松开，上传过程中保持当前标签页和分屏选中。
4. 等路径填入，再补充问题并按回车，例如：

   ```text
   请分析这张截图 /tmp/codex-clipboard.Abc1234567/image.png
   ```

输入框显示的是路径，不会出现图片附件缩略图。远程工具需要能访问该文件并支持读取图片。

## 切换服务器、停止与卸载

目标保存在本地 `config.json`，Git 会忽略它。配置格式见 `config.example.json`。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Configure.ps1 -Destination other-server
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Stop.ps1
# 等待托盘图标消失后，再启动：
wscript.exe .\Start.vbs
```

配置在启动时读取，切换服务器后需要重启。每个 Windows 用户/会话只运行一个实例。如果仅临时使用，运行 `Configure.ps1` 后双击 `Start.vbs` 即可，无需安装自启动。`Install.ps1 -NoStart` 可只安装自启动。

Windows Script Host 不可用时，可以直接运行并保留这个 PowerShell 进程：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Bridge.ps1
```

托盘图标右键 → **Exit image paste helper** 可退出；也可运行 `Stop.ps1`。移除自启动并请求停止：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

卸载不会删除源码、配置、日志或远程图片。若之前安装过旧版，请先停止并卸载旧版，避免它占用同一个快捷键。

## 常见问题

| 现象 | 检查方法 |
| --- | --- |
| 远程提示 `clipboard unavailable` 或 X11 连接错误 | 触发的是远程剪贴板操作。检查本地辅助程序是否运行，确认使用 Windows Terminal，快捷键未被其他程序占用。 |
| 没有反应 | 检查托盘和 `bridge.log`；复制实际图片内容，而不是只复制资源管理器中的图片文件；确认窗口和权限级别。 |
| 提示快捷键被占用 | 退出旧版或其他使用 Ctrl+Alt+V 的程序。 |
| SSH 密码或主机密钥错误 | 重跑上面的非交互连接测试；需要时通过 SSH agent 解锁密钥。程序不会弹出密码框或自动接受新主机密钥。 |
| 已上传但没有自动填入 | 上传时窗口/标题改变，或修饰键未松开。回到正确输入框，手动按 Ctrl+Shift+V。 |
| 远程找不到图片 | 检查配置的服务器和用户、容器文件系统，以及 `/tmp` 是否被清理。 |
| 改了配置仍上传到旧服务器 | 重启辅助程序。 |

`state.json` 记录进程 ID、目标和启动时间，异常退出后可能残留；`bridge.log` 记录运行状态、远程路径和错误，不记录图片内容。日志里的 `PASTED` 仅代表 Windows 接受了模拟按键，不代表远程工具已经读取图片。

## 数据处理与当前限制

- 只有在 Windows Terminal 前台按快捷键时才读取、上传剪贴板图片。程序识别终端进程，不能识别当前是否处于 Codex、普通 shell 或密码输入界面，请在预期输入框中触发。
- 使用已有 SSH 配置、严格主机密钥检查和非交互认证，仓库不保存凭据。
- 每张图片使用远程随机目录，目录权限 `700`，文件权限 `600`。本地临时图片在上传尝试后清理；远程图片留给工具读取，由服务器策略或你手动清理。
- 上传成功后剪贴板变成路径。如果上传时你复制了新内容，则保留新内容，上传路径写入日志。
- 窗口和标题检查只能降低误粘贴风险，不能可靠区分所有标签页、分屏；上传时保持目标窗格选中。程序不会自动按回车。
- 当前支持 Windows Terminal，未适配 PuTTY、VS Code 内置终端、macOS 或 Linux 桌面。快捷键固定为 Ctrl+Alt+V。
- 上传在托盘程序的 UI 线程中执行，传输期间托盘操作可能暂停。SSH 有连接和保活限制，但当前的进程退出超时不是严格的上传全程超时。

## 测试与源码阅读

离线测试不会读取剪贴板或上传文件，`-Check` 只编译原生辅助代码，不注册快捷键：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Config.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Bridge.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Bridge.ps1 -Check
```

停止程序后，可以用 `Bridge.ps1 -CheckHotkey` 短暂注册并释放快捷键，检查是否可用。配置好服务器后，可执行真实传输测试：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Transfer.ps1
```

它自行生成 8×8 PNG，上传后检查 SHA-256、文件和目录权限，再删除测试文件与目录，不读取你的剪贴板。服务器额外需要 `sha256sum`、支持 `-c` 的 GNU `stat`、`rm` 和 `rmdir`。

建议依次阅读：

1. `Bridge.ps1` 的 `Invoke-ClipboardUpload`：主流程。
2. `Bridge.Core.ps1` 的 `Send-ImageFile`：通过 SSH 标准输入传输二进制，校验返回路径。
3. `Bridge.Native.cs`：`RegisterHotKey`、Windows 消息和 `SendInput`。
4. `Configure.ps1`、`Install.ps1`、`Uninstall.ps1`：配置和自启动管理。

PowerShell 用 `Add-Type` 在运行时编译 C#，不需要额外构建工具。许可证为 [MIT](LICENSE)。
