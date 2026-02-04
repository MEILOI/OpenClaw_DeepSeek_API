# OpenClaw_DeepSeek_API





###  项目简介 
⚡️ OpenClaw + DeepSeek API 接入脚本 (Auto-Patcher)

 🚀 由于官方未支持DeepSeek API接入,所以为 OpenClaw 打造的 DeepSeek 接入脚本。

   一键自动化脚本：智能源码补丁 + NVM环境自适应 + Systemd进程守护。完美支持 DeepSeek-V3/R1。








## 🚀 一键安装 (One-Line Install)

无需手动下载，无需繁琐配置。复制下方命令至 VPS 终端（Root/Sudo），**自动完成下载、赋权、执行全流程：**

```
curl -fsSL https://raw.githubusercontent.com/MEILOI/OpenClaw_DeepSeek_API/main/deepseek-installer.sh -o deepseek-installer.sh && chmod +x deepseek-installer.sh && sudo ./deepseek-installer.sh

```

> **脚本将自动执行以下操作：**
> 1. 🔍 **环境嗅探**：自动识别 NVM、Homebrew 或系统自带 Node.js 路径。
> 2. 💉 **源码注入**：智能定位 OpenClaw 核心库，植入 DeepSeek 兼容驱动。
> 3. ⚙️ **配置生成**：自动写入 `openclaw.json` 标准配置文件。
> 4. 🛡️ **服务守护**：创建 Systemd 服务，确保开机自启、崩溃重启。
> 5. 🔗 **自动配对**：自动抓取并显示 Telegram 配对码。
> 
> 

---

## 💎 为什么选择本脚本？

| 特性 | 说明 |
| --- | --- |
| **🧬 全环境自适应** | 无论你是用 `apt`、`yum` 还是 `nvm` 安装的 Node.js，脚本都能精准定位，不再报错“找不到目录”。 |
| **💊 智能源码补丁** | 并非简单的替换文件，而是采用**AST 级逻辑定位**，无视版本号变化，精准注入兼容代码。 |
| **🛡️ 绝对路径守护** | 自动解析 Node.js 绝对路径写入 Systemd，彻底解决 VPS 重启后服务无法启动的顽疾。 |
| **🔙 安全回滚机制** | 修改前自动生成 `.backup` 备份文件，如果不满意，随时还原。 |

---

## 🧩 支持模型列表

安装后，OpenClaw 将原生支持以下模型（已预设最佳参数）：

* **`deepseek-chat` (DeepSeek-V3)**
* *特点：* 极速、超低成本、通用性强。（默认首选）


* **`deepseek-reasoner` (DeepSeek-R1)**
* *特点：* 深度推理、思维链 (CoT)、逻辑分析。



---

## 🛠️ 使用指南

1. 准备好 **DeepSeek API Key** (`sk-xxxx`)。
2. 准备好 **Telegram Bot Token**。
3. 执行一键脚本。
4. 脚本运行结束后，复制终端显示的配对码，去 Telegram 发送给机器人即可。

---

## ❓ FAQ

* **Q: 脚本对 OpenClaw 版本有要求吗？**
* A: 适配 OpenClaw 2026.2.x 及以上版本。


* **Q: 如何更新？**
* A: 如果 OpenClaw 官方更新导致补丁失效，只需重新运行一次本脚本即可。


* **Q: 安全吗？**
* A: 脚本开源透明，仅修改本地文件，API Key 仅用于生成本地配置文件，绝无上传。





*Project maintained by TheX-MEILOI*

