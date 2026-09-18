#!/usr/bin/env python3
"""Inspect and apply deterministic refreshes to marked project infographics.

The expensive design pass owns structure and styling. This helper owns values that
can be derived exactly from plan.md/tasks.md, small explicitly marked prose leaves,
and byte-preserving migration of unambiguous legacy pages. It never invents layout.
"""

from __future__ import annotations

import argparse
import hashlib
import html as html_lib
import json
import os
import re
import sys
import tempfile
from dataclasses import asdict, dataclass, field
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Callable, Iterable


SCHEMA_VERSION = 1
STATE_ID = "todo-infographic-refresh-state"
REQUIRED_VALUE_BINDINGS = {"phase-count", "generated-date"}
REQUIRED_TASK_BINDING_SETS = ({"task-summary"}, {"task-done", "task-total"})
CHECKBOX_RE = re.compile(r"^(\s*-\s+\[)([ xX])(\]\s+)")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$")
FENCE_RE = re.compile(r"^\s*(`{3,}|~{3,})")
PHASE_RE = re.compile(r"^Phase\s+([0-9]+[A-Za-z]?)\b", re.IGNORECASE)
DECISION_RE = re.compile(r"^\s*\d+\.\s+\*\*(D[0-9]+[A-Za-z]?)\b", re.IGNORECASE)
STYLE_RE = re.compile(r"<style\b[^>]*>(.*?)</style\s*>", re.IGNORECASE | re.DOTALL)
STATE_RE = re.compile(
    rf"<script\b(?=[^>]*\bid\s*=\s*['\"]{re.escape(STATE_ID)}['\"])[^>]*>"
    r"(.*?)</script\s*>",
    re.IGNORECASE | re.DOTALL,
)


class RefreshError(RuntimeError):
    pass


@dataclass(frozen=True)
class Phase:
    key: str
    title: str
    done: int
    total: int
    percent: int
    structure_sha256: str
    content: str


@dataclass(eq=False)
class HtmlNode:
    tag: str
    start: int
    start_tag_end: int
    end_tag_start: int | None = None
    end: int | None = None
    parent: "HtmlNode | None" = None
    children: list["HtmlNode"] = field(default_factory=list)


@dataclass(frozen=True)
class TextSegment:
    start: int
    value: str
    parent: HtmlNode


class SourceTreeParser(HTMLParser):
    """Track source offsets without serializing or reformatting the document."""

    VOID_TAGS = {
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link",
        "meta", "param", "source", "track", "wbr",
    }

    def __init__(self, document: str) -> None:
        super().__init__(convert_charrefs=False)
        self.document = document
        self.line_offsets = [0]
        for match in re.finditer(r"\n", document):
            self.line_offsets.append(match.end())
        self.nodes: list[HtmlNode] = []
        self.text: list[TextSegment] = []
        self.stack: list[HtmlNode] = []

    def source_offset(self) -> int:
        line, column = self.getpos()
        return self.line_offsets[line - 1] + column

    def _start(self, tag: str, closed: bool) -> None:
        raw = self.get_starttag_text() or ""
        start = self.source_offset()
        parent = self.stack[-1] if self.stack else None
        node = HtmlNode(tag.casefold(), start, start + len(raw), parent=parent)
        if parent is not None:
            parent.children.append(node)
        self.nodes.append(node)
        if closed or node.tag in self.VOID_TAGS or raw.rstrip().endswith("/>"):
            node.end_tag_start = node.start_tag_end
            node.end = node.start_tag_end
        else:
            self.stack.append(node)

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self._start(tag, closed=False)

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self._start(tag, closed=True)

    def handle_endtag(self, tag: str) -> None:
        wanted = tag.casefold()
        for index in range(len(self.stack) - 1, -1, -1):
            if self.stack[index].tag != wanted:
                continue
            start = self.source_offset()
            close = self.document.find(">", start)
            node = self.stack[index]
            node.end_tag_start = start
            node.end = len(self.document) if close < 0 else close + 1
            del self.stack[index:]
            return

    def handle_data(self, data: str) -> None:
        if not self.stack or not data:
            return
        start = self.source_offset()
        self.text.append(TextSegment(start, data, self.stack[-1]))


def parse_source_tree(document: str) -> SourceTreeParser:
    parser = SourceTreeParser(document)
    parser.feed(document)
    parser.close()
    return parser


def descendants(node: HtmlNode) -> Iterable[HtmlNode]:
    for child in node.children:
        yield child
        yield from descendants(child)


def is_descendant(candidate: HtmlNode, ancestor: HtmlNode) -> bool:
    current: HtmlNode | None = candidate
    while current is not None:
        if current is ancestor:
            return True
        current = current.parent
    return False


def normalized_text(document: str, node: HtmlNode) -> str:
    if node.end_tag_start is None:
        return ""
    body = document[node.start_tag_end : node.end_tag_start]
    body = re.sub(r"<(?:script|style)\b[^>]*>.*?</(?:script|style)\s*>", " ", body, flags=re.I | re.S)
    body = re.sub(r"<[^>]+>", " ", body)
    return " ".join(html_lib.unescape(body).split())


def raw_start_tag(document: str, node: HtmlNode) -> str:
    return document[node.start : node.start_tag_end]


def attr_in_start_tag(document: str, node: HtmlNode, attribute: str) -> str | None:
    match = re.search(
        rf"\b{re.escape(attribute)}\s*=\s*(['\"])(.*?)\1",
        raw_start_tag(document, node),
        re.I | re.S,
    )
    return html_lib.unescape(match.group(2)) if match else None


def insertion_offset(document: str, node: HtmlNode) -> int:
    start_tag = raw_start_tag(document, node)
    suffix = 2 if start_tag.rstrip().endswith("/>") else 1
    return node.start_tag_end - suffix


def add_attr_operation(
    operations: list[tuple[int, int, str]],
    document: str,
    node: HtmlNode,
    attribute: str,
    value: str,
) -> None:
    existing = attr_in_start_tag(document, node, attribute)
    if existing == value:
        return
    if existing is not None:
        raise RefreshError(f"legacy element already has conflicting {attribute}={existing!r}")
    position = insertion_offset(document, node)
    escaped = html_lib.escape(value, quote=True)
    operations.append((position, position, f' {attribute}="{escaped}"'))


def apply_operations(document: str, operations: list[tuple[int, int, str]]) -> str:
    ordered = sorted(operations, key=lambda item: (item[0], item[1]), reverse=True)
    previous_start = len(document) + 1
    for start, end, replacement in ordered:
        if start < 0 or end < start or end > len(document):
            raise RefreshError("legacy marker operation is outside the document")
        if end > previous_start:
            raise RefreshError("legacy marker operations overlap")
        document = document[:start] + replacement + document[end:]
        previous_start = start
    return document


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        raise RefreshError(f"cannot read {path}: {exc}") from exc


def load_json(path: Path) -> Any:
    try:
        return json.loads(read_text(path))
    except json.JSONDecodeError as exc:
        raise RefreshError(f"invalid JSON in {path}: {exc}") from exc


def section_map(markdown: str) -> dict[str, str]:
    sections: dict[str, list[str]] = {"__preamble__": []}
    current = "__preamble__"
    for line in markdown.splitlines():
        match = HEADING_RE.match(line)
        if match and len(match.group(1)) == 2:
            current = match.group(2).strip()
            sections.setdefault(current, [])
            continue
        sections[current].append(line)
    return {name: "\n".join(lines).strip() for name, lines in sections.items()}


def phase_key(title: str) -> str:
    match = PHASE_RE.match(title.strip())
    if match:
        return f"phase-{match.group(1).lower()}"
    slug = re.sub(r"[^a-z0-9]+", "-", title.casefold()).strip("-")
    return slug or "phase"


def _visible_markdown_lines(markdown: str) -> list[str]:
    visible: list[str] = []
    in_comment = False
    fence: str | None = None
    for original in markdown.splitlines():
        line = original
        if in_comment:
            if "-->" in line:
                line = line.split("-->", 1)[1]
                in_comment = False
            else:
                continue
        while "<!--" in line:
            before, after = line.split("<!--", 1)
            line = before
            if "-->" in after:
                line += after.split("-->", 1)[1]
            else:
                in_comment = True
                break
        fence_match = FENCE_RE.match(line)
        if fence_match:
            marker = fence_match.group(1)[0]
            if fence is None:
                fence = marker
            elif fence == marker:
                fence = None
            continue
        if fence is None:
            visible.append(line)
    return visible


def parse_phases(tasks: str) -> list[Phase]:
    phases: list[Phase] = []
    current_title: str | None = None
    current_lines: list[str] = []

    def finish() -> None:
        nonlocal current_title, current_lines
        if current_title is None:
            return
        done = 0
        total = 0
        normalized: list[str] = []
        for line in current_lines:
            checkbox = CHECKBOX_RE.match(line)
            if checkbox:
                total += 1
                if checkbox.group(2).casefold() == "x":
                    done += 1
                line = CHECKBOX_RE.sub(r"\1 \3", line, count=1)
            normalized.append(line.rstrip())
        key = phase_key(current_title)
        phases.append(
            Phase(
                key=key,
                title=current_title,
                done=done,
                total=total,
                percent=round(done / total * 100) if total else 0,
                structure_sha256=sha256_text("\n".join(normalized).strip()),
                content="\n".join(current_lines).strip(),
            )
        )
        current_title = None
        current_lines = []

    for line in _visible_markdown_lines(tasks):
        heading = HEADING_RE.match(line)
        if heading and len(heading.group(1)) == 2:
            finish()
            title = heading.group(2).strip()
            if PHASE_RE.match(title):
                current_title = title
            continue
        if current_title is not None:
            current_lines.append(line)
    finish()

    keys = [phase.key for phase in phases]
    if len(keys) != len(set(keys)):
        raise RefreshError(f"duplicate phase keys after normalization: {keys}")
    return phases


def decision_ids(plan_sections: dict[str, str]) -> list[str]:
    section = plan_sections.get("Key Decisions", "")
    result: list[str] = []
    for line in section.splitlines():
        match = DECISION_RE.match(line)
        if match:
            value = match.group(1).upper()
            if value not in result:
                result.append(value)
    return result


def attr_values(document: str, attribute: str) -> list[str]:
    pattern = re.compile(
        rf"\b{re.escape(attribute)}\s*=\s*(['\"])(.*?)\1",
        re.IGNORECASE | re.DOTALL,
    )
    return [html_lib.unescape(match.group(2)) for match in pattern.finditer(document)]


def node_segments(parser: SourceTreeParser, node: HtmlNode) -> list[TextSegment]:
    return [segment for segment in parser.text if is_descendant(segment.parent, node)]


def leaf_nodes(parser: SourceTreeParser) -> list[HtmlNode]:
    return [node for node in parser.nodes if not node.children and node.end_tag_start is not None]


def nearest_ancestor(
    node: HtmlNode, predicate: Callable[[HtmlNode], bool]
) -> HtmlNode | None:
    current = node.parent
    while current is not None:
        if predicate(current):
            return current
        current = current.parent
    return None


def wrap_segment_operation(
    operations: list[tuple[int, int, str]],
    segment: TextSegment,
    start: int,
    end: int,
    opening: str,
    closing: str,
) -> None:
    operations.append((segment.start + end, segment.start + end, closing))
    operations.append((segment.start + start, segment.start + start, opening))


def decision_card_for(
    document: str,
    parser: SourceTreeParser,
    decision_id: str,
) -> HtmlNode | None:
    token = re.compile(rf"^\[?{re.escape(decision_id)}\]?$", re.I)
    matches = [
        node for node in leaf_nodes(parser)
        if token.fullmatch(normalized_text(document, node))
    ]
    cards: list[HtmlNode] = []
    for match in matches:
        card = nearest_ancestor(
            match,
            lambda candidate: (
                re.search(r"\bGain\b", normalized_text(document, candidate), re.I) is not None
                and re.search(r"\bCost\b", normalized_text(document, candidate), re.I) is not None
            ),
        )
        if card is not None and card not in cards:
            cards.append(card)
    return cards[0] if len(cards) == 1 else None


def visible_decision_cards(document: str, parser: SourceTreeParser) -> dict[str, HtmlNode]:
    candidates = {
        match.group(1).upper()
        for node in leaf_nodes(parser)
        for match in [re.fullmatch(r"\[?(D[0-9]+[A-Za-z]?)\]?", normalized_text(document, node), re.I)]
        if match
    }
    result: dict[str, HtmlNode] = {}
    for decision_id in sorted(candidates):
        card = decision_card_for(document, parser, decision_id)
        if card is not None:
            result[decision_id] = card
    return result


def phase_label_node(
    document: str,
    parser: SourceTreeParser,
    phase: dict[str, Any],
) -> HtmlNode | None:
    number = phase["key"].removeprefix("phase-")
    pattern = re.compile(rf"^Phase\s+{re.escape(number)}(?:\b|\s*[-—:])", re.I)
    matches = [
        node for node in leaf_nodes(parser)
        if pattern.search(normalized_text(document, node))
    ]
    return matches[0] if len(matches) == 1 else None


def phase_container_for(
    document: str,
    parser: SourceTreeParser,
    phase: dict[str, Any],
) -> HtmlNode | None:
    label = phase_label_node(document, parser, phase)
    if label is None:
        return None

    def qualifies(candidate: HtmlNode) -> bool:
        text = normalized_text(document, candidate)
        ratios = re.findall(r"\b[0-9]+\s*/\s*[0-9]+\b", text)
        percents = re.findall(r"\b[0-9]+%", text)
        phase_labels = [
            node for node in descendants(candidate)
            if not node.children and re.match(r"^Phase\s+[0-9]+[A-Za-z]?\b", normalized_text(document, node), re.I)
        ]
        return bool(ratios and percents and len(phase_labels) == 1)

    return nearest_ancestor(label, qualifies)


def add_legacy_value_markers(
    document: str,
    parser: SourceTreeParser,
    current: dict[str, Any],
    operations: list[tuple[int, int, str]],
) -> None:
    existing = set(attr_values(document, "data-todo-value"))
    leaves = leaf_nodes(parser)

    if "phase-count" not in existing:
        labels = [node for node in leaves if normalized_text(document, node).casefold() == "phases"]
        if len(labels) != 1:
            raise RefreshError("legacy page has no unambiguous Phases stat label")
        container = labels[0].parent
        targets = [
            node for node in descendants(container)
            if not node.children and re.fullmatch(r"[0-9]+", normalized_text(document, node))
        ] if container is not None else []
        if len(targets) != 1:
            raise RefreshError("legacy page has no unambiguous phase-count value")
        add_attr_operation(operations, document, targets[0], "data-todo-value", "phase-count")

    if not any(required.issubset(existing) for required in REQUIRED_TASK_BINDING_SETS):
        labels = [
            node for node in leaves
            if normalized_text(document, node).casefold() in {"tasks", "tasks done", "task progress"}
        ]
        if len(labels) != 1:
            raise RefreshError("legacy page has no unambiguous task-progress stat label")
        container = labels[0].parent
        candidates = [
            node for node in descendants(container)
            if re.fullmatch(r"[0-9,]+\s*/\s*[0-9,]+", normalized_text(document, node))
        ] if container is not None else []
        if len(candidates) != 1:
            raise RefreshError("legacy page has no unambiguous task-progress value")
        display = candidates[0]
        numbers: list[tuple[TextSegment, int, int]] = []
        for segment in node_segments(parser, display):
            for match in re.finditer(r"[0-9][0-9,]*", segment.value):
                numbers.append((segment, match.start(), match.end()))
        if len(numbers) < 2:
            raise RefreshError("legacy task-progress value does not contain done and total")
        done, total = numbers[0], numbers[1]
        wrap_segment_operation(
            operations, done[0], done[1], done[2],
            '<span data-todo-value="task-done">', "</span>",
        )
        wrap_segment_operation(
            operations, total[0], total[1], total[2],
            '<span data-todo-value="task-total">', "</span>",
        )

    if "generated-date" not in existing:
        generated_date = current["values"].get("generated-date")
        if not generated_date:
            raise RefreshError("legacy migration needs a generated date")
        matches: list[tuple[TextSegment, re.Match[str]]] = []
        for segment in parser.text:
            date_match = re.search(r"\b[0-9]{4}-[0-9]{2}-[0-9]{2}\b", segment.value)
            if date_match is None:
                continue
            parent_text = normalized_text(document, segment.parent)
            if "generated" in parent_text.casefold():
                matches.append((segment, date_match))
        if len(matches) != 1:
            raise RefreshError("legacy page has no unambiguous generated date")
        segment, date_match = matches[0]
        wrap_segment_operation(
            operations, segment, date_match.start(), date_match.end(),
            '<time data-todo-value="generated-date">', "</time>",
        )


def migrate_legacy_markers(
    document: str,
    current: dict[str, Any],
    *,
    allow_extra_decisions: bool,
) -> tuple[str, dict[str, Any]]:
    parser = parse_source_tree(document)
    operations: list[tuple[int, int, str]] = []
    add_legacy_value_markers(document, parser, current, operations)

    phase_nodes: set[int] = set()
    for phase in current["phases"]:
        key = phase["key"]
        count_existing = key in attr_values(document, "data-todo-phase-count")
        progress_existing = key in attr_values(document, "data-todo-phase-progress")
        if count_existing and progress_existing:
            continue
        container = phase_container_for(document, parser, phase)
        if container is None or container.start in phase_nodes:
            raise RefreshError(f"legacy page has no unambiguous container for {key}")
        phase_nodes.add(container.start)
        leaves = [node for node in descendants(container) if not node.children]
        counts = [
            node for node in leaves
            if re.search(r"\b[0-9]+\s*/\s*[0-9]+\b", normalized_text(document, node))
        ]
        if len(counts) != 1:
            raise RefreshError(f"legacy page has no unambiguous count for {key}")
        progress = [
            node for node in descendants(container)
            if re.search(r"\bwidth\s*:\s*[0-9]+%", raw_start_tag(document, node), re.I)
        ]
        if len(progress) != 1:
            raise RefreshError(f"legacy page has no unambiguous progress bar for {key}")
        if not count_existing:
            add_attr_operation(operations, document, counts[0], "data-todo-phase-count", key)
        if not progress_existing:
            add_attr_operation(operations, document, progress[0], "data-todo-phase-progress", key)
            if attr_in_start_tag(document, progress[0], "aria-valuenow") is None:
                add_attr_operation(
                    operations, document, progress[0], "aria-valuenow", str(phase["percent"])
                )
        percent_labels = [
            node for node in leaves
            if re.fullmatch(r"[0-9]+%", normalized_text(document, node))
        ]
        if len(percent_labels) > 1:
            raise RefreshError(f"legacy page has ambiguous percent labels for {key}")
        if percent_labels:
            add_attr_operation(
                operations, document, percent_labels[0], "data-todo-phase-percent", key
            )

    cards = visible_decision_cards(document, parser)
    existing_decisions = {
        value.upper() for value in attr_values(document, "data-todo-review-id")
    }
    plan_ids = set(current["decision_ids"])
    visible_ids = set(cards) | existing_decisions
    missing = sorted(plan_ids - visible_ids)
    extra = sorted(visible_ids - plan_ids)
    if missing:
        raise RefreshError("legacy page is missing decision cards: " + ", ".join(missing))
    if extra and not allow_extra_decisions:
        raise RefreshError("legacy page has stale decision cards: " + ", ".join(extra))
    for decision_id in current["decision_ids"]:
        if decision_id in existing_decisions:
            continue
        add_attr_operation(
            operations, document, cards[decision_id], "data-todo-review-id", decision_id
        )

    migrated = apply_operations(document, operations)
    details = {
        "visible_decision_ids": sorted(visible_ids),
        "extra_decision_ids": extra,
        "marker_operations": len(operations),
    }
    return migrated, details


def element_pattern(attribute: str, key: str) -> re.Pattern[str]:
    return re.compile(
        rf"(<(?P<tag>[A-Za-z][\w:-]*)\b"
        rf"(?=[^>]*\b{re.escape(attribute)}\s*=\s*['\"]{re.escape(key)}['\"])[^>]*>)"
        rf"(?P<body>.*?)"
        rf"(</(?P=tag)\s*>)",
        re.IGNORECASE | re.DOTALL,
    )


def extract_leaf_values(document: str, attribute: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for key in attr_values(document, attribute):
        pattern = element_pattern(attribute, key)
        matches = list(pattern.finditer(document))
        if len(matches) != 1:
            raise RefreshError(f"{attribute}={key!r} must occur exactly once")
        body = matches[0].group("body")
        if re.search(r"<[A-Za-z/]", body):
            raise RefreshError(f"{attribute}={key!r} must mark a leaf element")
        values[key] = html_lib.unescape(body.strip())
    return values


def replace_leaf(document: str, attribute: str, key: str, value: str) -> str:
    pattern = element_pattern(attribute, key)
    matches = list(pattern.finditer(document))
    if len(matches) != 1:
        raise RefreshError(f"{attribute}={key!r} must occur exactly once")
    escaped = html_lib.escape(value, quote=False)
    return pattern.sub(lambda match: f"{match.group(1)}{escaped}{match.group(4)}", document, count=1)


def replace_phase_count(document: str, key: str, done: int, total: int) -> str:
    pattern = element_pattern("data-todo-phase-count", key)
    matches = list(pattern.finditer(document))
    if len(matches) != 1:
        raise RefreshError(f"data-todo-phase-count={key!r} must occur exactly once")
    body = matches[0].group("body")
    ratio = re.search(r"([0-9]+)(\s*/\s*)([0-9]+)", body)
    if not ratio:
        raise RefreshError(f"data-todo-phase-count={key!r} has no done/total ratio")
    updated_body = body[: ratio.start()] + f"{done}{ratio.group(2)}{total}" + body[ratio.end() :]
    return pattern.sub(
        lambda match: f"{match.group(1)}{updated_body}{match.group(4)}",
        document,
        count=1,
    )


def phase_count_value(value: str) -> tuple[int, int] | None:
    match = re.search(r"\b([0-9]+)\s*/\s*([0-9]+)\b", value)
    return (int(match.group(1)), int(match.group(2))) if match else None


def replace_progress(document: str, key: str, percent: int) -> str:
    pattern = re.compile(
        rf"<(?P<tag>[A-Za-z][\w:-]*)\b"
        rf"(?=[^>]*\bdata-todo-phase-progress\s*=\s*['\"]{re.escape(key)}['\"])[^>]*>",
        re.IGNORECASE | re.DOTALL,
    )
    matches = list(pattern.finditer(document))
    if len(matches) != 1:
        raise RefreshError(f"data-todo-phase-progress={key!r} must occur exactly once")
    start_tag = matches[0].group(0)

    style_match = re.search(r"\bstyle\s*=\s*(['\"])(.*?)\1", start_tag, re.IGNORECASE | re.DOTALL)
    if style_match:
        style = style_match.group(2)
        if re.search(r"(?:^|;)\s*width\s*:", style, re.IGNORECASE):
            style = re.sub(
                r"((?:^|;)\s*width\s*:)\s*[^;]+",
                rf"\1 {percent}%",
                style,
                count=1,
                flags=re.IGNORECASE,
            )
        else:
            separator = "" if not style or style.rstrip().endswith(";") else ";"
            style = f"{style}{separator} width: {percent}%"
        replacement = (
            start_tag[: style_match.start(2)]
            + style
            + start_tag[style_match.end(2) :]
        )
    else:
        replacement = start_tag[:-1] + f' style="width: {percent}%">'

    if re.search(r"\baria-valuenow\s*=", replacement, re.IGNORECASE):
        replacement = re.sub(
            r"(\baria-valuenow\s*=\s*['\"])[^'\"]*(['\"])",
            rf"\g<1>{percent}\2",
            replacement,
            count=1,
            flags=re.IGNORECASE,
        )
    else:
        replacement = replacement[:-1] + f' aria-valuenow="{percent}">'

    return document[: matches[0].start()] + replacement + document[matches[0].end() :]


def style_hash(document: str) -> str:
    styles = STYLE_RE.findall(document)
    return sha256_text("\n".join(styles))


def has_network_assets(document: str) -> bool:
    tag_asset = re.search(
        r"<(?:img|script|source|link)\b[^>]*(?:src|href)\s*=\s*['\"]https?://",
        document,
        re.IGNORECASE,
    )
    css_asset = re.search(
        r"(?:url\s*\(\s*['\"]?https?://|@import\s+(?:url\s*\()?\s*['\"]https?://)",
        document,
        re.IGNORECASE,
    )
    return bool(tag_asset or css_asset)


def progress_value(document: str, key: str) -> int:
    pattern = re.compile(
        rf"<[A-Za-z][\w:-]*\b"
        rf"(?=[^>]*\bdata-todo-phase-progress\s*=\s*['\"]{re.escape(key)}['\"])[^>]*>",
        re.IGNORECASE | re.DOTALL,
    )
    matches = list(pattern.finditer(document))
    if len(matches) != 1:
        raise RefreshError(f"data-todo-phase-progress={key!r} must occur exactly once")
    width = re.search(r"\bwidth\s*:\s*([0-9]+)%", matches[0].group(0), re.IGNORECASE)
    if not width:
        raise RefreshError(f"data-todo-phase-progress={key!r} has no percentage width")
    return int(width.group(1))


def parse_state(document: str) -> dict[str, Any] | None:
    match = STATE_RE.search(document)
    if not match:
        return None
    try:
        value = json.loads(match.group(1))
    except json.JSONDecodeError as exc:
        raise RefreshError(f"invalid embedded refresh state: {exc}") from exc
    if not isinstance(value, dict):
        raise RefreshError("embedded refresh state must be a JSON object")
    return value


def write_state(document: str, state: dict[str, Any], initialize: bool) -> str:
    payload = canonical_json(state).replace("</", "<\\/")
    block = f'<script id="{STATE_ID}" type="application/json">{payload}</script>'
    if STATE_RE.search(document):
        return STATE_RE.sub(block, document, count=1)
    if not initialize:
        raise RefreshError("infographic has no embedded refresh state")
    closing = re.search(r"</body\s*>", document, re.IGNORECASE)
    if not closing:
        raise RefreshError("infographic has no closing </body> tag")
    return document[: closing.start()] + block + "\n" + document[closing.start() :]


def footprint_hash(path: Path | None) -> str | None:
    if path is None:
        return None
    return sha256_text(canonical_json(load_json(path)))


def build_current(
    project: Path,
    generated_date: str | None,
    status: str | None,
    footprint_path: Path | None,
    previous: dict[str, Any] | None,
) -> dict[str, Any]:
    plan_path = project / "plan.md"
    tasks_path = project / "tasks.md"
    plan = read_text(plan_path)
    tasks = read_text(tasks_path)
    sections = section_map(plan)
    phases = parse_phases(tasks)
    done = sum(phase.done for phase in phases)
    total = sum(phase.total for phase in phases)
    previous_values = (previous or {}).get("values", {})
    effective_status = status if status is not None else previous_values.get("project-status")
    effective_date = generated_date if generated_date is not None else previous_values.get("generated-date")
    values: dict[str, str] = {
        "phase-count": str(len(phases)),
        "task-total": str(total),
        "task-done": str(done),
        "task-open": str(max(0, total - done)),
        "task-summary": f"{done} done / {total}",
    }
    if effective_status is not None:
        values["project-status"] = str(effective_status)
    if effective_date is not None:
        values["generated-date"] = str(effective_date)

    supplied_footprint_hash = footprint_hash(footprint_path)
    previous_footprint_hash = (previous or {}).get("source", {}).get("footprint_sha256")
    effective_footprint_hash = (
        supplied_footprint_hash if footprint_path is not None else previous_footprint_hash
    )
    source = {
        "plan_sha256": sha256_text(plan),
        "tasks_sha256": sha256_text(tasks),
        "plan_sections": {name: sha256_text(content) for name, content in sections.items()},
        "phase_structure": {phase.key: phase.structure_sha256 for phase in phases},
        "footprint_sha256": effective_footprint_hash,
    }
    return {
        "schema": SCHEMA_VERSION,
        "source": source,
        "values": values,
        "phases": [asdict(phase) for phase in phases],
        "decision_ids": decision_ids(sections),
        "plan_sections": sections,
        "footprint_supplied": footprint_path is not None,
    }


def changed_names(old: dict[str, str], new: dict[str, str]) -> list[str]:
    return sorted(name for name in set(old) | set(new) if old.get(name) != new.get(name))


def inspect_project(
    project: Path,
    html_path: Path,
    generated_date: str | None,
    status: str | None,
    footprint_path: Path | None,
) -> tuple[dict[str, Any], str | None, dict[str, Any]]:
    document = read_text(html_path) if html_path.exists() else None
    previous = parse_state(document) if document is not None else None
    current = build_current(project, generated_date, status, footprint_path, previous)
    reasons: list[str] = []
    mode = "fresh"
    changed_sections: list[str] = []
    changed_phases: list[str] = []
    content_values: dict[str, str] = {}
    legacy: dict[str, Any] | None = None

    if document is None:
        mode = "full-build"
        reasons.append("missing-html")
    elif previous is None:
        try:
            _migrated, legacy = migrate_legacy_markers(
                document, current, allow_extra_decisions=True
            )
            mode = "legacy-migration"
            reasons.extend(["legacy-unmarked-html", "legacy-content-review-required"])
            if legacy["extra_decision_ids"]:
                reasons.append("legacy-content-patch-required")
        except RefreshError as exc:
            mode = "full-build"
            reasons.extend(["legacy-unmarked-html", "legacy-migration-ambiguous"])
            legacy = {"error": str(exc)}
    elif previous.get("schema") != SCHEMA_VERSION:
        mode = "full-build"
        reasons.append("refresh-schema-mismatch")
    else:
        current_phase_keys = {phase["key"] for phase in current["phases"]}
        count_keys = set(attr_values(document, "data-todo-phase-count"))
        progress_keys = set(attr_values(document, "data-todo-phase-progress"))
        value_keys = set(attr_values(document, "data-todo-value"))
        html_decisions = {value.upper() for value in attr_values(document, "data-todo-review-id")}
        plan_decisions = set(current["decision_ids"])

        if not REQUIRED_VALUE_BINDINGS.issubset(value_keys):
            mode = "full-build"
            reasons.append("missing-required-value-bindings")
        if count_keys != current_phase_keys or progress_keys != current_phase_keys:
            mode = "full-build"
            reasons.append("phase-bindings-changed")
        if plan_decisions != html_decisions:
            mode = "full-build"
            reasons.append("decision-card-structure-changed")
        old_source = previous.get("source", {})
        if (
            current["footprint_supplied"]
            and old_source.get("footprint_sha256") != current["source"].get("footprint_sha256")
        ):
            mode = "full-build"
            reasons.append("file-footprint-changed")

        changed_sections = changed_names(
            old_source.get("plan_sections", {}), current["source"]["plan_sections"]
        )
        changed_phases = changed_names(
            old_source.get("phase_structure", {}), current["source"]["phase_structure"]
        )
        if mode != "full-build" and (changed_sections or changed_phases):
            mode = "semantic-refresh"
            reasons.append("source-meaning-changed")
        elif mode != "full-build":
            old_values = previous.get("values", {})
            source_changed = (
                old_source.get("plan_sha256") != current["source"]["plan_sha256"]
                or old_source.get("tasks_sha256") != current["source"]["tasks_sha256"]
            )
            values_changed = old_values != current["values"]
            if source_changed or values_changed:
                mode = "fast-refresh"
                reasons.append("derived-values-changed")

        content_values = extract_leaf_values(document, "data-todo-content")

    section_payload = [
        {"name": name, "content": current["plan_sections"].get(name, "")}
        for name in changed_sections
    ]
    phase_by_key = {phase["key"]: phase for phase in current["phases"]}
    phase_payload = [phase_by_key[key] for key in changed_phases if key in phase_by_key]
    result = {
        "mode": mode,
        "reasons": sorted(set(reasons)),
        "project": str(project),
        "html": str(html_path),
        "theme": {
            "style_sha256": style_hash(document) if document is not None else None,
            "document_sha256": sha256_text(document) if document is not None else None,
        },
        "source": {
            "plan_sha256": current["source"]["plan_sha256"],
            "tasks_sha256": current["source"]["tasks_sha256"],
            "footprint_sha256": current["source"]["footprint_sha256"],
        },
        "current": {
            "values": current["values"],
            "phases": [
                {
                    "key": phase["key"],
                    "title": phase["title"],
                    "done": phase["done"],
                    "total": phase["total"],
                    "percent": phase["percent"],
                }
                for phase in current["phases"]
            ],
            "decision_ids": current["decision_ids"],
        },
        "changed": {"plan_sections": section_payload, "phases": phase_payload},
        "bindings": {
            "content": content_values,
            "content_keys": sorted(content_values),
        },
        "legacy": legacy,
    }
    return result, document, current


def state_from_current(current: dict[str, Any], document: str) -> dict[str, Any]:
    return {
        "schema": SCHEMA_VERSION,
        "source": current["source"],
        "values": current["values"],
        "phases": [
            {
                "key": phase["key"],
                "title": phase["title"],
                "done": phase["done"],
                "total": phase["total"],
                "percent": phase["percent"],
            }
            for phase in current["phases"]
        ],
        "decision_ids": current["decision_ids"],
        "theme": {"style_sha256": style_hash(document)},
    }


def validate_bindings(document: str, current: dict[str, Any]) -> None:
    value_keys = set(attr_values(document, "data-todo-value"))
    missing = sorted(REQUIRED_VALUE_BINDINGS - value_keys)
    if missing:
        raise RefreshError(f"missing required data-todo-value bindings: {', '.join(missing)}")
    if not any(required.issubset(value_keys) for required in REQUIRED_TASK_BINDING_SETS):
        raise RefreshError(
            "missing task progress binding: expected task-summary or task-done plus task-total"
        )
    phase_keys = {phase["key"] for phase in current["phases"]}
    count_keys = set(attr_values(document, "data-todo-phase-count"))
    progress_keys = set(attr_values(document, "data-todo-phase-progress"))
    if count_keys != phase_keys:
        raise RefreshError(
            f"phase-count bindings differ: expected {sorted(phase_keys)}, got {sorted(count_keys)}"
        )
    if progress_keys != phase_keys:
        raise RefreshError(
            f"phase-progress bindings differ: expected {sorted(phase_keys)}, got {sorted(progress_keys)}"
        )
    percent_keys = set(attr_values(document, "data-todo-phase-percent"))
    if percent_keys and not percent_keys.issubset(phase_keys):
        raise RefreshError(
            f"phase-percent bindings contain unknown keys: {sorted(percent_keys - phase_keys)}"
        )
    html_decisions = {value.upper() for value in attr_values(document, "data-todo-review-id")}
    plan_decisions = set(current["decision_ids"])
    if html_decisions != plan_decisions:
        raise RefreshError(
            f"decision bindings differ: expected {sorted(plan_decisions)}, got {sorted(html_decisions)}"
        )
    extract_leaf_values(document, "data-todo-content")


def apply_exact_patch(document: str, patch_path: Path | None) -> tuple[str, int]:
    if patch_path is None:
        return document, 0
    patch = load_json(patch_path)
    replacements = patch.get("replacements") if isinstance(patch, dict) else None
    if not isinstance(replacements, list) or not replacements:
        raise RefreshError('exact patch must be shaped as {"replacements": [...]}')
    if len(replacements) > 8:
        raise RefreshError("exact patch has more than 8 replacements")
    total_size = 0
    updated = document
    for index, replacement in enumerate(replacements, start=1):
        if not isinstance(replacement, dict):
            raise RefreshError(f"exact patch replacement {index} must be an object")
        before = replacement.get("before")
        after = replacement.get("after")
        if not isinstance(before, str) or not isinstance(after, str) or not before:
            raise RefreshError(f"exact patch replacement {index} needs non-empty string before/after")
        total_size += len(before) + len(after)
        if total_size > 65536:
            raise RefreshError("exact patch exceeds the 64 KiB bounded-patch limit")
        occurrences = updated.count(before)
        if occurrences != 1:
            raise RefreshError(
                f"exact patch replacement {index} matched {occurrences} times instead of once"
            )
        updated = updated.replace(before, after, 1)
    return updated, len(replacements)


def apply_derived_bindings(document: str, current: dict[str, Any]) -> str:
    updated = document
    value_bindings = set(attr_values(updated, "data-todo-value"))
    percent_bindings = set(attr_values(updated, "data-todo-phase-percent"))
    for key, value in current["values"].items():
        if key in value_bindings:
            updated = replace_leaf(updated, "data-todo-value", key, value)
    for phase in current["phases"]:
        updated = replace_phase_count(
            updated, phase["key"], phase["done"], phase["total"]
        )
        updated = replace_progress(updated, phase["key"], phase["percent"])
        if phase["key"] in percent_bindings:
            updated = replace_leaf(
                updated,
                "data-todo-phase-percent",
                phase["key"],
                f"{phase['percent']}%",
            )
    return updated


def migrate_legacy(args: argparse.Namespace) -> dict[str, Any]:
    project = Path(args.project).resolve()
    html_path = Path(args.html).resolve() if args.html else project / "artifacts/infographic.html"
    manifest_path = Path(args.manifest).resolve()
    patch_path = Path(args.exact_patch).resolve() if args.exact_patch else None
    if patch_path is None and not args.confirm_content_current:
        raise RefreshError(
            "legacy migration requires --exact-patch or --confirm-content-current"
        )
    if patch_path is not None and args.confirm_content_current:
        raise RefreshError(
            "use --exact-patch or --confirm-content-current, not both"
        )
    manifest = load_json(manifest_path)
    if not isinstance(manifest, dict) or manifest.get("mode") != "legacy-migration":
        raise RefreshError("migration manifest must come from a legacy-migration inspection")
    if manifest.get("project") != str(project) or manifest.get("html") != str(html_path):
        raise RefreshError("migration manifest targets a different project or HTML file")

    document = read_text(html_path)
    original_style_hash = style_hash(document)
    if manifest.get("theme", {}).get("document_sha256") != sha256_text(document):
        raise RefreshError("infographic changed after inspection; inspect again before migrating")
    if manifest.get("theme", {}).get("style_sha256") != original_style_hash:
        raise RefreshError("infographic changed after inspection; inspect again before migrating")
    footprint_path = Path(args.footprint_json).resolve() if args.footprint_json else None
    current = build_current(project, args.date, args.status, footprint_path, None)
    expected_source = manifest.get("source", {})
    for key in ("plan_sha256", "tasks_sha256", "footprint_sha256"):
        if expected_source.get(key) != current["source"].get(key):
            raise RefreshError(f"{key.removesuffix('_sha256')} changed after inspection")

    patched, replacement_count = apply_exact_patch(document, patch_path)
    if style_hash(patched) != original_style_hash:
        raise RefreshError("exact patch changed the infographic CSS")
    migrated, migration = migrate_legacy_markers(
        patched, current, allow_extra_decisions=False
    )
    validate_bindings(migrated, current)
    updated = apply_derived_bindings(migrated, current)
    updated = write_state(updated, state_from_current(current, updated), initialize=True)
    if style_hash(updated) != original_style_hash:
        raise RefreshError("legacy migration changed the infographic CSS")
    if has_network_assets(updated):
        raise RefreshError("infographic contains a network-loaded asset")
    atomic_write(html_path, updated)
    return {
        "result": "written",
        "mode": "legacy-migration",
        "html": str(html_path),
        "exact_replacements": replacement_count,
        "marker_operations": migration["marker_operations"],
        "theme_css_preserved": True,
    }


def extract_fragment(args: argparse.Namespace) -> dict[str, Any]:
    html_path = Path(args.html).resolve()
    document = read_text(html_path)
    parser = parse_source_tree(document)
    required = [args.needle, *args.contains]
    candidates = [
        node for node in parser.nodes
        if node.end is not None
        and all(value.casefold() in normalized_text(document, node).casefold() for value in required)
    ]
    if not candidates:
        raise RefreshError("no HTML fragment contains every requested text anchor")
    node = min(candidates, key=lambda candidate: candidate.end - candidate.start)
    fragment = document[node.start : node.end]
    if len(fragment) > args.max_chars:
        raise RefreshError(
            f"smallest matching fragment is {len(fragment)} characters; limit is {args.max_chars}"
        )
    return {
        "html": str(html_path),
        "needle": args.needle,
        "contains": args.contains,
        "fragment": fragment,
    }


def apply_refresh(args: argparse.Namespace) -> dict[str, Any]:
    project = Path(args.project).resolve()
    html_path = Path(args.html).resolve() if args.html else project / "artifacts/infographic.html"
    footprint_path = Path(args.footprint_json).resolve() if args.footprint_json else None
    result, document, current = inspect_project(
        project, html_path, args.date, args.status, footprint_path
    )
    mode = result["mode"]
    if document is None:
        raise RefreshError("cannot apply a refresh before the HTML exists")
    if mode == "full-build" and not args.initialize:
        raise RefreshError(
            "full-build required; regenerate marked HTML, then rerun apply with --initialize"
        )
    if mode == "semantic-refresh" and not args.initialize and not (
        args.content_patch or args.confirm_no_content_change
    ):
        raise RefreshError(
            "semantic-refresh requires --content-patch or --confirm-no-content-change"
        )

    validate_bindings(document, current)
    original_style_hash = style_hash(document)
    if (
        args.expected_style_sha256
        and args.expected_style_sha256 != original_style_hash
    ):
        raise RefreshError(
            "rebuilt HTML does not preserve the pre-build theme CSS hash"
        )
    previous = parse_state(document)
    if previous and not args.initialize:
        expected_style_hash = previous.get("theme", {}).get("style_sha256")
        if expected_style_hash and expected_style_hash != original_style_hash:
            raise RefreshError("theme CSS changed since the last initialized build")

    updated = apply_derived_bindings(document, current)

    applied_content_keys: list[str] = []
    if args.content_patch:
        patch = load_json(Path(args.content_patch).resolve())
        content = patch.get("content") if isinstance(patch, dict) else None
        if not isinstance(content, dict):
            raise RefreshError('content patch must be an object shaped as {"content": {...}}')
        available = set(attr_values(updated, "data-todo-content"))
        unknown = sorted(set(content) - available)
        if unknown:
            raise RefreshError(
                "content patch targets unknown or structural bindings: " + ", ".join(unknown)
            )
        for key, value in content.items():
            if not isinstance(value, str):
                raise RefreshError(f"content patch value for {key!r} must be a string")
            updated = replace_leaf(updated, "data-todo-content", key, value)
            applied_content_keys.append(key)

    state = state_from_current(current, updated)
    updated = write_state(updated, state, initialize=args.initialize)
    if style_hash(updated) != original_style_hash:
        raise RefreshError("refresh changed the infographic CSS")
    if has_network_assets(updated):
        raise RefreshError("infographic contains a network-loaded asset")

    atomic_write(html_path, updated)
    return {
        "result": "written",
        "mode": mode,
        "html": str(html_path),
        "values": current["values"],
        "content_keys_updated": sorted(applied_content_keys),
        "theme_css_preserved": True,
    }


def atomic_write(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode if path.exists() else None
    handle = tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, delete=False, prefix=f".{path.name}."
    )
    temp_path = Path(handle.name)
    try:
        with handle:
            handle.write(value)
        if mode is not None:
            os.chmod(temp_path, mode)
        os.replace(temp_path, path)
    finally:
        if temp_path.exists():
            temp_path.unlink()


def verify_project(args: argparse.Namespace) -> dict[str, Any]:
    project = Path(args.project).resolve()
    html_path = Path(args.html).resolve() if args.html else project / "artifacts/infographic.html"
    document = read_text(html_path)
    state = parse_state(document)
    if state is None:
        raise RefreshError("missing embedded refresh state")
    current = build_current(project, None, None, None, state)
    validate_bindings(document, current)
    if state.get("source", {}).get("plan_sha256") != current["source"]["plan_sha256"]:
        raise RefreshError("plan.md is newer than the embedded refresh state")
    if state.get("source", {}).get("tasks_sha256") != current["source"]["tasks_sha256"]:
        raise RefreshError("tasks.md is newer than the embedded refresh state")
    if state.get("theme", {}).get("style_sha256") != style_hash(document):
        raise RefreshError("theme CSS hash does not match the initialized build")
    value_bindings = extract_leaf_values(document, "data-todo-value")
    for key, expected in state.get("values", {}).items():
        if key in value_bindings and value_bindings[key] != str(expected):
            raise RefreshError(
                f"visible value {key!r} is {value_bindings[key]!r}, expected {expected!r}"
            )
    phase_counts = extract_leaf_values(document, "data-todo-phase-count")
    for phase in state.get("phases", []):
        key = phase["key"]
        expected_count = (phase["done"], phase["total"])
        if phase_count_value(phase_counts.get(key, "")) != expected_count:
            raise RefreshError(
                f"visible phase count {key!r} is {phase_counts.get(key)!r}, expected {phase['done']}/{phase['total']}"
            )
        if progress_value(document, key) != phase["percent"]:
            raise RefreshError(f"visible phase progress {key!r} is stale")
    phase_percents = extract_leaf_values(document, "data-todo-phase-percent")
    for phase in state.get("phases", []):
        key = phase["key"]
        if key in phase_percents and phase_percents[key] != f"{phase['percent']}%":
            raise RefreshError(f"visible phase percent {key!r} is stale")
    if "</html>" not in document.casefold():
        raise RefreshError("infographic has no closing </html> tag")
    if has_network_assets(document):
        raise RefreshError("infographic contains a network-loaded asset")
    return {
        "result": "verified",
        "html": str(html_path),
        "values": state.get("values", {}),
        "theme_css_preserved": True,
    }


def emit(value: dict[str, Any], output: str | None) -> None:
    rendered = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if output:
        Path(output).write_text(rendered, encoding="utf-8")
    else:
        sys.stdout.write(rendered)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)

    def common(command: argparse.ArgumentParser, include_date: bool = True) -> None:
        command.add_argument("project", help="absolute or relative project directory")
        command.add_argument("--html", help="infographic path; defaults under the project")
        if include_date:
            command.add_argument("--date", help="YYYY-MM-DD footer date")
            command.add_argument("--status", help="registry status to bind")
            command.add_argument("--footprint-json", help="orchestrator-gathered footprint JSON")

    inspect_command = subparsers.add_parser("inspect", help="classify the cheapest safe path")
    common(inspect_command)
    inspect_command.add_argument("--output", help="write the compact manifest here")

    apply_command = subparsers.add_parser("apply", help="apply derived values and prose leaves")
    common(apply_command)
    apply_command.add_argument("--content-patch", help='JSON shaped as {"content": {...}}')
    apply_command.add_argument("--confirm-no-content-change", action="store_true")
    apply_command.add_argument("--initialize", action="store_true")
    apply_command.add_argument(
        "--expected-style-sha256",
        help="pre-build CSS hash that an existing theme must preserve",
    )

    migrate_command = subparsers.add_parser(
        "migrate", help="migrate a legacy page with bounded deterministic edits"
    )
    common(migrate_command)
    migrate_command.add_argument(
        "--manifest", required=True, help="inspection manifest that freezes sources and CSS"
    )
    migrate_command.add_argument(
        "--exact-patch", help='optional JSON shaped as {"replacements": [...]}'
    )
    migrate_command.add_argument(
        "--confirm-content-current",
        action="store_true",
        help="confirm a bounded semantic review found no stale visible content",
    )

    fragment_command = subparsers.add_parser(
        "fragment", help="extract the smallest HTML fragment containing text anchors"
    )
    fragment_command.add_argument("--html", required=True, help="infographic HTML path")
    fragment_command.add_argument("--needle", required=True, help="primary text anchor")
    fragment_command.add_argument(
        "--contains", action="append", default=[], help="additional required text anchor"
    )
    fragment_command.add_argument("--max-chars", type=int, default=12000)
    fragment_command.add_argument("--output", help="write the fragment JSON here")

    verify_command = subparsers.add_parser("verify", help="verify state, bindings, and CSS")
    common(verify_command, include_date=False)
    return result


def main(argv: Iterable[str] | None = None) -> int:
    args = parser().parse_args(list(argv) if argv is not None else None)
    try:
        if args.command == "inspect":
            project = Path(args.project).resolve()
            html_path = Path(args.html).resolve() if args.html else project / "artifacts/infographic.html"
            footprint_path = Path(args.footprint_json).resolve() if args.footprint_json else None
            result, _document, _current = inspect_project(
                project, html_path, args.date, args.status, footprint_path
            )
            emit(result, args.output)
        elif args.command == "apply":
            emit(apply_refresh(args), None)
        elif args.command == "migrate":
            emit(migrate_legacy(args), None)
        elif args.command == "fragment":
            emit(extract_fragment(args), args.output)
        else:
            emit(verify_project(args), None)
        return 0
    except RefreshError as exc:
        print(f"ERROR\t{exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
