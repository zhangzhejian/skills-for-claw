---
name: ai-agent-daily-digest
description: 获取全网最新 AI Agent 相关技术动态、产品发布，以及 OpenClaw 的商业新闻、产品更新和 GitHub 仓库最新 commits。当用户想了解 AI agent 领域最新动态、今日科技新闻、行业资讯、OpenClaw 最新进展，或者说"帮我总结一下最新的AI新闻"、"有什么新的 agent 产品"、"openclaw 最近更新了什么"时触发。即使用户没有明确说"新闻"或"摘要"，只要他们在问 AI agent 领域最近发生了什么，或想做一个信息总结，都应该使用这个技能。
---

# AI Agent 每日信息摘要

汇总 AI Agent 领域最新动态和 OpenClaw 项目进展，生成结构化中文报告。

## 核心原则

- **每条新闻必须附来源链接**。没有可验证来源的信息不要收录——链接是用户深入阅读的入口，也是信息可信度的保障。
- **报告必须包含全部三个板块**（AI Agent 动态、OpenClaw 动态、今日观察）。即使某个板块没有新信息，也要明确写出"近 24 小时未发现相关动态"，让用户知道你确实查了而不是遗漏了。
- **语言**：中文撰写，技术术语保留英文（agent、MCP、LLM 等）。
- **客观性**：如实报道，不夸大。新闻少的日子直接说明，不要凑数。

---

## 工作流程

### 第一步：信息采集

从四个渠道并行采集信息。使用你环境中可用的命令行工具和搜索工具——不同环境可能提供不同的工具（如 WebSearch、web_search、搜索 MCP 等），选择能完成任务的即可。

#### 渠道 A：RSS 订阅源（主要数据源）

运行脚本从 6 个精选 RSS 源批量获取最近 24 小时的 AI 新闻：

```bash
python3 scripts/fetch_rss.py --hours 24 --json
```

脚本路径相对于本 skill 所在目录。脚本内置以下已验证的 RSS 源：
- Hacker News（AI agent 过滤）— 开发者社区热点
- TechCrunch AI — 科技媒体头条
- VentureBeat AI — 企业 AI 动态
- MIT Technology Review — 深度技术报道
- OpenAI Blog — OpenAI 官方博客
- Google AI Blog — Google AI 官方博客

脚本输出 JSON，包含 `articles` 数组，每篇文章有 `source`、`title`、`link`、`published`、`summary`、`relevance` 字段。已按相关性排序，优先处理高 relevance 的条目。

**如果脚本不可用或执行失败**，直接用搜索工具搜索（见渠道 B）。

#### 渠道 B：搜索补充（补充数据源）

RSS 覆盖不到的信息用搜索工具补充，重点补充以下方向：
- **中文源**："AI agent 最新动态"、"AI 智能体 新产品 发布"、"大模型 agent 更新"
- **融资与商业**："AI agent startup funding"、"AI agent 收购 合作"
- **RSS 未覆盖的厂商**：Anthropic、Mistral、Meta AI 等的最新动态

这一步的目的是填补 RSS 的盲区，不需要重复 RSS 已经覆盖的信息。

#### 渠道 C：OpenClaw 新闻

搜索 OpenClaw 相关的商业与产品新闻：
- "OpenClaw AI"
- "OpenClaw product update"
- "OpenClaw announcement"

#### 渠道 D：OpenClaw GitHub 仓库

运行脚本获取 GitHub 数据：

```bash
python3 scripts/fetch_github.py openclaw/openclaw --hours 24
```

脚本路径相对于本 skill 所在目录。脚本输出 JSON，包含 commits、pull_requests、releases 三个字段。

**如果脚本不可用或执行失败**，用以下任一方式降级：
- 用 `gh api` 命令（如果 `gh` CLI 可用）
- 用 `curl` 直接调用 GitHub REST API
- 用搜索工具搜索 "github.com/openclaw/openclaw recent commits"

**如果 GitHub API 返回 404**（仓库不存在），在报告中如实说明，不要编造数据。

### 第二步：筛选与去重

- 同一事件从多个来源获取时，合并为一条，保留最权威的来源链接
- 过滤纯广告和无实质内容的推广
- 确认时效性：只保留最近 24 小时的信息
- 按重要性排序：重大发布 > 技术更新 > 融资消息 > 其他

### 第三步：生成报告

严格按照以下结构输出报告。这个结构不是建议而是必须遵循的骨架——用户依赖固定的板块结构来快速定位信息。

```markdown
# AI Agent 每日信息摘要

> 生成时间：YYYY-MM-DD HH:MM
> 检索范围：最近 24 小时

---

## 一、AI Agent 重要动态

### [新闻标题]
- **来源**：[来源名称](URL)
- **摘要**：2-3 句话概括核心内容
- **影响分析**：一句话点评对 AI agent 生态的影响

（按重要性排列 5-10 条。每条必须有来源链接。）

---

## 二、OpenClaw 动态

### 商业与产品新闻
（OpenClaw 相关的新闻报道、产品更新。如无，写"近 24 小时未发现相关动态。"）

### GitHub 仓库更新

#### 最新 Commits
| 时间 | SHA | 作者 | 提交信息 |
|------|-----|------|----------|
| ...  | ... | ...  | ...      |

（如无 commits，写"近 24 小时无新 commits。"）

#### 活跃 Pull Requests
| PR   | 标题 | 状态        | 作者 |
|------|------|-------------|------|
| #N   | ...  | open/merged | ...  |

（如无活跃 PR，写"近期无活跃 PR。"）

#### 开发趋势分析
基于 commits 和 PRs 总结当前开发重点与方向。如数据不足，简述仓库当前状态。

---

## 三、今日观察

对当天 AI agent 领域整体趋势的 3-5 句话点评。指出最值得关注的动态，以及这些动态反映的行业方向。
```

### 第四步：保存报告

将报告保存为 `ai_agent_digest_YYYYMMDD.md` 文件（日期为当天日期）。
