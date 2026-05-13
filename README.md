# DigitalShadow

> 诚实、客观、无需动手的第三方伙伴——用数据记录你的每一天。

DigitalShadow 是一个 macOS 菜单栏应用，常驻后台，自动追踪你每天在电脑上使用的应用、浏览的网页、停留时间，生成可读的 Markdown 日志，并周期性通过 LLM 进行语义总结，让你从第三人称视角看见自己的进步、专注与成长。

## 核心特性

- **全自动记录** — 开机自启，静默运行，无需任何日常操作
- **语义理解** — 不只是"打开了 Chrome"，而是"在 GitHub 上 review PR"
- **视频内容识别** — 自动拉取 YouTube/Bilibili 字幕，理解你看了什么
- **跨应用关联** — 编辑器+终端+浏览器 = 同一个开发任务，自动关联
- **每日 Markdown 日志** — 所有数据存本地，格式可读、可编辑、可迁移
- **AI 周期总结** — 调用你配置的 LLM API（OpenAI / Anthropic / 自定义），自动生成叙事总结
- **隐私优先** — 所有原始数据仅存本地，只在总结时将结构化会话摘要发给 LLM
- **菜单栏控制** — 一键暂停记录、手动触发总结、打开设置

## 安装

```bash
git clone https://github.com/129021/digital-shadow.git
cd digital-shadow
make install
```

卸载：

```bash
make uninstall
```

## 使用

1. 启动后，菜单栏会出现绿色圆点（记录中）
2. 点击图标 →「设置...」→ 填入你的 LLM API Key，选择总结频率
3. 日志自动写入 `~/DigitalShadow/logs/`
4. 随时点击「今日摘要」查看当天的活动记录
5. 点击「总结最近 N 小时」手动触发 AI 总结

## 存储结构

```
~/DigitalShadow/
├── config.json          # API Key、模型、总结频率等配置
├── activities.db        # SQLite 原始事件
├── logs/
│   ├── 2026-05-13.md              # 每日日志
│   └── 2026-05-13_14-00_summary.md # AI 总结产物
└── summaries/
    ├── 2026-W20.md     # 每周总结
    └── 2026-05.md      # 每月总结
```

## 技术栈

- **语言**: Swift 5.10+
- **平台**: macOS 14+
- **依赖**: 零外部依赖（仅 SQLite3、AppKit、URLSession）
- **数据**: SQLite + Markdown
- **AI**: OpenAI / Anthropic / 自定义兼容 API

## 架构

```
菜单栏图标 ──▶ 采集引擎（AX + NSWorkspace）
                    │
                    ▼
              SQLite 事件流 ──▶ 本地规则引擎 ──▶ Markdown 日志
                    │
                    ▼
              LLM 总结模块 ──▶ AI 叙事总结
```

## 许可证

MIT
