# SillyTavern Termux

在安卓手机上一条命令装好 [SillyTavern](https://github.com/SillyTavern/SillyTavern)（酒馆），并附一个输数字就能用的管理面板。

不需要电脑、不需要服务器，也不用额外折腾网络。

> Apache-2.0 · 免费使用 · 可商用

---

## 它做什么

Termux 里粘一条命令，剩下的它自己办。**按你的网络选一条**：

**国内网络（推荐，直连 Gitee）**

```bash
curl -fsSL https://gitee.com/luyao23333/silly-tavern-termux/raw/main/install.sh | bash
```

**海外网络**

```bash
curl -fsSL https://raw.githubusercontent.com/luyao20000315-sketch/SillyTavern-Termux/main/install.sh | bash
```

它会自动：

1. 把 apt 源换成国内镜像（换不动就自动回滚，不会把你的源搞坏）
2. 装 git / node / curl
3. 拉酒馆本体，锁定 v1.18.0
4. `npm install`
5. 生成管理面板 `~/st.sh`，并写入 `st` 别名

装完重开一个 Termux 窗口，输入 `st`：

```
┌────────────────────────────────────────────┐
│  酒馆控制台                          已停止 │
├────────────────────────────────────────────┤
│  [1] 启动        [2] 停止      [3] 重启    │
│  [4] 状态        [5] 日志                  │
├────────────────────────────────────────────┤
│  [6] 更新版本    [7] 酒馆助手              │
│  [8] 备份数据    [9] 恢复数据              │
├────────────────────────────────────────────┤
│  [10] 卸载酒馆   [0] 退出                  │
└────────────────────────────────────────────┘
```

启动后手机浏览器打开 `http://127.0.0.1:8000`。

---

## 装 Termux

手机必须先有 Termux。**别用 Google Play 里那个**，那版早就停更了，跑不起来。

二选一：

- **F-Droid（推荐）** 打开 <https://f-droid.org/packages/com.termux/>，在「版本」列表里点最新版旁边的 Download APK。不用装 F-Droid 客户端。
- **GitHub 直接下** <https://github.com/termux/termux-app/releases/download/v0.118.3/termux-app_v0.118.3+github-debug_universal.apk>
  （113MB，全架构通用，什么手机都能装。手机是 arm64 的话可以换成 `..._arm64-v8a.apk`，只有 35MB）

装好打开，输入 `pkg --version` 能打印出版本号就对了。

---

## 面板里的各项

| 选项 | 做什么 |
|------|--------|
| `[1]` 启动 | 后台起服务，**等端口真的响应了才报成功**；进程中途挂了会直接把日志尾巴甩给你 |
| `[2]` `[3]` | 停止 / 重启。只杀酒馆自己的进程，不会误伤手机上其他 node |
| `[4]` 状态 | 进程 PID、端口探测结果、当前版本、备份份数 |
| `[5]` 日志 | 最近 30 行。跟实时用 `tail -f ~/.st-logs/server.log` |
| `[6]` 更新 | 切到最新正式版。**国内镜像同步会慢**，检测到官方有更新版时会问你要不要临时从 GitHub 拉 |
| `[7]` 酒馆助手 | 装 / 更新 Tavern Helper（给酒馆加功能的扩展） |
| `[8]` 备份 | 把 `data/` 和 `config.yaml` 打包到 `~/.st-snapshots/` |
| `[9]` 恢复 | 从备份还原。**恢复前会先给你当前的数据也存一份** |
| `[10]` 卸载 | 删掉酒馆，Termux 环境保留 |

---

## 保活

玩的时候 Termux 被系统杀掉，酒馆就断了。三个都做上比较稳：

- 挂成小窗 / 分屏
- 系统设置 → 电池 → Termux → 改成「无限制」
- 长按 Termux 卡片 → 锁定

---

## 数据在哪

| 东西 | 位置 |
|------|------|
| 聊天记录、角色卡、设置 | `~/SillyTavern/data` |
| 配置文件 | `~/SillyTavern/config.yaml` |
| 服务日志 | `~/.st-logs/server.log` |
| 备份包 | `~/.st-snapshots/` |

> ⚠️ `config.yaml` 里存着你的 API Key。备份包发人之前想清楚。

想拷到电脑或网盘：

```bash
termux-setup-storage          # 只需执行一次，然后重启 Termux
tar -czf ~/storage/shared/st-data.tar.gz -C ~/SillyTavern data config.yaml
```

---

## 卸载

- **只卸载酒馆** —— 面板 `[10]`，或 `rm -rf ~/SillyTavern`
- **整个 Termux 都不要了** —— 安卓设置 → 应用 → Termux → 卸载

> ⚠️ 卸 Termux 会连聊天记录一起清空。先备份。

装回来：重跑上面那条 `curl` 命令，然后面板 `[9]` 恢复数据。

---

## 下载走的哪些源

所有下载都是国内优先、国外兜底，自动切换：

| 下载内容 | 国内 | 国外 |
|---------|------|------|
| 酒馆本体 | Gitee `mirrors/sillytavern` | GitHub `SillyTavern/SillyTavern` |
| 酒馆助手 | GitLab `novi028/JS-Slash-Runner` | GitHub `N0VI028/JS-Slash-Runner` |
| npm 依赖 | npmmirror | npm 官方 |
| apt 软件包 | 清华 TUNA | Termux 官方 |

国内源全部失败才会走国外，你不用管。

---

## 常见问题

**卡住不动 / 特别慢**
apt 源换成清华了还慢，多半是 npm 那步。等它跑完；真卡死了 Ctrl+C 重跑，装过的部分会跳过。

**报 `CANNOT LINK ... SSL_set_quic_tls_transport_params`**
Termux 里的包版本错位了，通常是手动装过东西造成的。脚本检测到这个会自动跑 `apt full-upgrade` 修复后重试。手动修也一样：

```bash
apt update && apt full-upgrade -y
```

注意是 `apt`，**别用 `pkg upgrade`** —— `pkg` 内部要调 curl，而 curl 这时候已经崩了，它会跟着一起崩。

**输入 `st` 提示 command not found**
别名是写进 `~/.bashrc` 的，得重开一个 Termux 窗口才生效。当前窗口直接用 `bash ~/st.sh`。

**启动失败，红色报错**
脚本不会假装成功。看面板 `[5]` 的日志。多半是 8000 端口被占，或者依赖没装全（那就再跑一次 `install.sh`）。

**更新时提示"当前源最高 X，官方已有 Y"**
Gitee 镜像同步有延迟。选 `y` 就从 GitHub 官方拉，慢一点但版本新。

**卸载重装后聊天记录还在吗**
在 `~/.st-snapshots/` 里（那是 Termux 内部目录，别把 Termux 卸载了）。卸 Termux 之前先按上面「数据在哪」拷到手机存储。

---

## 自己改

面板是 `install.sh` 里一段 `<<'ST_PANEL_EOF'` 的 heredoc 生成的 —— 装完写到 `~/st.sh`。这么设计是为了 `curl | bash` 装完立刻就有面板，不用第二次联网。**改菜单就改那段 heredoc。**

改完两处都验一下语法：

```bash
bash -n install.sh
sed -n "/<<'ST_PANEL_EOF'/,/^ST_PANEL_EOF$/p" install.sh | sed '1d;$d' | bash -n
```

没手机也能测面板：造个假的 `~/SillyTavern`（有 `data/` 和 `config.yaml` 就行），把面板常量的路径指过去，然后喂输入驱动它：

```bash
printf '8\n\n4\n\n9\n1\nn\n\n0\n' | bash /tmp/panel.sh   # 备份→状态→恢复→退出
```

---

## 许可证

Apache License 2.0，见 [LICENSE](LICENSE)。商用、修改、再分发都可以。
