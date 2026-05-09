#!/bin/sh
set -eu

DEFAULT_URL="https://open-trend-radar.test.rd.ai/"
URL="$DEFAULT_URL"
FORMAT="json"
CATEGORY=""
TOP=""
TIMEOUT="30"
SAVE_HTML=""

usage() {
  cat <<'EOF'
Usage: fetch_open_trend_radar.sh [options]

Options:
  --url URL          TrendRadar page URL. Hash fragments are ignored.
  --format json|md  Output format. Default: json.
  --category VALUE  Filter hotlist by category name or tab index.
  --top N           Limit items per group/feed.
  --timeout N       HTTP timeout in seconds. Default: 30.
  --save-html PATH  Save raw HTML to this path.
  -h, --help        Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      URL="${2:?missing value for --url}"
      shift 2
      ;;
    --format)
      FORMAT="${2:?missing value for --format}"
      shift 2
      ;;
    --category)
      CATEGORY="${2:?missing value for --category}"
      shift 2
      ;;
    --top)
      TOP="${2:?missing value for --top}"
      shift 2
      ;;
    --timeout)
      TIMEOUT="${2:?missing value for --timeout}"
      shift 2
      ;;
    --save-html)
      SAVE_HTML="${2:?missing value for --save-html}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ "$FORMAT" != "json" ] && [ "$FORMAT" != "md" ]; then
  echo "error: --format must be json or md" >&2
  exit 2
fi

REQUEST_URL="${URL%%#*}"
if [ -z "$REQUEST_URL" ]; then
  REQUEST_URL="$DEFAULT_URL"
fi

HTML_FILE="$(mktemp "${TMPDIR:-/tmp}/open-trend-radar.XXXXXX")"
trap 'rm -f "$HTML_FILE"' EXIT

curl -fsSL --compressed \
  --connect-timeout "$TIMEOUT" \
  --max-time "$TIMEOUT" \
  -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36" \
  "$REQUEST_URL" \
  -o "$HTML_FILE"

if [ -n "$SAVE_HTML" ]; then
  cp "$HTML_FILE" "$SAVE_HTML"
fi

perl -Mutf8 -MJSON::PP -MEncode=decode - "$HTML_FILE" "$REQUEST_URL" "$FORMAT" "$CATEGORY" "$TOP" <<'PERL'
use strict;
use warnings;
use open qw(:std :encoding(UTF-8));

my ($file, $source_url, $format, $category_filter, $top) = @ARGV;
$category_filter = decode("UTF-8", $category_filter) if defined $category_filter;
$top = undef if !defined($top) || $top eq "";

open my $fh, "<:encoding(UTF-8)", $file or die "cannot read $file: $!";
local $/;
my $html = <$fh>;
close $fh;

sub decode_entities {
    my ($s) = @_;
    return "" if !defined $s;
    $s =~ s/&amp;/&/g;
    $s =~ s/&quot;/"/g;
    $s =~ s/&#39;/'/g;
    $s =~ s/&apos;/'/g;
    $s =~ s/&lt;/</g;
    $s =~ s/&gt;/>/g;
    $s =~ s/&#x([0-9a-fA-F]+);/chr(hex($1))/eg;
    $s =~ s/&#([0-9]+);/chr($1)/eg;
    return $s;
}

sub clean_text {
    my ($s) = @_;
    return "" if !defined $s;
    $s =~ s/<script\b.*?<\/script>//sg;
    $s =~ s/<style\b.*?<\/style>//sg;
    $s =~ s/<[^>]+>/ /sg;
    $s = decode_entities($s);
    $s =~ s/\x{00a0}/ /g;
    $s =~ s/\s+/ /g;
    $s =~ s/^\s+|\s+$//g;
    return $s;
}

sub first_text {
    my ($html, $class) = @_;
    return clean_text($1) if $html =~ /<[^>]*class="[^"]*\Q$class\E[^"]*"[^>]*>(.*?)<\/[^>]+>/s;
    return "";
}

sub attr_href {
    my ($html) = @_;
    return decode_entities($1) if $html =~ /<a\b[^>]*href="([^"]*)"/s;
    return "";
}

sub strip_count {
    my ($s) = @_;
    $s = clean_text($s);
    $s =~ s/\s*条\s*$//;
    return $s;
}

sub parse_report {
    my %report;
    my $section = "";
    $section = $1 if $html =~ /<div class="header-info">(.*?)(?=<\/div>\s*<\/div>\s*<div class="content">)/s;
    while ($section =~ /<span class="info-label">(.*?)<\/span>\s*<span class="info-value">(.*?)<\/span>/sg) {
        my ($label, $value) = (clean_text($1), clean_text($2));
        $report{$label} = $value if $label ne "";
    }
    my $title = first_text($html, "header-title");
    $report{"标题"} = $title if $title ne "";
    return \%report;
}

sub parse_failed_platforms {
    my @items;
    if ($html =~ /<div class="error-section">(.*?)(?=<div class="rss-section">)/s) {
        my $section = $1;
        while ($section =~ /<li class="error-item">(.*?)<\/li>/sg) {
            push @items, clean_text($1);
        }
    }
    return \@items;
}

sub parse_news_item {
    my ($block) = @_;
    my $link_html = "";
    $link_html = $1 if $block =~ /<div class="news-title">(.*?)<\/div>/s;
    return {
        number => first_text($block, "news-number"),
        source => first_text($block, "source-name"),
        rank   => first_text($block, "rank-num"),
        time   => first_text($block, "time-info"),
        count  => first_text($block, "count-info"),
        title  => clean_text($link_html),
        url    => attr_href($link_html),
    };
}

sub parse_news_items {
    my ($section) = @_;
    my @items;
    while ($section =~ /<div class="news-item[^"]*">(.*?)(?=<div class="news-item[^"]*">|\z)/sg) {
        my $item = parse_news_item($1);
        push @items, $item if $item->{title} ne "";
    }
    return \@items;
}

sub parse_rss_item {
    my ($block, $feed_name) = @_;
    my $link_html = "";
    $link_html = $1 if $block =~ /<div class="rss-title">(.*?)<\/div>/s;
    my @authors;
    while ($block =~ /<span class="rss-author"[^>]*>(.*?)<\/span>/sg) {
        my $author = clean_text($1);
        push @authors, $author if $author ne "";
    }
    return {
        feed    => $feed_name,
        time    => first_text($block, "rss-time"),
        authors => \@authors,
        title   => clean_text($link_html),
        url     => attr_href($link_html),
    };
}

sub parse_rss_section {
    my ($section) = @_;
    my @feeds;
    while ($section =~ /<div class="feed-group">(.*?)(?=<div class="feed-group">|\z)/sg) {
        my $group = $1;
        my $feed_name = first_text($group, "feed-name");
        my @items;
        while ($group =~ /<div class="rss-item">(.*?)(?=<div class="rss-item">|\z)/sg) {
            my $item = parse_rss_item($1, $feed_name);
            push @items, $item if $item->{title} ne "";
        }
        push @feeds, {
            feed  => $feed_name,
            count => strip_count(first_text($group, "feed-count")),
            items => \@items,
        } if $feed_name ne "" || @items;
    }
    return {
        title => first_text($section, "rss-section-title"),
        count => strip_count(first_text($section, "rss-section-count")),
        feeds => \@feeds,
    };
}

sub parse_rss_sections {
    my @sections;
    while ($html =~ /(<div class="(?:section-divider\s+)?rss-section">.*?)(?=<div class="section-divider\s+(?:hotlist-section|standalone-section)|\z)/sg) {
        push @sections, parse_rss_section($1);
    }
    return @sections;
}

sub parse_hotlists {
    my @groups;
    while ($html =~ /<div class="word-group" data-tab-index="([^"]+)">(.*?)(?=<div class="word-group" data-tab-index="|<div class="section-divider rss-section">|\z)/sg) {
        my ($tab_index, $group) = ($1, $2);
        my $category = first_text($group, "word-name");
        push @groups, {
            tab_index => $tab_index,
            category  => $category,
            count     => strip_count(first_text($group, "word-count")),
            items     => parse_news_items($group),
        } if $category ne "";
    }
    return \@groups;
}

sub parse_standalone {
    my $section = "";
    $section = $1 if $html =~ /(<div class="section-divider standalone-section">.*?)(?=<\/div>\s*<\/div>\s*<script|\z)/s;
    return {
        title => first_text($section, "standalone-section-title"),
        count => strip_count(first_text($section, "standalone-section-count")),
        items => parse_news_items($section),
    };
}

sub filtered {
    my ($data) = @_;
    if (defined($category_filter) && $category_filter ne "") {
        my @hotlists = grep {
            $_->{tab_index} eq $category_filter || $_->{category} eq $category_filter
        } @{$data->{hotlists}};
        $data->{hotlists} = \@hotlists;

        if ($category_filter !~ /^\d+$/) {
            for my $section_name (qw(rss_new rss_updates)) {
                my @feeds = grep { $_->{feed} eq $category_filter } @{$data->{$section_name}->{feeds} || []};
                $data->{$section_name}->{feeds} = \@feeds;
            }
        }
    }

    if (defined $top) {
        for my $group (@{$data->{hotlists}}) {
            @{$group->{items}} = @{$group->{items}}[0 .. $top - 1] if @{$group->{items}} > $top;
        }
        for my $section_name (qw(rss_new rss_updates)) {
            for my $feed (@{$data->{$section_name}->{feeds} || []}) {
                @{$feed->{items}} = @{$feed->{items}}[0 .. $top - 1] if @{$feed->{items}} > $top;
            }
        }
        @{$data->{standalone}->{items}} = @{$data->{standalone}->{items}}[0 .. $top - 1]
            if @{$data->{standalone}->{items}} > $top;
    }
    return $data;
}

sub append_news_md {
    my ($lines, $items) = @_;
    if (!@$items) {
        push @$lines, "无数据", "";
        return;
    }
    for my $item (@$items) {
        my @meta = grep { $_ ne "" } ($item->{source}, $item->{rank}, $item->{time}, $item->{count});
        my $prefix = $item->{number} ne "" ? "$item->{number}. " : "- ";
        push @$lines, "$prefix\[$item->{title}\]($item->{url})";
        push @$lines, "   - " . join(" | ", @meta) if @meta;
    }
    push @$lines, "";
}

sub append_rss_md {
    my ($lines, $section) = @_;
    for my $feed (@{$section->{feeds} || []}) {
        push @$lines, "### $feed->{feed} (" . scalar(@{$feed->{items}}) . "/$feed->{count})";
        for my $item (@{$feed->{items}}) {
            my @meta = grep { $_ ne "" } ($item->{time}, join(", ", @{$item->{authors}}));
            push @$lines, "- \[$item->{title}\]($item->{url})";
            push @$lines, "  - " . join(" | ", @meta) if @meta;
        }
        push @$lines, "";
    }
}

sub render_markdown {
    my ($data) = @_;
    my @lines = ("# Open Trend Radar", "");
    if (%{$data->{report}}) {
        push @lines, "## 报告信息";
        for my $key (qw(报告类型 新闻总数 热点新闻 生成时间 标题)) {
            push @lines, "- **$key**: $data->{report}{$key}" if exists $data->{report}{$key};
        }
        push @lines, "";
    }
    if (@{$data->{failed_platforms}}) {
        push @lines, "## 请求失败平台", join(", ", @{$data->{failed_platforms}}), "";
    }
    if (@{$data->{rss_new}->{feeds} || []}) {
        push @lines, "## " . ($data->{rss_new}->{title} || "RSS 新增更新");
        append_rss_md(\@lines, $data->{rss_new});
    }
    push @lines, "## 热点分组";
    for my $group (@{$data->{hotlists}}) {
        push @lines, "### $group->{category} (" . scalar(@{$group->{items}}) . "/$group->{count})";
        append_news_md(\@lines, $group->{items});
    }
    if (@{$data->{rss_updates}->{feeds} || []}) {
        push @lines, "## " . ($data->{rss_updates}->{title} || "RSS 订阅更新");
        append_rss_md(\@lines, $data->{rss_updates});
    }
    if (@{$data->{standalone}->{items} || []}) {
        push @lines, "## " . ($data->{standalone}->{title} || "独立展示区");
        append_news_md(\@lines, $data->{standalone}->{items});
    }
    return join("\n", @lines) . "\n";
}

my @rss_sections = parse_rss_sections();
my $data = filtered({
    source_url       => $source_url,
    fetched_at       => scalar(gmtime()) . " UTC",
    report           => parse_report(),
    failed_platforms => parse_failed_platforms(),
    rss_new          => $rss_sections[0] || { title => "", count => "", feeds => [] },
    hotlists         => parse_hotlists(),
    rss_updates      => $rss_sections[1] || { title => "", count => "", feeds => [] },
    standalone       => parse_standalone(),
});

if ($format eq "json") {
    print JSON::PP->new->utf8(0)->pretty->canonical->encode($data);
} else {
    print render_markdown($data);
}
PERL
