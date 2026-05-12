# DigitalShadow 设计文档

## 概述

DigitalShadow 是一个 macOS 本地数字足迹追踪工具。它常驻后台，自动记录用户每天在电脑上使用的应用、浏览的网页及停留时间，生成可读的每日日志（markdown 格式），并周期性地调用用户配置的 LLM API 进行语义总结，形成一个"诚实客观的第三方伙伴"视角。

### 核心原则

- **本地优先**：所有原始数据仅存本地，不上传到任何云端
- **被动不打扰**：后台静默运行，用户无需任何日常操作
- **用户可控**：随时暂停记录、配置总结频率、选择 API 提供商
- **服务主流场景**：覆盖主流应用和网站的内容识别；尊重边界，不做全知监视

---

## 运行形态

- **菜单栏图标**：绿色圆点 = 记录中，灰色 = 已暂停。Dock 无图标
- **后台守护进程**：通过 LaunchAgent 开机自启，独立于菜单栏 UI 进程
- **交互入口**：菜单栏下拉菜单提供今日摘要、手动总结、暂停/恢复、设置、退出

---

## 架构

```
菜单栏图标 (DigitalShadowMenuBar)
    │
    ▼
采集引擎 (DigitalShadowDaemon — LaunchAgent 常驻)
    │  macOS Accessibility API + NSWorkspace
    │  按秒级轮询当前活跃应用、窗口标题、URL（浏览器）
    ▼
SQLite (activities.db) — 原始事件流
    │
    ▼
本地规则引擎（同进程内）
    ├─ 应用归类（内置映射表 + NSWorkspace 自动分类）
    ├─ 窗口标题 → 可读描述
    ├─ 活动切分（空闲检测 + 应用群组变化）
    └─ 产出 sessions 表 + 实时可读毛坯日志
    │
    ├──▶ ~/DigitalShadow/logs/YYYY-MM-DD.md  （实时写入）
    │
    └──▶ LLM 总结模块
         ├─ 定时自动总结（用户设定频率：4h/8h/日/3日）
         ├─ 手动即时总结（菜单栏触发）
         └─ 周期深度总结（每周/每月）
              │
              ▼
         ~/DigitalShadow/logs/ 和 ~/DigitalShadow/summaries/
```

三个并发单元：采集不停写、规则引擎实时做毛坯、LLM 调用仅按触发条件执行，互不阻塞。

---

## 数据模型

### events — 原始事件流

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER | 自增主键 |
| timestamp | TEXT | ISO 8601，如 `2026-05-12T14:32:07.123` |
| app_name | TEXT | 应用名 |
| bundle_id | TEXT | Bundle Identifier |
| window_title | TEXT | 当前窗口标题 |
| url | TEXT (nullable) | 浏览器当前 URL（仅浏览器） |
| duration_ms | INTEGER | 该窗口停留时长 |
| app_category | TEXT | 本地分类标记 |

### sessions — 会话片段

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER | 自增主键 |
| start_time | TEXT | 会话开始时间 |
| end_time | TEXT | 会话结束时间 |
| app_group | TEXT (JSON) | 涉及的应用列表 |
| title | TEXT | 会话标题（本地毛坯 or LLM 产出） |
| summary | TEXT (nullable) | LLM 总结文本 |
| category | TEXT (nullable) | 活动分类 |
| merged_into | INTEGER (nullable) | 指向被合并的父 session（跨应用关联） |

### 活动切分规则

- 空闲超过 5 分钟 → 断开会话
- 应用群组发生显著变化（编辑工具集群 → 浏览器+通讯工具集群） → 断开会话
- 每个会话取最频繁窗口标题的转译结果作为毛坯标题

---

## 本地规则引擎

### 内置应用映射表

预装约 50 条映射，覆盖主流 macOS 应用：
Chrome/Safari/Edge/Firefox/Arc → browser
VS Code/Xcode/JetBrains 家族/Sublime → editor
Terminal/iTerm/Warp → terminal
Slack/Discord/Teams/微信/飞书/钉钉 → communication
Notion/Obsidian/Pages/Word → writing
Figma/Sketch/Photoshop → design

### 自动兜底

通过 NSWorkspace 读取应用的 App Store 分类元数据，新应用自动归类。

### 窗口标题转可读描述

关键词匹配 + 正则，将原始窗口标题转为人类可读的短描述：
- `"GitHub · Pull Request #42"` → `"浏览 GitHub PR #42"`
- `"src/login.ts — digital-shadow"` → `"编辑 login.ts"`
- `"x.com / home"` → `"浏览 X.com"`

---

## 内容增强：视频字幕获取

当检测到用户在 YouTube/Bilibili 等视频网站停留超过 N 分钟时，异步拉取公开字幕（via yt-dlp），提取前 500 字文本附到事件数据中，供 LLM 总结时使用。受 DRM 保护的视频（Netflix 等）不在此范围内。

---

## LLM 总结机制

### 触发方式

1. **定时自动总结**：用户设定频率（4h / 8h / 每天 / 每 3 天），到时自动触发
2. **手动即时总结**：菜单栏「总结最近 N 小时」，用户随时触发
3. **周期深度总结**：每周/每月，识别趋势、里程碑、分心模式

### 调用链路

```
结构化 sessions → 构造 Prompt → HTTP 调 API → 解析 JSON → 写入 .md
```

### API 配置（用户设置界面）

- 提供商选择：OpenAI / Anthropic / 自定义 OpenAI 兼容接口
- API Key
- 模型选择（默认建议经济型模型，如 GPT-4o-mini）

### Prompt 设计原则

- 输入为压缩过的 sessions 数组，不传原始事件流
- 要求输出 JSON：每个 session 的标题、分类、一句话小结、200 字内叙事
- 过滤 URL query string 和敏感信息
- 周期总结额外要求：趋势识别、里程碑、分心模式

---

## 存储结构

```
~/DigitalShadow/
├── config.json
├── activities.db
├── logs/
│   ├── 2026-05-12.md
│   └── 2026-05-12_14-00_summary.md
└── summaries/
    ├── 2026-W19.md
    └── 2026-05.md
```

### 日志格式

```markdown
# 2026-05-12 日志

## 时间线

| 时段 | 活动 | 时长 |
|------|------|------|
| 09:15-10:00 | 代码开发：digital-shadow | 45min |
| 10:00-10:15 | 浏览 Twitter | 15min |
| 10:15-11:30 | 代码评审 + Slack 沟通 | 1h15min |

## 今日总结

> 今天上午主力推进 digital-shadow 数据模型设计，期间短暂浏览社交网络...

## 应用时长统计

VS Code: 4h20min | Chrome: 2h15min | Slack: 45min | Terminal: 30min
```

---

## 技术选型

- **语言**：Swift（原生 macOS API：NSWorkspace、Accessibility、CGS）
- **数据库**：SQLite（via GRDB.swift 或直接 SQLite.swift）
- **LLM 调用**：URLSession 直接 HTTP 请求
- **打包**：标准 .app，包含守护进程和菜单栏 UI
- **开机自启**：LaunchAgent plist 写入 `~/Library/LaunchAgents/`
- **视频字幕**：yt-dlp 命令行工具（可选依赖）

---

## 设计约束

- 不在 Dock 显示，仅菜单栏图标
- 不向云端上传任何原始活动数据
- LLM 调用仅发送结构化的 session 摘要
- 用户可随时暂停记录（菜单栏一键切换）
- 用户自行配置 API Key，费用由用户承担
