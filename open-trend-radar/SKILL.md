---
name: open-trend-radar
description: 获取 open-trend-radar.test.rd.ai 的热点新闻雷达数据，解析页面内嵌的热点分组、RSS 更新、失败平台和独立展示区。当用户询问 open-trend-radar、TrendRadar、热点新闻分析、热点 tab 数据、新闻雷达数据如何获取，或需要从 https://open-trend-radar.test.rd.ai 导出结构化新闻数据时使用。
---

# Open Trend Radar 数据获取

从 `https://open-trend-radar.test.rd.ai/` 获取热点新闻分析页面，并把页面内嵌数据解析成 JSON 或 Markdown。

## 数据来源判断

该站点当前不是通过公开 JSON API 动态加载数据；服务端直接返回完整 HTML，新闻数据嵌在 DOM 中。URL 的 `#tab-0` 只是前端 hash，用于切换页面 tab，抓取时请求根路径即可。

核心结构：
- 页面头部：`.header-info`
- 请求失败平台：`.error-section .error-item`
- RSS 新增更新：页面顶部 `.rss-section`，包含 `.feed-group .rss-item`
- 热点分组：`.word-group[data-tab-index]`，每组包含 `.word-name` 和 `.news-item`
- RSS 订阅更新：带 `.section-divider.rss-section` 的后续 RSS 区块
- 独立展示区：`.standalone-section .news-item`

## 快速使用

在本 skill 目录下运行：

```bash
python3 scripts/fetch_open_trend_radar.py --format json
```

常用参数：

```bash
# 只看某个 tab/分类，支持分类名或 tab index
python3 scripts/fetch_open_trend_radar.py --category 大模型与AI --format md
python3 scripts/fetch_open_trend_radar.py --category 0 --format json

# 限制每个分组输出数量
python3 scripts/fetch_open_trend_radar.py --top 5 --format md

# 保存原始 HTML 方便排查 DOM 变化
python3 scripts/fetch_open_trend_radar.py --save-html /tmp/open-trend-radar.html

# 指定页面 URL；hash 可有可无
python3 scripts/fetch_open_trend_radar.py --url 'https://open-trend-radar.test.rd.ai/#tab-0'
```

## 输出字段

JSON 顶层包含：
- `source_url`: 实际请求 URL
- `fetched_at`: 抓取时间
- `report`: 报告类型、新闻总数、热点新闻、生成时间等头部信息
- `failed_platforms`: 请求失败平台列表
- `rss_new`: 顶部 RSS 新增更新
- `hotlists`: 热点 tab 分组，每组含 `tab_index`、`category`、`count`、`items`
- `rss_updates`: RSS 订阅更新
- `standalone`: 独立展示区

新闻 item 常见字段：
- `number`
- `source`
- `rank`
- `time`
- `count`
- `title`
- `url`

## 使用建议

- 回答“数据如何获取”时，说明这是静态 HTML 内嵌数据，可用 `curl`/`requests` 拉页面后按 CSS selector 解析。
- 如果脚本解析数量明显异常，先用 `--save-html` 保存页面，再检查上述 CSS selector 是否变更。
- 若用户要二次分析，优先输出 JSON；若用户要阅读摘要，使用 Markdown。
