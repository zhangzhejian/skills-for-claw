---
name: ai-agent-daily-digest
description: 获取全网最新 AI Agent 相关技术动态、产品发布，以及 OpenClaw 的商业新闻、产品更新和 GitHub 仓库最新 commits。当用户想了解 AI agent 领域最新动态、今日科技新闻、行业资讯、OpenClaw 最新进展，或者说"帮我总结一下最新的AI新闻"、"有什么新的 agent 产品"、"openclaw 最近更新了什么"时触发。即使用户没有明确说"新闻"或"摘要"，只要他们在问 AI agent 领域最近发生了什么，或想做一个信息总结，都应该使用这个技能。
---

# AI Agent 每日信息摘要

汇总 AI Agent 领域最新动态和 OpenClaw 项目进展，生成结构化中文报告。

## 工作流程

### 1. 信息采集

并行使用 WebSearch 和 Bash 工具从多个渠道采集信息。所有搜索限定在最近 24 小时内。

#### 1.1 AI Agent 技术与产品动态

使用 WebSearch 工具进行以下搜索（并行执行，越广越好）：

```
搜索查询示例（根据当天热点灵活调整）：
- "AI agent" new release OR launch OR update today
- LLM agent framework new 2026
- autonomous agent AI product launch
- AI coding agent update
- AI agent startup funding OR announcement
- Claude OR GPT OR Gemini agent update
- MCP server new tool
- AI workflow automation new
- agentic AI news today
```

同时搜索中文渠道：
```
- AI agent 最新动态
- AI 智能体 新产品 发布
- 大模型 agent 框架 更新
```

关注的信息类型：
- **新产品/工具发布**：新的 AI agent 产品、框架、平台
- **重大技术更新**：现有产品的重要版本更新、新功能
- **融资/商业动态**：AI agent 相关公司融资、收购、合作
- **开源项目**：新的开源 agent 框架、工具链
- **技术突破**：agent 相关的研究进展、benchmark 突破

#### 1.2 OpenClaw 动态

使用 WebSearch 搜索 OpenClaw 相关新闻：
```
- "OpenClaw" AI
- OpenClaw product update
- OpenClaw announcement
```

#### 1.3 OpenClaw GitHub 仓库更新

使用 GitHub API 获取最新 commits 和活动：

```bash
# 获取最近 24 小时的 commits
gh api repos/openclaw/openclaw/commits \
  --jq '.[] | {sha: .sha[0:7], message: .commit.message, author: .commit.author.name, date: .commit.author.date}' \
  -q 'since='$(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ) 2>/dev/null || \
curl -s "https://api.github.com/repos/openclaw/openclaw/commits?since=$(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ)" | \
  python3 -c "import sys,json; [print(f\"{c['sha'][:7]} | {c['commit']['author']['name']} | {c['commit']['message'].split(chr(10))[0]}\") for c in json.load(sys.stdin)]"
```

```bash
# 获取最近的 PRs
gh api repos/openclaw/openclaw/pulls?state=all\&sort=updated\&direction=desc\&per_page=10 \
  --jq '.[] | {number: .number, title: .title, state: .state, user: .user.login, updated: .updated_at}' 2>/dev/null || \
curl -s "https://api.github.com/repos/openclaw/openclaw/pulls?state=all&sort=updated&direction=desc&per_page=10"
```

```bash
# 获取最近的 releases（如果有）
gh api repos/openclaw/openclaw/releases?per_page=3 \
  --jq '.[] | {tag: .tag_name, name: .name, date: .published_at, body: .body[0:200]}' 2>/dev/null || \
curl -s "https://api.github.com/repos/openclaw/openclaw/releases?per_page=3"
```

如果 `gh` 不可用，回退到 curl + GitHub REST API。如果 GitHub API 因 rate limit 被拒，用 WebFetch 直接访问仓库页面提取信息。

### 2. 信息筛选与整理

采集完成后：
- 去重：同一事件从多个来源获取的信息合并
- 过滤噪音：去掉纯广告、无实质内容的推广
- 验证时效：确保信息确实是最近 24 小时内的
- 按重要性排序：重大发布 > 技术更新 > 融资消息 > 其他

### 3. 生成报告

按以下模板生成中文 Markdown 报告：

```markdown
# AI Agent 每日信息摘要

> 生成时间：YYYY-MM-DD HH:MM
> 检索范围：最近 24 小时

---

## 一、AI Agent 重要动态

### [新闻标题]
- **来源**：[来源网站/链接]
- **摘要**：2-3 句话概括核心内容
- **影响分析**：对 AI agent 生态的潜在影响

（按重要性排列，通常 5-10 条）

---

## 二、OpenClaw 动态

### 商业与产品新闻
（如果有 OpenClaw 相关的新闻报道、产品更新公告等）

### GitHub 仓库更新

#### 最新 Commits
| 时间 | SHA | 作者 | 提交信息 |
|------|-----|------|----------|
| ... | ... | ... | ... |

#### 活跃 Pull Requests
| PR | 标题 | 状态 | 作者 |
|----|------|------|------|
| #N | ... | open/merged | ... |

#### 开发趋势分析
基于最近的 commits 和 PRs，总结 OpenClaw 团队当前的开发重点和方向。

---

## 三、今日观察

对当天 AI agent 领域的整体趋势做 3-5 句话的点评，指出最值得关注的动态。
```

### 要点

- **语言**：报告使用中文，但技术术语保留英文（如 agent、MCP、LLM）
- **链接**：每条新闻都要附上来源链接，方便用户深入阅读
- **客观性**：如实报道，不夸大不缩小。如果某天没什么大新闻，直接说明
- **OpenClaw 特别关注**：即使 OpenClaw 当天没有新闻，也要检查 GitHub 活动并报告
- **输出**：将报告保存为 `ai_agent_digest_YYYYMMDD.md`
