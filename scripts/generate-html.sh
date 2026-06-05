#!/bin/sh
# generate-html.sh — Produce a self-contained HTML decision log from analyst
# and adversary JSON outputs.
#
# Usage:
#   generate-html.sh [--decisions FILE] [--findings FILE] [--output FILE]
#
# All arguments are optional. Defaults:
#   --decisions  /tmp/decision-log.json
#   --findings   /tmp/adversary-findings.json  (skipped if missing)
#   --output     /tmp/decision-log.html
#
# Requires: jq

set -e

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DECISIONS="/tmp/decision-log.json"
FINDINGS="/tmp/adversary-findings.json"
OUTPUT="/tmp/decision-log.html"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --decisions)
      if [ -z "$2" ] || echo "$2" | grep -q '^-'; then
        echo "Error: --decisions requires a file path" >&2; exit 1
      fi
      DECISIONS="$2"; shift 2 ;;
    --findings)
      if [ -z "$2" ] || echo "$2" | grep -q '^-'; then
        echo "Error: --findings requires a file path" >&2; exit 1
      fi
      FINDINGS="$2"; shift 2 ;;
    --output)
      if [ -z "$2" ] || echo "$2" | grep -q '^-'; then
        echo "Error: --output requires a file path" >&2; exit 1
      fi
      OUTPUT="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--decisions FILE] [--findings FILE] [--output FILE]"
      echo ""
      echo "Generate a self-contained HTML decision log."
      echo ""
      echo "Options:"
      echo "  --decisions FILE   Decision log JSON (default: /tmp/decision-log.json)"
      echo "  --findings FILE    Adversary findings JSON (default: /tmp/adversary-findings.json)"
      echo "  --output FILE      Output HTML file (default: /tmp/decision-log.html)"
      echo "  -h, --help         Show this help"
      exit 0
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2; exit 1 ;;
    *)
      echo "Error: Unexpected argument: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not found. Install it: brew install jq" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------
if [ ! -f "$DECISIONS" ]; then
  echo "Error: Decision log not found: $DECISIONS" >&2
  exit 1
fi

if ! jq empty "$DECISIONS" 2>/dev/null; then
  echo "Error: Invalid JSON in decision log: $DECISIONS" >&2
  exit 1
fi

# Findings are optional — generate without adversary sections if missing
FINDINGS_JSON="null"
if [ -f "$FINDINGS" ]; then
  if ! jq empty "$FINDINGS" 2>/dev/null; then
    echo "Warning: Invalid JSON in findings file, skipping: $FINDINGS" >&2
  else
    FINDINGS_JSON=$(jq -c '.' "$FINDINGS" | sed 's/</\\u003c/g; s/>/\\u003e/g')
  fi
fi

# Read and sanitize decision log JSON for safe <script> embedding
DECISIONS_JSON=$(jq -c '.' "$DECISIONS" | sed 's/</\\u003c/g; s/>/\\u003e/g')

# Extract page title
PAGE_TITLE=$(jq -r '"Decision Log — " + (.repository // "Session")' "$DECISIONS")

# ---------------------------------------------------------------------------
# Generate HTML
# ---------------------------------------------------------------------------
{

# ── Head ──────────────────────────────────────────────────────────────────
cat <<'HTMLHEAD'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
HTMLHEAD

printf '<title>%s</title>\n' "$PAGE_TITLE"

cat <<'HTMLSTYLE'
<style>
*,*::before,*::after{box-sizing:border-box}
body{margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif,
  'Apple Color Emoji','Segoe UI Emoji';line-height:1.5;color:var(--text);background:var(--bg)}
code,pre,.code-ref{font-family:'SF Mono','Fira Code','Cascadia Code','Consolas',monospace}

/* ── Light theme ── */
:root{
  --bg:#ffffff;--bg-card:#f6f8fa;--bg-elevated:#ffffff;--bg-code:#eff1f3;
  --text:#1f2328;--text-secondary:#656d76;--text-muted:#8b949e;
  --border:#d0d7de;--border-subtle:#e8eaed;
  --green:#1a7f37;--green-bg:#dafbe1;
  --yellow:#9a6700;--yellow-bg:#fff8c5;
  --red:#cf222e;--red-bg:#ffebe9;
  --blue:#0969da;--blue-bg:#ddf4ff;
  --orange:#bc4c00;--orange-bg:#fff1e5;
  --shadow:0 1px 3px rgba(0,0,0,0.04);
  --focus-ring:0 0 0 3px rgba(9,105,218,0.3)
}
/* ── Dark theme ── */
@media(prefers-color-scheme:dark){:root{
  --bg:#0d1117;--bg-card:#161b22;--bg-elevated:#1c2128;--bg-code:#1c2128;
  --text:#e6edf3;--text-secondary:#7d8590;--text-muted:#484f58;
  --border:#30363d;--border-subtle:#21262d;
  --green:#3fb950;--green-bg:rgba(63,185,80,0.12);
  --yellow:#d29922;--yellow-bg:rgba(210,153,34,0.12);
  --red:#f85149;--red-bg:rgba(248,81,73,0.12);
  --blue:#58a6ff;--blue-bg:rgba(88,166,255,0.12);
  --orange:#db6d28;--orange-bg:rgba(219,109,40,0.12);
  --shadow:0 1px 3px rgba(0,0,0,0.3);
  --focus-ring:0 0 0 3px rgba(88,166,255,0.3)
}}

/* ── Layout ── */
.container{max-width:900px;margin:0 auto;padding:32px 20px}

/* ── Header ── */
.header{margin-bottom:40px}
.header h1{font-size:28px;font-weight:700;margin:0 0 8px;letter-spacing:-0.02em}
.session-info{display:flex;flex-wrap:wrap;gap:16px;margin-bottom:16px;color:var(--text-secondary);font-size:14px}
.session-info code{font-size:12px;background:var(--bg-code);padding:2px 6px;border-radius:4px}
.stats-bar{display:flex;flex-wrap:wrap;gap:20px;padding:16px 20px;background:var(--bg-card);
  border:1px solid var(--border);border-radius:10px;box-shadow:var(--shadow)}
.stat{display:flex;flex-direction:column;gap:2px}
.stat-label{font-size:11px;text-transform:uppercase;letter-spacing:0.6px;color:var(--text-muted);font-weight:600}
.stat-value{font-size:16px;font-weight:600;display:flex;align-items:center;gap:6px}

/* ── Confidence dots ── */
.dot{display:inline-block;width:10px;height:10px;border-radius:50%;flex-shrink:0}
.dot.high{background:var(--green)}.dot.medium{background:var(--yellow)}.dot.low{background:var(--red)}

/* ── Section ── */
.section{margin-bottom:48px}
.section>h2{font-size:20px;font-weight:700;margin:0 0 20px;padding-bottom:10px;
  border-bottom:2px solid var(--border-subtle);letter-spacing:-0.01em}

/* ── Decision cards ── */
.decision-card{position:relative;margin-bottom:14px;padding:16px 16px 16px 20px;
  background:var(--bg-card);border:1px solid var(--border);border-radius:10px;
  border-left:4px solid var(--border);box-shadow:var(--shadow);transition:box-shadow 0.3s}
.decision-card.high{border-left-color:var(--green)}
.decision-card.medium{border-left-color:var(--yellow)}
.decision-card.low{border-left-color:var(--red)}
.decision-header{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.decision-num{font-weight:700;font-size:13px;color:var(--text-secondary);white-space:nowrap}
.decision-summary{font-weight:600;font-size:15px;flex:1;min-width:0}
.chose-line{font-size:13px;color:var(--text-secondary);margin:4px 0 0}
.chose-line strong{color:var(--text);font-weight:600}

/* ── Source badge ── */
.badge{font-size:10px;padding:2px 8px;border-radius:10px;font-weight:600;text-transform:uppercase;
  letter-spacing:0.4px;white-space:nowrap}
.badge.breadcrumb{background:var(--green-bg);color:var(--green)}
.badge.implicit{background:var(--yellow-bg);color:var(--yellow)}

/* ── Expandable details ── */
.decision-card details{margin-top:10px}
.decision-card details summary{cursor:pointer;user-select:none;font-size:13px;
  color:var(--blue);font-weight:500;list-style:none;padding:4px 0}
.decision-card details summary::-webkit-details-marker{display:none}
.decision-card details summary::marker{display:none;content:''}
.decision-card details summary::before{content:'▶ ';font-size:9px;margin-right:2px}
.decision-card details[open] summary::before{content:'▼ '}
.detail-body h4{font-size:11px;text-transform:uppercase;letter-spacing:0.6px;color:var(--text-muted);
  margin:14px 0 4px;font-weight:700}
.detail-body p{margin:0 0 6px;font-size:14px;line-height:1.6}
.detail-body ul{margin:0 0 8px;padding-left:20px;font-size:14px}
.detail-body li{margin-bottom:4px}

/* ── Impact callout ── */
.impact-box{padding:12px 14px;background:var(--blue-bg);border-left:3px solid var(--blue);
  border-radius:0 8px 8px 0;margin:10px 0}
.impact-box h4{color:var(--blue);margin-top:0}

/* ── Code refs ── */
.code-ref{font-size:12px;background:var(--bg-code);padding:2px 6px;border-radius:4px;
  white-space:nowrap}

/* ── Links ── */
.dep-link{color:var(--blue);cursor:pointer;text-decoration:none;font-weight:500}
.dep-link:hover{text-decoration:underline}

/* ── Dependency tree ── */
.dep-tree{padding:16px 20px;background:var(--bg-card);border:1px solid var(--border);
  border-radius:10px;font-size:13px;line-height:1.7;white-space:pre;overflow-x:auto;
  box-shadow:var(--shadow)}

/* ── Severity badges ── */
.sev-badge{font-size:11px;font-weight:700;padding:2px 8px;border-radius:10px;white-space:nowrap}
.sev-badge.critical{background:var(--red-bg);color:var(--red)}
.sev-badge.significant{background:var(--orange-bg);color:var(--orange)}
.sev-badge.questionable{background:var(--yellow-bg);color:var(--yellow)}
.sev-badge.info{background:var(--blue-bg);color:var(--blue)}

/* ── Finding cards ── */
.finding-card{margin-bottom:12px;padding:14px 14px 14px 18px;background:var(--bg-card);
  border:1px solid var(--border);border-radius:10px;border-left:4px solid var(--border);
  box-shadow:var(--shadow)}
.finding-card.critical{border-left-color:var(--red)}
.finding-card.significant{border-left-color:var(--orange)}
.finding-card.questionable{border-left-color:var(--yellow)}

/* ── Inline finding (within decision card) ── */
.inline-finding{margin-top:10px;padding:10px 12px;border-radius:8px;font-size:13px;line-height:1.5}
.inline-finding.escalation{background:var(--yellow-bg)}
.inline-finding.auto-fork{background:var(--blue-bg)}
.inline-finding.code-issue.critical{background:var(--red-bg)}
.inline-finding.code-issue.significant{background:var(--orange-bg)}
.inline-finding.code-issue.questionable{background:var(--yellow-bg)}

/* ── Footer ── */
.footer{text-align:center;padding:24px 0;font-size:12px;color:var(--text-muted);
  border-top:1px solid var(--border-subtle);margin-top:48px}

/* ── Responsive ── */
@media(max-width:640px){
  .container{padding:16px 12px}
  .stats-bar{flex-direction:column;gap:12px}
  .session-info{flex-direction:column;gap:6px}
  .decision-header{gap:6px}
}
</style>
</head>
<body>
<div id="app"></div>
<script>
HTMLSTYLE

# ── Inject JSON data ─────────────────────────────────────────────────────
printf 'var DATA=%s;\n' "$DECISIONS_JSON"
printf 'var FINDINGS=%s;\n' "$FINDINGS_JSON"

# ── Client-side rendering ────────────────────────────────────────────────
cat <<'HTMLJS'
(function() {
  'use strict';

  var app = document.getElementById('app');

  /* ════════════════════════════════════════════════════════════════════════
     Utilities
     ════════════════════════════════════════════════════════════════════════ */

  function esc(s) {
    if (s == null) return '';
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }

  function dot(level) {
    return '<span class="dot ' + level + '" title="' + level + ' confidence"></span>';
  }

  function normSev(sev) {
    if (!sev) return 'questionable';
    var s = String(sev).toLowerCase();
    if (s.indexOf('critical') !== -1 || s === 'high') return 'critical';
    if (s.indexOf('significant') !== -1 || s === 'medium') return 'significant';
    if (s.indexOf('info') !== -1) return 'info';
    return 'questionable';
  }

  function sevBadge(sev) {
    var n = normSev(sev);
    var labels = { critical:'\uD83D\uDD34 Critical', significant:'\uD83D\uDFE0 Significant',
                   questionable:'\uD83D\uDFE1 Questionable', info:'\uD83D\uDD35 Info' };
    return '<span class="sev-badge ' + n + '">' + (labels[n] || esc(sev)) + '</span>';
  }

  function dLink(id) {
    return '<a class="dep-link" href="#decision-' + id + '" data-scroll-to="decision-' + id + '">Decision #' + id + '</a>';
  }

  function fmtDate(iso) {
    try { return new Date(iso).toLocaleString(); } catch(e) { return iso || ''; }
  }

  /* ════════════════════════════════════════════════════════════════════════
     Pre-compute maps
     ════════════════════════════════════════════════════════════════════════ */

  var decisionsById = {};
  var dependentsOf = {};   // id → [ids that depend on it]
  var childrenOf = {};     // id → [direct children for tree]

  DATA.decisions.forEach(function(d) {
    decisionsById[d.id] = d;
    if (!childrenOf[d.id]) childrenOf[d.id] = [];
    (d.depends_on || []).forEach(function(pid) {
      // dependentsOf: pid is depended upon by d.id
      if (!dependentsOf[pid]) dependentsOf[pid] = [];
      if (dependentsOf[pid].indexOf(d.id) === -1) dependentsOf[pid].push(d.id);
      // childrenOf: for tree rendering (parent → children)
      if (!childrenOf[pid]) childrenOf[pid] = [];
      if (childrenOf[pid].indexOf(d.id) === -1) childrenOf[pid].push(d.id);
    });
  });

  // Findings lookup: decision_id → [{type, data}]
  var findingsFor = {};
  if (FINDINGS) {
    (FINDINGS.escalations || []).forEach(function(f) {
      var k = f.decision_id; if (k == null) return;
      if (!findingsFor[k]) findingsFor[k] = [];
      findingsFor[k].push({ type:'escalation', data:f });
    });
    (FINDINGS.auto_forks || []).forEach(function(f) {
      var k = f.decision_id; if (k == null) return;
      if (!findingsFor[k]) findingsFor[k] = [];
      findingsFor[k].push({ type:'auto_fork', data:f });
    });
    (FINDINGS.code_issues || []).forEach(function(f) {
      var k = f.related_decision; if (k == null) return;
      if (!findingsFor[k]) findingsFor[k] = [];
      findingsFor[k].push({ type:'code_issue', data:f });
    });
  }

  /* ════════════════════════════════════════════════════════════════════════
     Section: Header
     ════════════════════════════════════════════════════════════════════════ */

  function renderHeader() {
    var d = DATA.decisions || [];
    var stats = DATA.stats || {};
    var high = stats.high_confidence != null ? stats.high_confidence : d.filter(function(x){return x.confidence==='high'}).length;
    var med  = stats.medium_confidence != null ? stats.medium_confidence : d.filter(function(x){return x.confidence==='medium'}).length;
    var low  = stats.low_confidence != null ? stats.low_confidence : d.filter(function(x){return x.confidence==='low'}).length;

    var advHtml = '';
    if (FINDINGS && FINDINGS.summary) {
      var fs = FINDINGS.summary;
      advHtml =
        '<div class="stat">' +
          '<span class="stat-value">' +
            '\uD83D\uDD00 ' + (fs.auto_forked||0) +
            ' &nbsp;\u26A0\uFE0F ' + (fs.escalated||0) +
            ' &nbsp;\u2705 ' + (fs.clean||0) +
          '</span>' +
          '<span class="stat-label">Adversary Review</span>' +
        '</div>';
    }

    var explicitImplicit = '';
    if (stats.explicit != null) {
      explicitImplicit =
        '<div class="stat">' +
          '<span class="stat-value">' + (stats.explicit||0) + ' / ' + (stats.implicit||0) + '</span>' +
          '<span class="stat-label">Explicit / Implicit</span>' +
        '</div>';
    }

    return (
      '<header class="header">' +
        '<h1>\uD83D\uDCCB Decision Log</h1>' +
        '<div class="session-info">' +
          '<span>\uD83D\uDCE6 ' + esc(DATA.repository) + '</span>' +
          '<span>\uD83C\uDF3F ' + esc(DATA.branch) + '</span>' +
          '<span>\uD83D\uDD11 <code>' + esc(DATA.session_id) + '</code></span>' +
          '<span>\uD83D\uDD50 ' + fmtDate(DATA.analyzed_at) + '</span>' +
        '</div>' +
        '<div class="stats-bar">' +
          '<div class="stat">' +
            '<span class="stat-value">' + d.length + '</span>' +
            '<span class="stat-label">Total Decisions</span>' +
          '</div>' +
          '<div class="stat">' +
            '<span class="stat-value">' +
              dot('high') + ' ' + high + ' &nbsp; ' +
              dot('medium') + ' ' + med + ' &nbsp; ' +
              dot('low') + ' ' + low +
            '</span>' +
            '<span class="stat-label">Confidence</span>' +
          '</div>' +
          explicitImplicit +
          advHtml +
        '</div>' +
      '</header>'
    );
  }

  /* ════════════════════════════════════════════════════════════════════════
     Section: Decision Timeline
     ════════════════════════════════════════════════════════════════════════ */

  function renderTimeline() {
    var decisions = DATA.decisions || [];
    if (!decisions.length) return '<div class="section"><h2>Decision Timeline</h2><p style="color:var(--text-secondary)">No decisions recorded.</p></div>';

    var h = '<div class="section"><h2>Decision Timeline</h2>';

    decisions.forEach(function(d) {
      var conf = d.confidence || 'medium';
      var over = (d.alternatives || []).join(', ') || 'no recorded alternatives';

      h += '<div class="decision-card ' + conf + '" id="decision-' + d.id + '">';

      /* header row */
      h += '<div class="decision-header">';
      h += '<span class="decision-num">#' + d.id + '</span>';
      h += dot(conf);
      h += '<span class="decision-summary">' + esc(d.summary) + '</span>';
      if (d.source) h += ' <span class="badge ' + d.source + '">' + esc(d.source) + '</span>';
      h += '</div>';

      /* chose line */
      h += '<div class="chose-line">Chose <strong>' + esc(d.chose) + '</strong> over ' + esc(over) + '</div>';

      /* expandable details */
      h += '<details><summary>Show details</summary><div class="detail-body">';

      if (d.rationale) {
        h += '<h4>Rationale</h4><p>' + esc(d.rationale) + '</p>';
      }

      if (d.alternatives && d.alternatives.length) {
        h += '<h4>Alternatives Considered</h4><ul>';
        d.alternatives.forEach(function(a) { h += '<li>' + esc(a) + '</li>'; });
        h += '</ul>';
      }

      if (d.tradeoff) {
        h += '<h4>Tradeoff</h4><p>' + esc(d.tradeoff) + '</p>';
      }

      /* system impact — visually emphasized */
      if (d.impacts && d.impacts.length) {
        h += '<div class="impact-box"><h4>\uD83D\uDCA1 System Impact</h4>';
        d.impacts.forEach(function(imp) { h += '<p>' + esc(imp) + '</p>'; });
        h += '</div>';
      }

      /* code references */
      if (d.code_refs && d.code_refs.length) {
        h += '<h4>Code References</h4><p>';
        d.code_refs.forEach(function(ref, i) {
          if (i) h += ' &nbsp; ';
          h += '<code class="code-ref">' + esc(ref) + '</code>';
        });
        h += '</p>';
      }

      /* dependency links */
      if (d.depends_on && d.depends_on.length) {
        h += '<h4>Depends On</h4><p>';
        h += d.depends_on.map(function(x) { return dLink(x); }).join(', ');
        h += '</p>';
      }

      var deps = dependentsOf[d.id];
      if (deps && deps.length) {
        h += '<h4>Dependents</h4><p>';
        h += deps.map(function(x) { return dLink(x); }).join(', ');
        h += ' depend' + (deps.length === 1 ? 's' : '') + ' on this';
        h += '</p>';
      }

      h += '</div></details>'; /* end detail-body, details */

      /* inline adversary findings */
      var ff = findingsFor[d.id];
      if (ff && ff.length) {
        ff.forEach(function(f) {
          if (f.type === 'escalation') {
            h += '<div class="inline-finding escalation">';
            h += sevBadge(f.data.severity);
            h += ' <strong>Escalated:</strong> ' + esc(f.data.finding);
            if (f.data.context) h += '<p style="margin:6px 0 0;font-size:13px;color:var(--text-secondary)">' + esc(f.data.context) + '</p>';
            h += '</div>';
          } else if (f.type === 'auto_fork') {
            h += '<div class="inline-finding auto-fork">';
            h += '<strong>\uD83D\uDD00 Auto-forked:</strong> ' + esc(f.data.finding);
            h += '</div>';
          } else if (f.type === 'code_issue') {
            var ns = normSev(f.data.severity);
            h += '<div class="inline-finding code-issue ' + ns + '">';
            h += sevBadge(f.data.severity);
            if (f.data.file) h += ' <code class="code-ref">' + esc(f.data.file) + (f.data.line ? ':' + f.data.line : '') + '</code>';
            h += ' ' + esc(f.data.finding);
            h += '</div>';
          }
        });
      }

      h += '</div>'; /* end decision-card */
    });

    h += '</div>';
    return h;
  }

  /* ════════════════════════════════════════════════════════════════════════
     Section: Dependency Visualization
     ════════════════════════════════════════════════════════════════════════ */

  function renderDependencyTree() {
    var roots = [];
    if (DATA.dependency_chains && DATA.dependency_chains.roots) {
      roots = DATA.dependency_chains.roots;
    } else {
      DATA.decisions.forEach(function(d) {
        if (!d.depends_on || !d.depends_on.length) roots.push(d.id);
      });
    }
    if (!roots.length) return '';

    /* Guard against cycles */
    function renderNode(id, prefix, isLast, visited) {
      if (visited.indexOf(id) !== -1) {
        return prefix + (isLast ? '\u2514\u2500\u2500 ' : '\u251C\u2500\u2500 ') +
          'Decision #' + id + ' (circular)\n';
      }
      visited = visited.concat([id]);
      var d = decisionsById[id];
      var connector = isLast ? '\u2514\u2500\u2500 ' : '\u251C\u2500\u2500 ';
      var extension = isLast ? '    ' : '\u2502   ';
      var label = 'Decision #' + id;
      if (d) label += ' \u2014 ' + (d.summary || '');
      var out = prefix + connector + label + '\n';
      var kids = childrenOf[id] || [];
      kids.forEach(function(kid, i) {
        out += renderNode(kid, prefix + extension, i === kids.length - 1, visited);
      });
      return out;
    }

    var tree = '';
    roots.forEach(function(rid) {
      var d = decisionsById[rid];
      tree += 'Decision #' + rid + ' (root)';
      if (d) tree += ' \u2014 ' + (d.summary || '');
      tree += '\n';
      var kids = childrenOf[rid] || [];
      kids.forEach(function(kid, i) {
        tree += renderNode(kid, '', i === kids.length - 1, [rid]);
      });
      tree += '\n';
    });

    return (
      '<div class="section">' +
        '<h2>Dependency Graph</h2>' +
        '<div class="dep-tree">' + esc(tree.replace(/\n$/, '')) + '</div>' +
      '</div>'
    );
  }

  /* ════════════════════════════════════════════════════════════════════════
     Section: Escalated Findings
     ════════════════════════════════════════════════════════════════════════ */

  function renderEscalatedFindings() {
    var items = FINDINGS.escalations || [];
    if (!items.length) return '';

    var h = '<div class="section"><h2>\u26A0\uFE0F Escalated Findings</h2>';
    h += '<p style="color:var(--text-secondary);font-size:14px;margin:-12px 0 20px">' +
         'These require your judgment \u2014 the adversary couldn\u2019t resolve them automatically.</p>';

    items.forEach(function(f) {
      var n = normSev(f.severity);
      h += '<div class="finding-card ' + n + '">';
      h += '<div style="display:flex;align-items:center;gap:8px;margin-bottom:8px;flex-wrap:wrap">';
      h += sevBadge(f.severity);
      if (f.decision_id != null) h += ' \u2192 ' + dLink(f.decision_id);
      h += '</div>';
      h += '<p style="margin:0 0 6px;font-weight:600;font-size:14px">' + esc(f.finding) + '</p>';
      if (f.context) {
        h += '<p style="margin:0;font-size:13px;line-height:1.6;color:var(--text-secondary)">' + esc(f.context) + '</p>';
      }
      h += '</div>';
    });

    h += '</div>';
    return h;
  }

  /* ════════════════════════════════════════════════════════════════════════
     Section: Auto-Fork History (collapsible)
     ════════════════════════════════════════════════════════════════════════ */

  function renderAutoForkHistory() {
    var items = FINDINGS.auto_forks || [];
    if (!items.length) return '';

    var h = '<div class="section">';
    h += '<details>';
    h += '<summary style="font-size:20px;font-weight:700;cursor:pointer;list-style:none;padding-bottom:10px;border-bottom:2px solid var(--border-subtle)">';
    h += '<span style="font-size:11px;margin-right:4px">\u25B6</span> ';
    h += '\uD83D\uDD00 Auto-Fork History <span style="font-weight:400;font-size:14px;color:var(--text-secondary)">\u2014 ' + items.length + ' issue' + (items.length!==1?'s':'') + ' caught &amp; fixed</span>';
    h += '</summary>';
    h += '<p style="color:var(--text-secondary);font-size:14px;margin:12px 0 20px">' +
         'The adversary caught these issues and sent the coding agent back to fix them before this report reached you.</p>';

    items.forEach(function(f) {
      h += '<div class="finding-card">';
      if (f.decision_id != null) h += '<p style="margin:0 0 6px">' + dLink(f.decision_id) + '</p>';
      h += '<p style="margin:0 0 4px"><strong>Issue:</strong> ' + esc(f.finding) + '</p>';
      if (f.fork_context) {
        h += '<p style="margin:0;font-size:13px;color:var(--text-secondary)"><strong>Fix:</strong> ' + esc(f.fork_context) + '</p>';
      }
      h += '</div>';
    });

    h += '</details></div>';
    return h;
  }

  /* ════════════════════════════════════════════════════════════════════════
     Section: Code Issues
     ════════════════════════════════════════════════════════════════════════ */

  function renderCodeIssues() {
    var items = FINDINGS.code_issues || [];
    if (!items.length) return '';

    var h = '<div class="section"><h2>\uD83D\uDC1B Code Issues</h2>';

    items.forEach(function(f) {
      var n = normSev(f.severity);
      h += '<div class="finding-card ' + n + '">';
      h += '<div style="display:flex;align-items:center;gap:8px;margin-bottom:8px;flex-wrap:wrap">';
      h += sevBadge(f.severity);
      if (f.file) {
        h += ' <code class="code-ref">' + esc(f.file) + (f.line ? ':' + f.line : '') + '</code>';
      }
      if (f.related_decision != null) h += ' \u2192 ' + dLink(f.related_decision);
      h += '</div>';
      h += '<p style="margin:0;font-size:14px;line-height:1.6">' + esc(f.finding) + '</p>';
      h += '</div>';
    });

    h += '</div>';
    return h;
  }

  /* ════════════════════════════════════════════════════════════════════════
     Footer
     ════════════════════════════════════════════════════════════════════════ */

  function renderFooter() {
    var parts = ['Generated by Decision Log Analyzer', fmtDate(DATA.analyzed_at)];
    if (FINDINGS) parts.push('Adversary review round ' + (FINDINGS.review_round || 1));
    return '<footer class="footer">' + parts.join(' \u00B7 ') + '</footer>';
  }

  /* ════════════════════════════════════════════════════════════════════════
     Render & bind events
     ════════════════════════════════════════════════════════════════════════ */

  var html = '<div class="container">';
  html += renderHeader();
  html += renderTimeline();
  html += renderDependencyTree();
  if (FINDINGS) {
    html += renderEscalatedFindings();
    html += renderAutoForkHistory();
    html += renderCodeIssues();
  }
  html += renderFooter();
  html += '</div>';

  app.innerHTML = html;

  /* Smooth-scroll for decision cross-references */
  document.querySelectorAll('[data-scroll-to]').forEach(function(el) {
    el.addEventListener('click', function(e) {
      e.preventDefault();
      var targetId = el.getAttribute('data-scroll-to');
      var target = document.getElementById(targetId);
      if (!target) return;
      target.scrollIntoView({ behavior:'smooth', block:'start' });
      /* brief highlight */
      target.style.boxShadow = 'var(--focus-ring)';
      setTimeout(function() { target.style.boxShadow = ''; }, 2000);
    });
  });

  /* Fix auto-fork details summary toggle indicator */
  var afDetails = document.querySelector('.section > details');
  if (afDetails) {
    var afArrow = afDetails.querySelector('summary > span');
    if (afArrow) {
      afDetails.addEventListener('toggle', function() {
        afArrow.textContent = afDetails.open ? '\u25BC' : '\u25B6';
      });
    }
  }

})();
</script>
</body>
</html>
HTMLJS

} > "$OUTPUT"

echo "✅ Decision log generated: $OUTPUT ($(wc -c < "$OUTPUT" | tr -d ' ') bytes)"
