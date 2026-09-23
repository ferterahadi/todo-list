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
import weakref
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
PHASE_RE = re.compile(r"^Phase\s+([0-9]+(?:\.[0-9]+)?[A-Za-z]?)\b", re.IGNORECASE)
DECISION_RE = re.compile(
    r"^\s*(?:\d+\.|[-*+])\s+(?:~~)?\*\*(?:~~)?(D[0-9]+[A-Za-z]?)\b", re.IGNORECASE
)
# Canonical task count: these level-2 sections never hold real tasks.
EXCLUDED_TASK_SECTIONS = {"status", "notes", "context"}
# Plan sections the page never renders; edits there are not a prose change.
INVISIBLE_PLAN_SECTION_RE = re.compile(
    r"^(?:relationships|references|repos?|verification)\b", re.IGNORECASE
)
STUB_GOAL_SENTENCE = "What success looks like in one sentence."
EXACT_PATCH_MAX_REPLACEMENTS = 8
EXACT_PATCH_MAX_BYTES = 65536
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


_TEXT_CACHE: "weakref.WeakKeyDictionary[HtmlNode, str]" = weakref.WeakKeyDictionary()


def normalized_text(document: str, node: HtmlNode) -> str:
    # Each node belongs to exactly one parsed document, so its text is cacheable.
    cached = _TEXT_CACHE.get(node)
    if cached is not None:
        return cached
    if node.end_tag_start is None:
        return ""
    body = document[node.start_tag_end : node.end_tag_start]
    body = re.sub(r"<(?:script|style)\b[^>]*>.*?</(?:script|style)\s*>", " ", body, flags=re.I | re.S)
    body = re.sub(r"<[^>]+>", " ", body)
    value = " ".join(html_lib.unescape(body).split())
    _TEXT_CACHE[node] = value
    return value


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
    """Drop HTML comments and fenced blocks exactly as graph-report.py does.

    Blank lines are kept so phase structure hashes stay stable across versions.
    """
    visible: list[str] = []
    in_comment = False
    fence_char = ""
    fence_len = 0
    for raw in markdown.splitlines():
        if fence_char:
            if re.match(rf"^{re.escape(fence_char)}{{{fence_len},}}\s*$", raw.lstrip()):
                fence_char = ""
                fence_len = 0
            continue
        output: list[str] = []
        position = 0
        while position < len(raw):
            if in_comment:
                ending = raw.find("-->", position)
                if ending < 0:
                    position = len(raw)
                    break
                in_comment = False
                position = ending + 3
                continue
            opening = raw.find("<!--", position)
            if opening < 0:
                output.append(raw[position:])
                break
            output.append(raw[position:opening])
            in_comment = True
            position = opening + 4
        line = "".join(output)
        fence = FENCE_RE.match(line)
        if fence:
            fence_char = fence.group(1)[0]
            fence_len = len(fence.group(1))
            continue
        visible.append(line)
    return visible


@dataclass(frozen=True)
class TaskModel:
    done: int
    total: int
    phases: list[Phase]
    unphased_sha256: str | None
    unphased_content: str


def _blank_checkbox(line: str) -> str:
    return CHECKBOX_RE.sub(r"\1 \3", line, count=1).rstrip()


def parse_tasks(tasks: str) -> TaskModel:
    """Count real tasks and split them into phases.

    A real task is a checkbox under any level-2 section except Status, Notes, and
    Context, outside comments and fences. A phase is a level-2 `Phase <n>` heading,
    or a level-3 one under a counted, non-phase, non-Revisions level-2 section; a
    level-3 heading inside a level-2 phase is a subsection of it.
    """
    phases: list[Phase] = []
    total = 0
    done = 0
    section: str | None = None
    counting = False
    section_is_phase = False
    current: dict[str, Any] | None = None
    unphased: list[str] = []

    def finish() -> None:
        nonlocal current
        if current is None:
            return
        phase_done = 0
        phase_total = 0
        for line in current["lines"]:
            checkbox = CHECKBOX_RE.match(line)
            if checkbox:
                phase_total += 1
                if checkbox.group(2).casefold() == "x":
                    phase_done += 1
        normalized = [_blank_checkbox(line) for line in current["lines"]]
        phases.append(
            Phase(
                key=phase_key(current["title"]),
                title=current["title"],
                done=phase_done,
                total=phase_total,
                percent=round(phase_done / phase_total * 100) if phase_total else 0,
                structure_sha256=sha256_text("\n".join(normalized).strip()),
                content="\n".join(current["lines"]).strip(),
            )
        )
        current = None

    for line in _visible_markdown_lines(tasks):
        heading = HEADING_RE.match(line)
        if heading:
            level = len(heading.group(1))
            title = heading.group(2).strip()
            if level == 2:
                finish()
                section = title.casefold()
                counting = section not in EXCLUDED_TASK_SECTIONS
                section_is_phase = PHASE_RE.match(title) is not None
                if section_is_phase:
                    current = {"title": title, "lines": []}
                continue
            if level == 3 and not section_is_phase:
                finish()
                if counting and section != "revisions" and PHASE_RE.match(title):
                    current = {"title": title, "lines": []}
                continue
            if current is not None:
                current["lines"].append(line)
            continue
        checkbox = CHECKBOX_RE.match(line)
        if checkbox and counting:
            total += 1
            if checkbox.group(2).casefold() == "x":
                done += 1
            if current is None and section != "revisions":
                unphased.append(_blank_checkbox(line))
        if current is not None:
            current["lines"].append(line)
    finish()

    keys = [phase.key for phase in phases]
    duplicates = sorted({key for key in keys if keys.count(key) > 1})
    if duplicates:
        titles = [phase.title for phase in phases if phase.key in duplicates]
        raise RefreshError(
            "tasks.md has phase headings that share a phase number "
            f"({', '.join(duplicates)}): {titles}; give each phase a unique number"
        )
    return TaskModel(
        done=done,
        total=total,
        phases=phases,
        unphased_sha256=sha256_text("\n".join(unphased)) if unphased else None,
        unphased_content="\n".join(unphased),
    )


def parse_phases(tasks: str) -> list[Phase]:
    return parse_tasks(tasks).phases


def section_named(sections: dict[str, str], pattern: str) -> str | None:
    for name, content in sections.items():
        if name != "__preamble__" and re.match(pattern, name, re.IGNORECASE):
            return content
    return None


def stub_reasons(plan: str, sections: dict[str, str]) -> list[str]:
    reasons: list[str] = []
    if STUB_GOAL_SENTENCE in plan:
        reasons.append("stub-template-goal")
    goal = section_named(sections, r"goal\b")
    if goal is None or not "".join(_visible_markdown_lines(goal)).strip():
        reasons.append("stub-missing-goal")
    scope = section_named(sections, r"scope\b")
    if scope is not None and "what's included" in scope and "what's excluded" in scope:
        reasons.append("stub-template-scope")
    return reasons


def decision_ids(plan_sections: dict[str, str]) -> list[str]:
    section = section_named(plan_sections, r"key decisions\b") or ""
    result: list[str] = []
    for line in _visible_markdown_lines(section):
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


# Legacy recognition. Every rule accepts one reading of the page or refuses; a
# refusal routes the page to a content-preserving full build.
RATIO_RE = re.compile(r"\b[0-9][0-9,]*\s*/\s*[0-9][0-9,]*\b")
PERCENT_RE = re.compile(r"\b[0-9]+(?:\.[0-9]+)?\s*%")
# Numbers that restate task or phase progress. An unbound one would go stale on
# the next fast refresh while verify still passed, so migration refuses them.
DERIVED_NUMBER_RE = re.compile(
    r"[0-9]\s*/\s*[0-9]"
    r"|[0-9]\s*%"
    r"|\b[0-9][0-9,]*\s+(?:of\s+[0-9][0-9,]*\s+)?"
    r"(?:tasks?|phases?|stages?|blocks?|done|open|remaining|left|closed|shipped"
    r"|complete|completed|checked|ticked|pending)\b"
    r"|\b(?:done|open|remaining|left|closed|shipped|pending)\s*[:=]?\s*[0-9]",
    re.IGNORECASE,
)
PHASE_STAT_LABEL_RE = re.compile(
    r"(?:(?:execution|delivery|ordered|planned|build|work)\s+)?phases?"
    r"(?:\s+(?:done|complete|completed|closed|shipped|finished|planned|in\s+plan|total))?",
    re.IGNORECASE,
)
TASK_STAT_LABEL_RE = re.compile(
    r"(?:(?:total|all)\s+)?tasks?"
    r"(?:\s+(?:done|complete|completed|closed|shipped|finished|checked(?:\s+off)?|ticked|progress))?"
    r"|task\s+progress",
    re.IGNORECASE,
)
OPEN_STAT_LABEL_RE = re.compile(
    r"open\s+tasks?|tasks?\s+(?:open|remaining|left)|remaining\s+tasks?", re.IGNORECASE
)
PHASE_STAT_VALUE_RE = re.compile(r"[0-9]+(?:\s*/\s*[0-9]+)?")
TASK_STAT_VALUE_RE = re.compile(
    r"[0-9][0-9,]*\s*/\s*[0-9][0-9,]*(?:\s+(?:done|complete|completed|closed))?", re.IGNORECASE
)
OPEN_STAT_VALUE_RE = re.compile(r"[0-9][0-9,]*")
LABEL_SPLIT_RE = re.compile(r"^(.*?)(?:\s*(?:[·—–:(|,;]|\s-\s)\s*(.*))?$", re.DOTALL)
PAGE_PHASE_LABEL_RE = re.compile(r"^Phase\s+([0-9]+(?:\.[0-9]+)?[A-Za-z]?)(?![0-9A-Za-z]|\.[0-9])", re.IGNORECASE)
WIDTH_RE = re.compile(r"\bwidth\s*:\s*[0-9]+(?:\.[0-9]+)?%", re.IGNORECASE)
CHECK_GLYPHS = {"✓", "✔", "☑", "☐", "✅", "⬜", "✗", "✘", "❌", "□", "■"}
STAT_MAX_LEVELS = 3


def innermost(nodes: list[HtmlNode]) -> list[HtmlNode]:
    return [
        node for node in nodes
        if not any(other is not node and is_descendant(other, node) for other in nodes)
    ]


def split_label(text: str) -> tuple[str, str]:
    match = LABEL_SPLIT_RE.match(text)
    key = (match.group(1) if match else text).strip().rstrip(".")
    caption = (match.group(2) or "") if match else ""
    return key, caption


def stat_labels(document: str, parser: SourceTreeParser, label_re: re.Pattern[str]) -> list[HtmlNode]:
    matches: list[HtmlNode] = []
    for node in parser.nodes:
        if node.end_tag_start is None or node.tag in {"script", "style", "title", "head"}:
            continue
        text = normalized_text(document, node)
        if not text or len(text) > 600:
            continue
        key, _caption = split_label(text)
        if label_re.fullmatch(key):
            matches.append(node)
    return innermost(matches)


def remove_once(text: str, part: str) -> str:
    index = text.find(part)
    return text if index < 0 or not part else text[:index] + " " + text[index + len(part):]


def stat_card(
    document: str,
    label: HtmlNode,
    value_re: re.Pattern[str],
) -> tuple[HtmlNode, HtmlNode] | None:
    """Return (card, value) for the first ancestor holding exactly one value."""
    current = label.parent
    for _level in range(STAT_MAX_LEVELS):
        if current is None:
            return None
        values = innermost([
            node for node in descendants(current)
            if node is not label
            and not is_descendant(node, label)
            and not is_descendant(label, node)
            and value_re.fullmatch(normalized_text(document, node))
        ])
        if values:
            return (current, values[0]) if len(values) == 1 else None
        current = current.parent
    return None


def resolve_stat(
    document: str,
    parser: SourceTreeParser,
    label_re: re.Pattern[str],
    value_re: re.Pattern[str],
    name: str,
    *,
    required: bool,
) -> tuple[HtmlNode, HtmlNode] | None:
    cards = []
    for label in stat_labels(document, parser, label_re):
        found = stat_card(document, label, value_re)
        if found is not None:
            cards.append((label, found))
    if not cards:
        if required:
            raise RefreshError(f"legacy page has no unambiguous {name} stat label")
        return None
    if len(cards) != 1:
        raise RefreshError(f"legacy page has {len(cards)} candidate {name} stats")
    label, (card, value) = cards[0]
    remainder = remove_once(
        remove_once(normalized_text(document, card), normalized_text(document, value)),
        split_label(normalized_text(document, label))[0],
    )
    if DERIVED_NUMBER_RE.search(remainder):
        raise RefreshError(
            f"legacy {name} stat carries an unbound progress number: {remainder.strip()[:80]!r}"
        )
    return card, value


def number_spans(parser: SourceTreeParser, node: HtmlNode) -> list[tuple[TextSegment, int, int]]:
    numbers: list[tuple[TextSegment, int, int]] = []
    for segment in node_segments(parser, node):
        for match in re.finditer(r"[0-9][0-9,]*", segment.value):
            numbers.append((segment, match.start(), match.end()))
    return numbers


def bind_number(
    operations: list[tuple[int, int, str]],
    document: str,
    node: HtmlNode,
    number: tuple[TextSegment, int, int],
    key: str,
) -> None:
    segment, start, end = number
    if not node.children and normalized_text(document, node) == segment.value[start:end].strip():
        add_attr_operation(operations, document, node, "data-todo-value", key)
        return
    wrap_segment_operation(
        operations, segment, start, end, f'<span data-todo-value="{key}">', "</span>"
    )


def add_legacy_value_markers(
    document: str,
    parser: SourceTreeParser,
    current: dict[str, Any],
    operations: list[tuple[int, int, str]],
) -> None:
    existing = set(attr_values(document, "data-todo-value"))
    expected_phases = int(current["values"]["phase-count"])

    if "phase-count" not in existing:
        _card, value = resolve_stat(
            document, parser, PHASE_STAT_LABEL_RE, PHASE_STAT_VALUE_RE, "Phases", required=True
        )
        numbers = number_spans(parser, value)
        if len(numbers) not in {1, 2}:
            raise RefreshError("legacy page has no unambiguous phase-count value")
        shown = int(numbers[-1][0].value[numbers[-1][1]:numbers[-1][2]])
        if shown != expected_phases:
            raise RefreshError(
                f"legacy page shows {shown} phases but tasks.md has {expected_phases}; "
                "the phase structure cannot be reconciled"
            )
        if len(numbers) == 2:
            if "phase-done" in existing:
                raise RefreshError("legacy page already binds phase-done elsewhere")
            wrap_segment_operation(
                operations, numbers[0][0], numbers[0][1], numbers[0][2],
                '<span data-todo-value="phase-done">', "</span>",
            )
            wrap_segment_operation(
                operations, numbers[1][0], numbers[1][1], numbers[1][2],
                '<span data-todo-value="phase-count">', "</span>",
            )
        else:
            bind_number(operations, document, value, numbers[0], "phase-count")

    if not any(required.issubset(existing) for required in REQUIRED_TASK_BINDING_SETS):
        _card, value = resolve_stat(
            document, parser, TASK_STAT_LABEL_RE, TASK_STAT_VALUE_RE, "task-progress",
            required=True,
        )
        numbers = number_spans(parser, value)
        if len(numbers) != 2:
            raise RefreshError("legacy page has no unambiguous task-progress value")
        for number, key in zip(numbers, ("task-done", "task-total")):
            wrap_segment_operation(
                operations, number[0], number[1], number[2],
                f'<span data-todo-value="{key}">', "</span>",
            )

    if "task-open" not in existing:
        found = resolve_stat(
            document, parser, OPEN_STAT_LABEL_RE, OPEN_STAT_VALUE_RE, "open-task",
            required=False,
        )
        if found is not None:
            _card, value = found
            numbers = number_spans(parser, value)
            if len(numbers) != 1:
                raise RefreshError("legacy page has no unambiguous open-task value")
            bind_number(operations, document, value, numbers[0], "task-open")

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


def page_phase_labels(document: str, nodes: Iterable[HtmlNode]) -> list[tuple[HtmlNode, str]]:
    labels: list[tuple[HtmlNode, str]] = []
    for node in nodes:
        if node.children or node.end_tag_start is None:
            continue
        match = PAGE_PHASE_LABEL_RE.match(normalized_text(document, node))
        if match:
            labels.append((node, f"phase-{match.group(1).lower()}"))
    return labels


def width_elements(document: str, container: HtmlNode) -> list[HtmlNode]:
    return [
        node for node in descendants(container)
        if WIDTH_RE.search(raw_start_tag(document, node))
    ]


def is_phase_block(document: str, candidate: HtmlNode) -> bool:
    """One phase label, a done/total ratio, and exactly one progress width."""
    if len(page_phase_labels(document, descendants(candidate))) != 1:
        return False
    if not RATIO_RE.search(normalized_text(document, candidate)):
        return False
    return len(width_elements(document, candidate)) == 1


def visible_phase_blocks(document: str, parser: SourceTreeParser) -> dict[str, list[HtmlNode]]:
    blocks: dict[str, list[HtmlNode]] = {}
    verdicts: dict[int, bool] = {}

    def qualifies(node: HtmlNode) -> bool:
        if id(node) not in verdicts:
            verdicts[id(node)] = is_phase_block(document, node)
        return verdicts[id(node)]

    for label, key in page_phase_labels(document, parser.nodes):
        container = nearest_ancestor(label, qualifies)
        if container is None:
            continue
        found = blocks.setdefault(key, [])
        if container not in found:
            found.append(container)
    return blocks


def refuse_row_state(document: str, container: HtmlNode, key: str) -> None:
    """Refuse per-task done marks: the helper updates counts, not individual rows."""
    for node in descendants(container):
        if not node.children and normalized_text(document, node) in CHECK_GLYPHS:
            raise RefreshError(f"legacy {key} block renders per-task check marks")
    rows = [node for node in descendants(container) if node.tag == "li"]
    signatures: set[str] = set()
    for row in rows:
        marks = [
            raw_start_tag(document, child) for child in row.children
            if not normalized_text(document, child)
        ]
        signatures.add(raw_start_tag(document, row) + "".join(marks))
    if len(signatures) > 1:
        raise RefreshError(f"legacy {key} block styles task rows by state")


def bind_phase_block(
    document: str,
    parser: SourceTreeParser,
    container: HtmlNode,
    phase: dict[str, Any],
    operations: list[tuple[int, int, str]],
) -> None:
    key = phase["key"]
    refuse_row_state(document, container, key)
    # Task rows are summarized prose; the count, percent, and bar live outside them.
    leaves = [
        node for node in descendants(container)
        if not node.children
        and node.tag != "li"
        and nearest_ancestor(node, lambda item: item is container or item.tag == "li") is container
    ]
    counts = [node for node in leaves if RATIO_RE.search(normalized_text(document, node))]
    if len(counts) != 1:
        raise RefreshError(f"legacy page has no unambiguous count for {key}")
    progress = width_elements(document, container)[0]
    percent_labels = [
        node for node in leaves
        if re.fullmatch(r"[0-9]+%", normalized_text(document, node))
    ]
    if len(percent_labels) > 1:
        raise RefreshError(f"legacy page has ambiguous percent labels for {key}")
    count_text = normalized_text(document, counts[0])
    if DERIVED_NUMBER_RE.search(RATIO_RE.sub(" ", count_text, count=1)):
        raise RefreshError(f"legacy {key} count carries another progress number: {count_text!r}")
    bound = {counts[0], *percent_labels}
    header_text = " ".join(normalized_text(document, node) for node in leaves if node not in bound)
    if PERCENT_RE.search(header_text) or RATIO_RE.search(header_text):
        raise RefreshError(f"legacy {key} block shows an unbound percent or ratio")
    for node in descendants(container):
        if node is not progress and attr_in_start_tag(document, node, "aria-valuenow") is not None:
            raise RefreshError(f"legacy {key} block has a second aria-valuenow")
    add_attr_operation(operations, document, counts[0], "data-todo-phase-count", key)
    add_attr_operation(operations, document, progress, "data-todo-phase-progress", key)
    if attr_in_start_tag(document, progress, "aria-valuenow") is None:
        add_attr_operation(operations, document, progress, "aria-valuenow", str(phase["percent"]))
    if percent_labels:
        add_attr_operation(operations, document, percent_labels[0], "data-todo-phase-percent", key)


def migrate_legacy_markers(
    document: str,
    current: dict[str, Any],
    *,
    allow_extra_decisions: bool,
) -> tuple[str, dict[str, Any]]:
    parser = parse_source_tree(document)
    document_end(document, parser)
    operations: list[tuple[int, int, str]] = []
    add_legacy_value_markers(document, parser, current, operations)

    # Structural guard: the page's phase blocks must be exactly the parsed phases.
    parsed_keys = [phase["key"] for phase in current["phases"]]
    count_bound = set(attr_values(document, "data-todo-phase-count"))
    progress_bound = set(attr_values(document, "data-todo-phase-progress"))
    blocks = visible_phase_blocks(document, parser)
    shown_keys = sorted(set(blocks) | (count_bound & progress_bound))
    if shown_keys != sorted(parsed_keys):
        raise RefreshError(
            f"legacy page shows phase blocks {shown_keys} but tasks.md has {sorted(parsed_keys)}; "
            "the phase structure cannot be reconciled"
        )
    for phase in current["phases"]:
        key = phase["key"]
        if key in count_bound and key in progress_bound:
            continue
        containers = blocks.get(key, [])
        if len(containers) != 1 or key in count_bound or key in progress_bound:
            raise RefreshError(f"legacy page has no unambiguous container for {key}")
        bind_phase_block(document, parser, containers[0], phase, operations)

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


def document_end(document: str, parser: SourceTreeParser) -> int:
    """Return where the state block goes, refusing a page that may be truncated.

    A page either closes both </body> and </html>, or omits the optional html and
    body tags entirely (a bare `<title>`/`<style>`/content document) and leaves no
    element open at the end of the file.
    """
    closing = re.search(r"</body\s*>", document, re.IGNORECASE)
    if closing and re.search(r"</html\s*>", document[closing.end() :], re.IGNORECASE):
        return closing.start()
    implicit = not re.search(r"<(?:/?body|/?html)\b", document, re.IGNORECASE)
    if implicit and not parser.stack and document.rstrip().endswith(">"):
        return len(document.rstrip())
    raise RefreshError(
        "infographic is incomplete: it needs closing </body> and </html> tags, "
        "or no html/body tags and no element left open"
    )


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
    end = document_end(document, parse_source_tree(document))
    if re.match(r"</body", document[end:], re.IGNORECASE):
        return document[:end] + block + "\n" + document[end:]
    return document[:end] + "\n" + block + document[end:]


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
    model = parse_tasks(tasks)
    phases = model.phases
    done = model.done
    total = model.total
    previous_values = (previous or {}).get("values", {})
    effective_status = status if status is not None else previous_values.get("project-status")
    effective_date = generated_date if generated_date is not None else previous_values.get("generated-date")
    values: dict[str, str] = {
        "phase-count": str(len(phases)),
        "phase-done": str(sum(1 for phase in phases if phase.total and phase.done == phase.total)),
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
        "unphased_tasks_sha256": model.unphased_sha256,
        "footprint_sha256": effective_footprint_hash,
    }
    return {
        "schema": SCHEMA_VERSION,
        "source": source,
        "values": values,
        "phases": [asdict(phase) for phase in phases],
        "unphased_tasks": model.unphased_content,
        "decision_ids": decision_ids(sections),
        "plan_sections": sections,
        "stub": stub_reasons(plan, sections),
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
    hidden_sections: list[str] = []
    changed_phases: list[str] = []
    unphased_changed = False
    content_values: dict[str, str] = {}
    legacy: dict[str, Any] | None = None

    if current["stub"]:
        mode = "stub"
        reasons.extend(current["stub"])
    elif document is None:
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
        # A footprint is supplied only for a full build or an explicit footprint
        # refresh; without one the recorded footprint is carried forward.
        if (
            current["footprint_supplied"]
            and old_source.get("footprint_sha256") != current["source"].get("footprint_sha256")
        ):
            mode = "full-build"
            reasons.append("file-footprint-changed")

        all_changed_sections = changed_names(
            old_source.get("plan_sections", {}), current["source"]["plan_sections"]
        )
        hidden_sections = [
            name for name in all_changed_sections if INVISIBLE_PLAN_SECTION_RE.match(name)
        ]
        changed_sections = [name for name in all_changed_sections if name not in hidden_sections]
        changed_phases = changed_names(
            old_source.get("phase_structure", {}), current["source"]["phase_structure"]
        )
        # States written before unphased tracking have no baseline; do not flag them.
        unphased_changed = (
            "unphased_tasks_sha256" in old_source
            and old_source["unphased_tasks_sha256"] != current["source"]["unphased_tasks_sha256"]
        )
        if mode != "full-build" and (changed_sections or changed_phases or unphased_changed):
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
            if hidden_sections:
                reasons.append("unrendered-plan-sections-changed")

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
        "changed": {
            "plan_sections": section_payload,
            "phases": phase_payload,
            "unphased_tasks": current["unphased_tasks"] if unphased_changed else None,
            "unrendered_plan_sections": hidden_sections,
        },
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
    if len(replacements) > EXACT_PATCH_MAX_REPLACEMENTS:
        raise RefreshError(
            f"exact patch has more than {EXACT_PATCH_MAX_REPLACEMENTS} replacements"
        )
    total_size = 0
    updated = document
    for index, replacement in enumerate(replacements, start=1):
        if not isinstance(replacement, dict):
            raise RefreshError(f"exact patch replacement {index} must be an object")
        before = replacement.get("before")
        after = replacement.get("after")
        if not isinstance(before, str) or not isinstance(after, str) or not before:
            raise RefreshError(f"exact patch replacement {index} needs non-empty string before/after")
        if STATE_ID in before or STATE_ID in after:
            raise RefreshError(f"exact patch replacement {index} touches the embedded refresh state")
        total_size += len(before.encode("utf-8")) + len(after.encode("utf-8"))
        if total_size > EXACT_PATCH_MAX_BYTES:
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
    if current["stub"]:
        raise RefreshError("plan.md is an unfilled stub; fill Goal and Scope before migrating")
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
    if mode == "stub":
        raise RefreshError("plan.md is an unfilled stub; fill Goal and Scope before refreshing")
    if mode == "full-build" and not args.initialize:
        raise RefreshError(
            "full-build required; regenerate marked HTML, then rerun apply with --initialize"
        )
    if args.confirm_no_content_change and (args.content_patch or args.exact_patch):
        raise RefreshError("--confirm-no-content-change cannot be combined with a patch")
    if args.exact_patch and (mode != "semantic-refresh" or args.initialize):
        raise RefreshError(
            "--exact-patch applies only to a semantic-refresh; legacy pages use migrate"
        )
    if mode == "semantic-refresh" and not args.initialize and not (
        args.content_patch or args.exact_patch or args.confirm_no_content_change
    ):
        raise RefreshError(
            "semantic-refresh requires --content-patch, --exact-patch, "
            "or --confirm-no-content-change"
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

    # The exact patch's `before` fragments come from the current HTML, so they apply
    # before derived values move; bindings must survive the patch intact.
    patch_path = Path(args.exact_patch).resolve() if args.exact_patch else None
    patched, replacement_count = apply_exact_patch(document, patch_path)
    if style_hash(patched) != original_style_hash:
        raise RefreshError("exact patch changed the infographic CSS")
    if replacement_count:
        validate_bindings(patched, current)

    updated = apply_derived_bindings(patched, current)

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
        "exact_replacements": replacement_count,
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
    document_end(document, parse_source_tree(document))
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
    apply_command.add_argument(
        "--exact-patch",
        help='semantic-refresh only: bounded JSON shaped as {"replacements": [...]}',
    )
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
