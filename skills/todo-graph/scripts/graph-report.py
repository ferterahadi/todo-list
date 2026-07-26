#!/usr/bin/env python3
"""Compile the todo hub's Markdown projects into a deterministic work graph.

The compiler is deliberately read-only. Human-facing modes emit bounded TSV; only
``export`` is unbounded. Canonical edges come from ``plan.md`` Relationship tables.
Legacy registry ``related`` values are context hints and never affect readiness.
"""

from __future__ import annotations

import json
import re
import sys
from collections import defaultdict, deque
from dataclasses import asdict, dataclass, field
from pathlib import Path, PurePosixPath
from typing import Iterable, Iterator, Sequence


SCHEMA_VERSION = 1
ROW_LIMIT = 20
AUDIT_LIMIT = 50
FIELD_LIMIT = 240
ALLOWED_RELATIONS = {"depends-on", "related-to", "supersedes"}
ACTIVE_STATUSES = {"planning", "ready", "in-progress", "done"}
SEVERITY_ORDER = {"ERROR": 0, "WARNING": 1}
GLOBAL_ERROR_CODES = {
    "DUPLICATE_IDENTITY",
    "MISSING_REGISTRY",
    "REGISTRY_SCHEMA",
    "UNKNOWN_STATUS",
}
REVISION_RE = re.compile(
    r"^###\s+(R[0-9]+[A-Za-z]*)\b.*\[\s*open(?:\s+[^\]]*)?\s*\]\s*$",
    re.IGNORECASE,
)
CHECKBOX_RE = re.compile(r"^\s*-\s+\[([ xX])\]\s+")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$")
FENCE_RE = re.compile(r"^\s*(`{3,}|~{3,})")


@dataclass
class TaskStats:
    exists: bool = False
    total: int = 0
    done: int = 0
    open_revisions: int = 0

    @property
    def open_tasks(self) -> int:
        return max(0, self.total - self.done)


@dataclass
class Node:
    name: str
    project_path: str
    repo: str
    status: str
    registry: str
    section: str
    related: list[str]
    registry_file: str
    registry_line: int
    tasks: TaskStats = field(default_factory=TaskStats)

    @property
    def settled(self) -> bool:
        return (
            self.status.casefold() == "done"
            and self.tasks.exists
            and self.tasks.total > 0
            and self.tasks.open_tasks == 0
            and self.tasks.open_revisions == 0
        )

    @property
    def location(self) -> str:
        return f"{self.registry_file}:{self.registry_line}"


@dataclass
class Edge:
    source: str
    relation: str
    target: str
    reason: str
    origin: str
    location: str
    resolved_target: str | None = None
    valid: bool = False
    errors: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class Issue:
    severity: str
    code: str
    source: str
    target: str
    location: str
    detail: str

    def sort_key(self) -> tuple[object, ...]:
        return (
            SEVERITY_ORDER.get(self.severity, 9),
            self.code,
            self.source,
            self.target,
            self.location,
            self.detail,
        )


class Graph:
    def __init__(self, hub: Path) -> None:
        self.hub = hub
        self.all_nodes: list[Node] = []
        self.identities: dict[str, list[Node]] = defaultdict(list)
        self.nodes: dict[str, Node] = {}
        self.edges: list[Edge] = []
        self.issues: list[Issue] = []
        self._issue_keys: set[Issue] = set()
        self.hard_out: dict[str, set[str]] = defaultdict(set)
        self.hard_in: dict[str, set[str]] = defaultdict(set)
        self.cycle_members: dict[str, tuple[str, ...]] = {}

    def add_issue(
        self,
        severity: str,
        code: str,
        source: str = "-",
        target: str = "-",
        location: str = "-",
        detail: str = "-",
    ) -> None:
        issue = Issue(
            severity,
            code,
            source or "-",
            target or "-",
            location or "-",
            compact(detail),
        )
        if issue not in self._issue_keys:
            self._issue_keys.add(issue)
            self.issues.append(issue)

    def sorted_issues(self) -> list[Issue]:
        return sorted(self.issues, key=Issue.sort_key)

    def blocking_errors_for(self, name: str) -> list[Issue]:
        return self.blocking_errors_for_names({name})

    def source_errors_for(self, name: str) -> list[Issue]:
        return [
            issue
            for issue in self.sorted_issues()
            if issue.severity == "ERROR" and issue.source == name
        ]

    def owned_issues_for_names(self, names: set[str]) -> list[Issue]:
        return [
            issue
            for issue in self.sorted_issues()
            if issue.source in names
            or issue.code in GLOBAL_ERROR_CODES
            or (issue.source == "-" and issue.target == "-")
        ]

    def blocking_errors_for_names(self, names: set[str]) -> list[Issue]:
        return [
            issue
            for issue in self.owned_issues_for_names(names)
            if issue.severity == "ERROR"
        ]

    def resolve(self, name: str) -> tuple[Node | None, str | None, str]:
        """Resolve an exact active-first identity, while refusing duplicates."""
        exact = self.identities.get(name, [])
        if len(exact) > 1:
            return None, "DUPLICATE_IDENTITY", ",".join(node.location for node in exact)
        if len(exact) == 1:
            return exact[0], None, ""

        folded = sorted(
            candidate
            for candidate in self.identities
            if candidate.casefold() == name.casefold()
        )
        if folded:
            return None, "NAME_CASE_MISMATCH", ",".join(folded)
        return None, "MISSING_PROJECT", name

    def dependency_blockers(self, node: Node) -> list[str]:
        blockers: set[str] = set()
        for issue in self.blocking_errors_for(node.name):
            if issue.code not in {"ACTIVE_DONE"}:
                blockers.add(f"error:{issue.code}")

        for edge in self.edges:
            if (
                edge.origin != "canonical"
                or edge.source != node.name
                or edge.relation != "depends-on"
            ):
                continue
            if not edge.valid or edge.resolved_target is None:
                blockers.add(f"invalid:{edge.target}")
                continue
            target = self.nodes.get(edge.resolved_target)
            if target is None:
                blockers.add(f"invalid:{edge.target}")
            elif not self.dependency_target_ready(target):
                error_codes = sorted(
                    {issue.code for issue in self.source_errors_for(target.name)}
                )
                state = (
                    f"{target.status};"
                    f"open={target.tasks.open_tasks};"
                    f"revisions={target.tasks.open_revisions}"
                )
                if error_codes:
                    state += f";errors={','.join(error_codes)}"
                blockers.add(
                    f"{target.name}({state})"
                )
        return sorted(blockers)

    def dependency_target_ready(self, node: Node) -> bool:
        return node.settled and not self.source_errors_for(node.name)

    def is_runnable(self, node: Node) -> bool:
        status = node.status.casefold()
        return (
            node.registry == "active"
            and status in {"ready", "in-progress"}
            and (
                status == "in-progress"
                or node.tasks.open_tasks > 0
                or node.tasks.open_revisions > 0
            )
            and not self.dependency_blockers(node)
        )


def compact(value: object) -> str:
    return re.sub(r"\s+", " ", str(value)).strip().replace("\t", " ")


def atom(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == "`" and value[-1] == "`":
        value = value[1:-1].strip()
    return value


def split_markdown_row(line: str) -> list[str]:
    text = line.strip()
    leading = text.startswith("|")
    trailing = text.endswith("|") and not text.endswith(r"\|")
    cells: list[str] = []
    current: list[str] = []
    index = 0
    while index < len(text):
        char = text[index]
        if char == "\\" and index + 1 < len(text) and text[index + 1] == "|":
            current.append("|")
            index += 2
            continue
        if char == "|":
            cells.append("".join(current).strip())
            current = []
        else:
            current.append(char)
        index += 1
    cells.append("".join(current).strip())
    if leading and cells and cells[0] == "":
        cells.pop(0)
    if trailing and cells and cells[-1] == "":
        cells.pop()
    return cells


def is_separator(cells: Sequence[str]) -> bool:
    return bool(cells) and all(
        re.fullmatch(r":?-{3,}:?", cell.strip()) is not None for cell in cells
    )


def visible_lines(path: Path) -> list[tuple[int, str]]:
    if not path.is_file():
        return []

    result: list[tuple[int, str]] = []
    in_comment = False
    fence_char = ""
    fence_len = 0

    for line_number, raw in enumerate(
        path.read_text(encoding="utf-8", errors="replace").splitlines(), 1
    ):
        if fence_char:
            stripped = raw.lstrip()
            if re.match(
                rf"^{re.escape(fence_char)}{{{fence_len},}}\s*$", stripped
            ):
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
            marker = fence.group(1)
            fence_char = marker[0]
            fence_len = len(marker)
            continue

        if line.strip():
            result.append((line_number, line.rstrip()))
    return result


def normalize_header(value: str) -> str:
    return re.sub(r"\s+", " ", atom(value).casefold().strip())


def parse_registry(graph: Graph, file_name: str, registry: str) -> None:
    path = graph.hub / file_name
    if not path.is_file():
        if registry == "active":
            graph.add_issue(
                "ERROR",
                "MISSING_REGISTRY",
                location=file_name,
                detail=f"{file_name} does not exist",
            )
        return

    lines = visible_lines(path)
    section = "-"
    found_table = False
    index = 0
    while index < len(lines):
        line_number, line = lines[index]
        heading = HEADING_RE.match(line)
        if heading and len(heading.group(1)) == 2:
            section = compact(heading.group(2))
            index += 1
            continue

        if not line.lstrip().startswith("|"):
            index += 1
            continue

        headers = split_markdown_row(line)
        normalized = [normalize_header(header) for header in headers]
        required = {"short-name", "path", "status"}
        if not required.issubset(normalized):
            index += 1
            continue
        found_table = True
        columns = {header: position for position, header in enumerate(normalized)}
        if index + 1 >= len(lines) or not is_separator(
            split_markdown_row(lines[index + 1][1])
        ):
            graph.add_issue(
                "ERROR",
                "REGISTRY_SCHEMA",
                location=f"{file_name}:{line_number}",
                detail="registry header is not followed by a separator",
            )
            index += 1
            continue

        index += 2
        while index < len(lines) and lines[index][1].lstrip().startswith("|"):
            row_number, row_line = lines[index]
            cells = split_markdown_row(row_line)
            if is_separator(cells):
                index += 1
                continue
            if len(cells) < len(headers):
                cells.extend([""] * (len(headers) - len(cells)))

            def cell(name: str, default: str = "-") -> str:
                position = columns.get(name)
                if position is None or position >= len(cells):
                    return default
                return atom(cells[position]) or default

            name = cell("short-name")
            if name not in {"-", "short-name"}:
                related_cell = cell("related")
                related = (
                    []
                    if related_cell == "-"
                    else [
                        atom(item)
                        for item in related_cell.split(",")
                        if atom(item) and atom(item) != "-"
                    ]
                )
                node = Node(
                    name=name,
                    project_path=cell("path"),
                    repo=cell("repo"),
                    status=cell("status").casefold(),
                    registry=registry,
                    section=section,
                    related=related,
                    registry_file=file_name,
                    registry_line=row_number,
                )
                graph.all_nodes.append(node)
                graph.identities[name].append(node)
            index += 1

    if not found_table:
        graph.add_issue(
            "ERROR",
            "REGISTRY_SCHEMA",
            location=file_name,
            detail="no project table found",
        )


def safe_project_dir(graph: Graph, node: Node) -> Path | None:
    raw = atom(node.project_path)
    pure = PurePosixPath(raw)
    if raw in {"", "-"} or pure.is_absolute() or ".." in pure.parts:
        graph.add_issue(
            "ERROR",
            "INVALID_PROJECT_PATH",
            source=node.name,
            location=node.location,
            detail=f"unsafe project path: {raw}",
        )
        return None
    try:
        candidate = graph.hub.joinpath(*pure.parts).resolve()
    except (OSError, RuntimeError) as error:
        graph.add_issue(
            "ERROR",
            "INVALID_PROJECT_PATH",
            source=node.name,
            location=node.location,
            detail=f"cannot resolve project path {raw}: {error}",
        )
        return None
    try:
        candidate.relative_to(graph.hub)
    except ValueError:
        graph.add_issue(
            "ERROR",
            "INVALID_PROJECT_PATH",
            source=node.name,
            location=node.location,
            detail=f"project path escapes hub: {raw}",
        )
        return None
    return candidate


def safe_project_file(
    graph: Graph, node: Node, project_dir: Path, file_name: str
) -> Path | None:
    candidate = project_dir / file_name
    try:
        resolved = candidate.resolve()
    except (OSError, RuntimeError) as error:
        graph.add_issue(
            "ERROR",
            "INVALID_PROJECT_PATH",
            source=node.name,
            location=node.location,
            detail=f"cannot resolve {file_name}: {error}",
        )
        return None
    try:
        resolved.relative_to(graph.hub)
    except ValueError:
        graph.add_issue(
            "ERROR",
            "INVALID_PROJECT_PATH",
            source=node.name,
            location=node.location,
            detail=f"{file_name} escapes hub through project path",
        )
        return None
    return candidate


def parse_task_stats(path: Path) -> TaskStats:
    if not path.is_file():
        return TaskStats(exists=False)

    total = 0
    done = 0
    open_revisions = 0
    section = ""
    count_checkboxes = False
    excluded_sections = {"status", "notes", "context"}

    for _, line in visible_lines(path):
        heading = HEADING_RE.match(line)
        if heading:
            level = len(heading.group(1))
            title = heading.group(2).strip()
            if level == 2:
                section = title.casefold()
                count_checkboxes = section not in excluded_sections
            if section == "revisions" and REVISION_RE.match(line):
                open_revisions += 1
            continue

        checkbox = CHECKBOX_RE.match(line)
        if checkbox and count_checkboxes:
            total += 1
            if checkbox.group(1).casefold() == "x":
                done += 1

    return TaskStats(
        exists=True,
        total=total,
        done=done,
        open_revisions=open_revisions,
    )


def relationship_sections(lines: list[tuple[int, str]]) -> list[list[tuple[int, str]]]:
    sections: list[list[tuple[int, str]]] = []
    index = 0
    while index < len(lines):
        _, line = lines[index]
        heading = HEADING_RE.match(line)
        if (
            heading
            and len(heading.group(1)) == 2
            and heading.group(2).strip().casefold() == "relationships"
        ):
            start = index + 1
            end = start
            while end < len(lines):
                next_heading = HEADING_RE.match(lines[end][1])
                if next_heading and len(next_heading.group(1)) <= 2:
                    break
                end += 1
            sections.append(lines[start:end])
            index = end
            continue
        index += 1
    return sections


def parse_canonical_edges(graph: Graph, node: Node, plan_path: Path) -> None:
    if not plan_path.is_file():
        graph.add_issue(
            "ERROR",
            "MISSING_PLAN",
            source=node.name,
            location=str(plan_path.relative_to(graph.hub)),
            detail="plan.md does not exist",
        )
        return

    relative_plan = str(plan_path.relative_to(graph.hub))
    sections = relationship_sections(visible_lines(plan_path))
    if len(sections) > 1:
        graph.add_issue(
            "ERROR",
            "DUPLICATE_RELATIONSHIPS_SECTION",
            source=node.name,
            location=relative_plan,
            detail=f"found {len(sections)} Relationships sections",
        )

    seen: dict[tuple[str, str], Edge] = {}
    for section in sections:
        table_found = False
        index = 0
        while index < len(section):
            line_number, line = section[index]
            if not line.lstrip().startswith("|"):
                index += 1
                continue
            headers = split_markdown_row(line)
            normalized = [normalize_header(header) for header in headers]
            required = {"relation", "target", "reason"}
            if not required.issubset(normalized):
                index += 1
                continue
            table_found = True
            columns = {header: position for position, header in enumerate(normalized)}
            if index + 1 >= len(section) or not is_separator(
                split_markdown_row(section[index + 1][1])
            ):
                graph.add_issue(
                    "ERROR",
                    "RELATIONSHIP_SCHEMA",
                    source=node.name,
                    location=f"{relative_plan}:{line_number}",
                    detail="relationship header is not followed by a separator",
                )
                index += 1
                continue

            index += 2
            while index < len(section) and section[index][1].lstrip().startswith("|"):
                row_number, row_line = section[index]
                cells = split_markdown_row(row_line)
                if is_separator(cells):
                    index += 1
                    continue
                if len(cells) < len(headers):
                    cells.extend([""] * (len(headers) - len(cells)))

                relation = atom(cells[columns["relation"]]).casefold()
                target = atom(cells[columns["target"]])
                reason = compact(cells[columns["reason"]])
                if not any((relation, target, reason)):
                    index += 1
                    continue

                edge = Edge(
                    source=node.name,
                    relation=relation,
                    target=target,
                    reason=reason,
                    origin="canonical",
                    location=f"{relative_plan}:{row_number}",
                )
                if relation not in ALLOWED_RELATIONS:
                    edge.errors.append("UNKNOWN_RELATION")
                    graph.add_issue(
                        "ERROR",
                        "UNKNOWN_RELATION",
                        source=node.name,
                        target=target or "-",
                        location=edge.location,
                        detail=f"relation={relation or '-'}",
                    )
                if not target:
                    edge.errors.append("MISSING_TARGET")
                    graph.add_issue(
                        "ERROR",
                        "MISSING_TARGET",
                        source=node.name,
                        location=edge.location,
                        detail="relationship target is empty",
                    )
                if not reason:
                    edge.errors.append("MISSING_REASON")
                    graph.add_issue(
                        "ERROR",
                        "MISSING_REASON",
                        source=node.name,
                        target=target or "-",
                        location=edge.location,
                        detail="canonical relationship reason is empty",
                    )

                signature = (relation, target)
                if signature in seen:
                    edge.errors.append("DUPLICATE_CANONICAL_EDGE")
                    graph.add_issue(
                        "ERROR",
                        "DUPLICATE_CANONICAL_EDGE",
                        source=node.name,
                        target=target or "-",
                        location=edge.location,
                        detail=f"first={seen[signature].location}",
                    )
                else:
                    seen[signature] = edge
                graph.edges.append(edge)
                index += 1
            continue

        visible_content = [line for _, line in section if line.strip()]
        if visible_content and not table_found:
            first_line = section[0][0]
            graph.add_issue(
                "ERROR",
                "RELATIONSHIP_SCHEMA",
                source=node.name,
                location=f"{relative_plan}:{first_line}",
                detail="Relationships section has no relation|target|reason table",
            )


def resolve_edge(graph: Graph, edge: Edge) -> None:
    if not edge.target:
        return
    exact = graph.identities.get(edge.target, [])
    if len(exact) == 1:
        edge.resolved_target = exact[0].name
    elif len(exact) > 1:
        code = "AMBIGUOUS_TARGET"
        edge.errors.append(code)
        graph.add_issue(
            "ERROR" if edge.origin == "canonical" else "WARNING",
            code,
            source=edge.source,
            target=edge.target,
            location=edge.location,
            detail="target identity appears more than once",
        )
        return
    else:
        case_matches = sorted(
            name
            for name in graph.identities
            if name.casefold() == edge.target.casefold()
        )
        if case_matches:
            code = "TARGET_CASE_MISMATCH"
            detail = f"exact target not found; candidates={','.join(case_matches)}"
        else:
            code = "MISSING_TARGET"
            detail = "exact target not found"
        edge.errors.append(code)
        graph.add_issue(
            "ERROR" if edge.origin == "canonical" else "WARNING",
            code,
            source=edge.source,
            target=edge.target,
            location=edge.location,
            detail=detail,
        )
        return

    if edge.source == edge.resolved_target:
        code = "SELF_EDGE" if edge.origin == "canonical" else "LEGACY_SELF_EDGE"
        edge.errors.append(code)
        graph.add_issue(
            "ERROR" if edge.origin == "canonical" else "WARNING",
            code,
            source=edge.source,
            target=edge.target,
            location=edge.location,
            detail="source and target are identical",
        )
        return

    edge.valid = not edge.errors


def add_legacy_edges(graph: Graph, node: Node) -> None:
    canonical_targets = {
        edge.target
        for edge in graph.edges
        if edge.origin == "canonical" and edge.source == node.name
    }
    seen: set[str] = set()
    for target in node.related:
        if target in seen or target in canonical_targets:
            continue
        seen.add(target)
        edge = Edge(
            source=node.name,
            relation="related-to",
            target=target,
            reason="legacy registry related hint",
            origin="legacy",
            location=node.location,
        )
        graph.edges.append(edge)


def strongly_connected_components(
    nodes: Iterable[str], adjacency: dict[str, set[str]]
) -> list[tuple[str, ...]]:
    ordered_nodes = sorted(set(nodes))
    node_set = set(ordered_nodes)
    neighbors = {
        node: tuple(
            target
            for target in sorted(adjacency.get(node, set()))
            if target in node_set
        )
        for node in ordered_nodes
    }
    reverse: dict[str, list[str]] = {node: [] for node in ordered_nodes}
    for node in ordered_nodes:
        for target in neighbors[node]:
            reverse[target].append(node)
    for node in ordered_nodes:
        reverse[node].sort()

    visited: set[str] = set()
    finish_order: list[str] = []
    for root in ordered_nodes:
        if root in visited:
            continue
        visited.add(root)
        stack: list[tuple[str, int]] = [(root, 0)]
        while stack:
            node, child_index = stack[-1]
            if child_index < len(neighbors[node]):
                target = neighbors[node][child_index]
                stack[-1] = (node, child_index + 1)
                if target not in visited:
                    visited.add(target)
                    stack.append((target, 0))
                continue
            finish_order.append(node)
            stack.pop()

    visited.clear()
    components: list[tuple[str, ...]] = []
    for root in reversed(finish_order):
        if root in visited:
            continue
        visited.add(root)
        component: list[str] = []
        stack = [root]
        while stack:
            node = stack.pop()
            component.append(node)
            for predecessor in reversed(reverse[node]):
                if predecessor not in visited:
                    visited.add(predecessor)
                    stack.append(predecessor)
        components.append(tuple(sorted(component)))
    return sorted(components)


def compile_graph(hub_arg: str) -> Graph:
    hub = Path(hub_arg).expanduser().resolve()
    graph = Graph(hub)
    parse_registry(graph, "index.md", "active")
    parse_registry(graph, "archive.md", "archive")

    for name, entries in sorted(graph.identities.items()):
        if len(entries) > 1:
            graph.add_issue(
                "ERROR",
                "DUPLICATE_IDENTITY",
                source=name,
                location=",".join(node.location for node in entries),
                detail="identity appears in multiple registry rows",
            )
        else:
            graph.nodes[name] = entries[0]

    for name in sorted(graph.nodes):
        node = graph.nodes[name]
        status = node.status.casefold()
        if status not in ACTIVE_STATUSES:
            graph.add_issue(
                "ERROR",
                "UNKNOWN_STATUS",
                source=name,
                location=node.location,
                detail=f"status={node.status}",
            )
        if node.registry == "active" and status == "done":
            graph.add_issue(
                "WARNING",
                "ACTIVE_DONE",
                source=name,
                location=node.location,
                detail="done project belongs in archive.md",
            )
        if node.registry == "archive" and status != "done":
            graph.add_issue(
                "ERROR",
                "ARCHIVE_NON_DONE",
                source=name,
                location=node.location,
                detail=f"archived status={node.status}",
            )

        project_dir = safe_project_dir(graph, node)
        if project_dir is None:
            continue
        tasks_path = safe_project_file(graph, node, project_dir, "tasks.md")
        plan_path = safe_project_file(graph, node, project_dir, "plan.md")
        if tasks_path is not None:
            node.tasks = parse_task_stats(tasks_path)
        if tasks_path is None:
            pass
        elif not node.tasks.exists:
            graph.add_issue(
                "ERROR",
                "DONE_MISSING_TASKS" if status == "done" else "MISSING_TASKS",
                source=name,
                location=str(tasks_path.relative_to(graph.hub)),
                detail="tasks.md does not exist",
            )
        elif status == "done" and (
            node.tasks.open_tasks > 0 or node.tasks.open_revisions > 0
        ):
            graph.add_issue(
                "ERROR",
                "DONE_OPEN_WORK",
                source=name,
                location=str(tasks_path.relative_to(graph.hub)),
                detail=(
                    f"open_tasks={node.tasks.open_tasks};"
                    f"open_revisions={node.tasks.open_revisions}"
                ),
            )
        elif status == "done" and node.tasks.total == 0:
            graph.add_issue(
                "ERROR",
                "DONE_NO_TASKS",
                source=name,
                location=str(tasks_path.relative_to(graph.hub)),
                detail="done status has no task evidence",
            )
        elif status == "ready" and node.tasks.open_tasks == 0:
            graph.add_issue(
                "ERROR",
                "READY_NO_OPEN_WORK",
                source=name,
                location=str(tasks_path.relative_to(graph.hub)),
                detail="ready status has no open tasks",
            )
        if plan_path is not None:
            parse_canonical_edges(graph, node, plan_path)

    for name in sorted(graph.nodes):
        add_legacy_edges(graph, graph.nodes[name])

    for edge in graph.edges:
        resolve_edge(graph, edge)

    # Cycle membership uses every resolved canonical dependency, including a self-edge.
    cycle_adjacency: dict[str, set[str]] = defaultdict(set)
    for edge in graph.edges:
        if (
            edge.origin == "canonical"
            and edge.relation == "depends-on"
            and edge.resolved_target is not None
            and edge.source in graph.nodes
            and edge.resolved_target in graph.nodes
        ):
            cycle_adjacency[edge.source].add(edge.resolved_target)

        if (
            edge.origin == "canonical"
            and edge.relation == "depends-on"
            and edge.valid
            and edge.resolved_target is not None
        ):
            graph.hard_out[edge.source].add(edge.resolved_target)
            graph.hard_in[edge.resolved_target].add(edge.source)

    for component in strongly_connected_components(graph.nodes, cycle_adjacency):
        is_self_cycle = (
            len(component) == 1
            and component[0] in cycle_adjacency.get(component[0], set())
        )
        if len(component) > 1 or is_self_cycle:
            for member in component:
                graph.cycle_members[member] = component
                locations = sorted(
                    edge.location
                    for edge in graph.edges
                    if edge.origin == "canonical"
                    and edge.relation == "depends-on"
                    and edge.source == member
                    and edge.resolved_target in component
                )
                graph.add_issue(
                    "ERROR",
                    "DEPENDENCY_CYCLE",
                    source=member,
                    location=",".join(locations) or "plan.md",
                    detail=f"members={','.join(component)}",
                )

    return graph


def display(value: object) -> str:
    text = compact(value)
    encoded = text.encode("utf-8")
    if len(encoded) <= FIELD_LIMIT:
        return text
    prefix = encoded[: FIELD_LIMIT - 3]
    while True:
        try:
            return f"{prefix.decode('utf-8')}..."
        except UnicodeDecodeError:
            prefix = prefix[:-1]


def row(*values: object) -> str:
    return "\t".join(display(value) if value != "" else "-" for value in values)


def export_row(*values: object) -> str:
    return "\t".join(compact(value) if value != "" else "-" for value in values)


def issue_row(issue: Issue, *, bounded: bool = True) -> str:
    render = row if bounded else export_row
    return render(
        issue.severity,
        issue.code,
        issue.source,
        issue.target,
        issue.location,
        issue.detail,
    )


def emit_bounded(
    records: Sequence[str], category: str, limit: int = ROW_LIMIT
) -> None:
    for record in records[:limit]:
        print(record)
    if len(records) > limit:
        print(row("TRUNCATED", category, len(records) - limit))


def summary(graph: Graph) -> dict[str, int]:
    return {
        "nodes": len(graph.nodes),
        "active": sum(node.registry == "active" for node in graph.nodes.values()),
        "archived": sum(node.registry == "archive" for node in graph.nodes.values()),
        "canonical_edges": sum(edge.origin == "canonical" for edge in graph.edges),
        "legacy_edges": sum(edge.origin == "legacy" for edge in graph.edges),
        "errors": sum(issue.severity == "ERROR" for issue in graph.issues),
        "warnings": sum(issue.severity == "WARNING" for issue in graph.issues),
    }


def print_summary(mode: str, graph: Graph, **extra: int) -> None:
    values = summary(graph)
    values.update(extra)
    fields: list[object] = ["SUMMARY", mode]
    fields.extend(f"{key}={values[key]}" for key in sorted(values))
    print(row(*fields))


def query_node(graph: Graph, name: str) -> Node | None:
    node, code, detail = graph.resolve(name)
    if node is None:
        print(row("ERROR", code or "MISSING_PROJECT", name, "-", "-", detail))
    return node


def relevant_issues(graph: Graph, names: set[str]) -> list[Issue]:
    return [
        issue
        for issue in graph.sorted_issues()
        if issue.source in names or issue.target in names
    ]


def mode_frontier(graph: Graph) -> int:
    in_flight: list[str] = []
    ready: list[str] = []
    blocked: list[str] = []
    planning: list[str] = []

    frontier_nodes = sorted(
        (
            item
            for item in graph.nodes.values()
            if item.registry == "active"
            and item.status.casefold() in {"planning", "ready", "in-progress"}
        ),
        key=lambda item: item.name,
    )
    for node in frontier_nodes:
        status = node.status.casefold()
        progress = f"{node.tasks.done}/{node.tasks.total}"
        blockers = graph.dependency_blockers(node)
        if status in {"ready", "in-progress"} and blockers:
            blocked.append(
                row(
                    "BLOCKED",
                    node.name,
                    status,
                    progress,
                    f"revisions={node.tasks.open_revisions}",
                    ",".join(blockers),
                )
            )
        elif status == "in-progress":
            in_flight.append(
                row(
                    "IN_FLIGHT",
                    node.name,
                    status,
                    progress,
                    f"revisions={node.tasks.open_revisions}",
                )
            )
        elif status == "ready":
            ready.append(
                row(
                    "READY",
                    node.name,
                    status,
                    progress,
                    f"revisions={node.tasks.open_revisions}",
                )
            )
        elif status == "planning":
            planning.append(
                row(
                    "PLANNING",
                    node.name,
                    status,
                    progress,
                    f"revisions={node.tasks.open_revisions}",
                )
            )

    relevant_names = {node.name for node in frontier_nodes}
    for node in frontier_nodes:
        relevant_names.update(graph.hard_out.get(node.name, set()))
    issues = graph.owned_issues_for_names(relevant_names)
    print_summary(
        "frontier",
        graph,
        in_flight=len(in_flight),
        ready=len(ready),
        blocked=len(blocked),
        planning=len(planning),
        relevant_errors=sum(issue.severity == "ERROR" for issue in issues),
        relevant_warnings=sum(issue.severity == "WARNING" for issue in issues),
    )
    emit_bounded(in_flight, "in_flight")
    emit_bounded(ready, "ready")
    emit_bounded(blocked, "blocked")
    emit_bounded(planning, "planning")
    emit_bounded(
        [issue_row(issue) for issue in issues],
        "issues",
        ROW_LIMIT,
    )
    return 1 if any(issue.severity == "ERROR" for issue in issues) else 0


def mode_context(graph: Graph, name: str) -> int:
    node = query_node(graph, name)
    if node is None:
        return 1

    blockers = graph.dependency_blockers(node)
    print(
        row(
            "NODE",
            node.name,
            node.registry,
            node.section,
            node.status,
            f"settled={str(node.settled).lower()}",
            f"runnable={str(graph.is_runnable(node)).lower()}",
            f"tasks={node.tasks.done}/{node.tasks.total}",
            f"open_revisions={node.tasks.open_revisions}",
            node.project_path,
        )
    )

    records: list[str] = []
    for edge in sorted(
        (item for item in graph.edges if item.source == node.name),
        key=lambda item: (
            item.relation,
            item.target,
            item.origin,
            item.location,
        ),
    ):
        target = graph.nodes.get(edge.resolved_target or "")
        records.append(
            row(
                "OUT",
                edge.relation,
                edge.target,
                f"origin={edge.origin}",
                f"valid={str(edge.valid).lower()}",
                f"status={target.status if target else '-'}",
                f"settled={str(target.settled).lower() if target else '-'}",
                (
                    f"errors={','.join(edge.errors)}"
                    if edge.errors
                    else "errors=-"
                ),
                edge.reason,
            )
        )
    for edge in sorted(
        (
            item
            for item in graph.edges
            if item.resolved_target == node.name and item.source != node.name
        ),
        key=lambda item: (
            item.relation,
            item.source,
            item.origin,
            item.location,
        ),
    ):
        records.append(
            row(
                "IN",
                edge.relation,
                edge.source,
                f"origin={edge.origin}",
                f"valid={str(edge.valid).lower()}",
                (
                    f"errors={','.join(edge.errors)}"
                    if edge.errors
                    else "errors=-"
                ),
                edge.reason,
            )
        )
    if blockers:
        records.append(row("BLOCKERS", node.name, ",".join(blockers)))
    emit_bounded(records, "connections")

    issues = graph.owned_issues_for_names({node.name})
    emit_bounded([issue_row(issue) for issue in issues], "issues", AUDIT_LIMIT)
    print_summary(
        "context",
        graph,
        connections=len(records),
        relevant_issues=len(issues),
    )
    return 1 if any(issue.severity == "ERROR" for issue in issues) else 0


def shortest_blocking_chains(
    graph: Graph, source: Node
) -> tuple[list[list[str]], int, set[str]]:
    parents: dict[str, str | None] = {source.name: None}
    queue: deque[str] = deque([source.name])
    terminals: list[str] = []
    while queue:
        current_name = queue.popleft()
        current = graph.nodes[current_name]
        unresolved = sorted(
            target
            for target in graph.hard_out.get(current_name, set())
            if target in graph.nodes
            and not graph.dependency_target_ready(graph.nodes[target])
        )
        if (
            not unresolved
            and current_name != source.name
            and not graph.dependency_target_ready(current)
        ):
            terminals.append(current_name)
            continue
        for target in unresolved:
            if target not in parents:
                parents[target] = current_name
                queue.append(target)

    chains: list[list[str]] = []
    for terminal in terminals[:ROW_LIMIT]:
        path: list[str] = []
        current_name: str | None = terminal
        while current_name is not None:
            path.append(current_name)
            current_name = parents[current_name]
        chains.append(list(reversed(path)))
    return (
        sorted(chains, key=lambda path: (len(path), tuple(path))),
        len(terminals),
        set(parents),
    )


def mode_why(graph: Graph, name: str) -> int:
    node = query_node(graph, name)
    if node is None:
        return 1

    chain_paths, chain_count, involved_names = shortest_blocking_chains(graph, node)
    issues = graph.owned_issues_for_names(involved_names)
    errors = graph.blocking_errors_for_names(involved_names)
    blockers = graph.dependency_blockers(node)
    status = node.status.casefold()
    if graph.is_runnable(node):
        print(row("RUNNABLE", node.name, node.status, "all dependencies settled"))
    elif node.settled:
        print(row("SETTLED", node.name, node.status, "no open work"))
    elif errors:
        print(row("BLOCKED", node.name, node.status, "invalid graph or state"))
    elif status == "planning":
        print(row("BLOCKED", node.name, node.status, "project still needs planning"))
    elif blockers:
        print(row("BLOCKED", node.name, node.status, ",".join(blockers)))
    else:
        print(row("BLOCKED", node.name, node.status, "project is not runnable"))

    chains: list[str] = []
    for path in chain_paths:
        terminal = graph.nodes[path[-1]]
        chains.append(
            row(
                "CHAIN",
                node.name,
                f"hops={len(path) - 1}",
                " -> ".join(path),
                f"terminal_status={terminal.status}",
                f"terminal_tasks={terminal.tasks.done}/{terminal.tasks.total}",
                f"terminal_revisions={terminal.tasks.open_revisions}",
            )
        )
    for chain in chains:
        print(chain)
    if chain_count > len(chains):
        print(row("TRUNCATED", "chains", chain_count - len(chains)))
    emit_bounded([issue_row(issue) for issue in issues], "issues", AUDIT_LIMIT)
    print_summary("why", graph, chains=chain_count, relevant_issues=len(issues))
    return 1 if errors else 0


def reverse_paths(graph: Graph, source: str) -> dict[str, list[str]]:
    paths: dict[str, list[str]] = {source: [source]}
    queue: deque[str] = deque([source])
    while queue:
        current = queue.popleft()
        for dependent in sorted(graph.hard_in.get(current, set())):
            if dependent not in paths:
                paths[dependent] = paths[current] + [dependent]
                queue.append(dependent)
    paths.pop(source, None)
    return paths


def mode_impact(graph: Graph, name: str) -> int:
    node = query_node(graph, name)
    if node is None:
        return 1

    dependency_ready = graph.dependency_target_ready(node)
    source_errors = graph.source_errors_for(node.name)
    if dependency_ready:
        print(row("ALREADY_SETTLED", node.name, node.status, node.location))

    paths = reverse_paths(graph, node.name)
    records: list[str] = []
    for dependent, path in sorted(
        paths.items(), key=lambda item: (len(item[1]), tuple(item[1]))
    ):
        dependent_node = graph.nodes[dependent]
        other_unsettled = sorted(
            prerequisite
            for prerequisite in graph.hard_out.get(dependent, set())
            if prerequisite != path[-2]
            and prerequisite in graph.nodes
            and not graph.dependency_target_ready(graph.nodes[prerequisite])
        )
        immediately_runnable = (
            len(path) == 2
            and not other_unsettled
            and dependent_node.registry == "active"
            and dependent_node.status.casefold() in {"ready", "in-progress"}
            and not graph.blocking_errors_for(dependent)
        )
        if dependency_ready and len(path) == 2:
            kind = "DEPENDENT"
        elif source_errors:
            kind = "AFFECTS"
        else:
            kind = "UNLOCKS" if immediately_runnable else "AFFECTS"
        records.append(
            row(
                kind,
                dependent,
                f"distance={len(path) - 1}",
                " -> ".join(path),
                f"status={dependent_node.status}",
                (
                    "other_blockers=-"
                    if not other_unsettled
                    else f"other_blockers={','.join(other_unsettled)}"
                ),
            )
        )
    print_summary("impact", graph, affected=len(records))
    emit_bounded(records, "impact")
    issues = graph.owned_issues_for_names(set(paths) | {node.name})
    emit_bounded([issue_row(issue) for issue in issues], "issues", AUDIT_LIMIT)
    return 1 if any(issue.severity == "ERROR" for issue in issues) else 0


def shortest_reverse_dependency_path(
    graph: Graph, source: str, target: str
) -> list[str] | None:
    queue: deque[list[str]] = deque([[source]])
    visited = {source}
    while queue:
        path = queue.popleft()
        current = path[-1]
        if current == target:
            return path
        for dependent in sorted(graph.hard_in.get(current, set())):
            if dependent not in visited:
                visited.add(dependent)
                queue.append(path + [dependent])
    return None


def shortest_dependency_path(
    graph: Graph, source: str, target: str
) -> list[str] | None:
    queue: deque[list[str]] = deque([[source]])
    visited = {source}
    while queue:
        path = queue.popleft()
        current = path[-1]
        if current == target:
            return path
        for prerequisite in sorted(graph.hard_out.get(current, set())):
            if prerequisite not in visited:
                visited.add(prerequisite)
                queue.append(path + [prerequisite])
    return None


def mode_path(graph: Graph, source_name: str, target_name: str) -> int:
    source = query_node(graph, source_name)
    if source is None:
        return 1
    target = query_node(graph, target_name)
    if target is None:
        return 1

    path = shortest_reverse_dependency_path(graph, source.name, target.name)
    if path is None:
        print(row("NO_PATH", source.name, target.name))
        print_summary("path", graph, paths=0)
        return 1

    issues = graph.blocking_errors_for_names(set(path))
    if any(issue.severity == "ERROR" for issue in issues):
        emit_bounded([issue_row(issue) for issue in issues], "issues", AUDIT_LIMIT)
        return 1

    print(row("PATH", source.name, target.name, f"hops={len(path) - 1}"))
    steps = [
        row(
            "STEP",
            index,
            project,
            "blocks" if index < len(path) - 1 else "destination",
        )
        for index, project in enumerate(path)
    ]
    emit_bounded(steps, "path_steps")
    print_summary("path", graph, paths=1)
    return 0


def mode_audit(graph: Graph) -> int:
    issues = graph.sorted_issues()
    print_summary(
        "audit",
        graph,
        clean=int(not issues),
    )
    emit_bounded([issue_row(issue) for issue in issues], "issues", AUDIT_LIMIT)
    return 1 if any(issue.severity == "ERROR" for issue in issues) else 0


def export_nodes(graph: Graph) -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    for node in sorted(
        graph.all_nodes,
        key=lambda item: (
            item.name,
            0 if item.registry == "active" else 1,
            item.registry_line,
        ),
    ):
        records.append(
            {
                "name": node.name,
                "path": node.project_path,
                "repo": node.repo,
                "status": node.status,
                "registry": node.registry,
                "section": node.section,
                "related": list(node.related),
                "location": node.location,
                "settled": node.settled,
                "tasks": asdict(node.tasks),
            }
        )
    return records


def export_edges(graph: Graph) -> list[dict[str, object]]:
    return [
        {
            "source": edge.source,
            "relation": edge.relation,
            "target": edge.target,
            "resolved_target": edge.resolved_target,
            "reason": edge.reason,
            "origin": edge.origin,
            "location": edge.location,
            "valid": edge.valid,
            "errors": list(edge.errors),
        }
        for edge in sorted(
            graph.edges,
            key=lambda item: (
                item.source,
                item.relation,
                item.target,
                item.origin,
                item.location,
            ),
        )
    ]


def mode_export(graph: Graph, output_format: str) -> int:
    nodes = export_nodes(graph)
    edges = export_edges(graph)
    issues = graph.sorted_issues()
    if output_format == "json":
        payload = {
            "schema_version": SCHEMA_VERSION,
            "summary": summary(graph),
            "nodes": nodes,
            "edges": edges,
            "issues": [asdict(issue) for issue in issues],
        }
        print(json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False))
    elif output_format == "tsv":
        print(export_row("SCHEMA", SCHEMA_VERSION))
        for node in nodes:
            tasks = node["tasks"]
            assert isinstance(tasks, dict)
            print(
                export_row(
                    "NODE",
                    node["name"],
                    node["registry"],
                    node["section"],
                    node["status"],
                    f"settled={str(node['settled']).lower()}",
                    f"tasks={tasks['done']}/{tasks['total']}",
                    f"open_revisions={tasks['open_revisions']}",
                    node["path"],
                    node["location"],
                )
            )
        for edge in edges:
            print(
                export_row(
                    "EDGE",
                    edge["source"],
                    edge["relation"],
                    edge["target"],
                    edge["origin"],
                    f"valid={str(edge['valid']).lower()}",
                    edge["reason"],
                    edge["location"],
                    ",".join(edge["errors"]) if edge["errors"] else "-",
                )
            )
        for issue in issues:
            print(issue_row(issue, bounded=False))
        print_summary("export", graph)
    else:
        print(row("ERROR", "INVALID_FORMAT", output_format, "expected tsv or json"))
        return 2
    return 1 if any(issue.severity == "ERROR" for issue in issues) else 0


def mode_can_link(
    graph: Graph, source_name: str, relation_arg: str, target_name: str
) -> int:
    relation = relation_arg.casefold()
    if relation not in ALLOWED_RELATIONS:
        print(
            row(
                "ERROR",
                "UNKNOWN_RELATION",
                source_name,
                target_name,
                f"relation={relation_arg}",
            )
        )
        return 1

    source, source_code, source_detail = graph.resolve(source_name)
    if source is None:
        print(
            row(
                "ERROR",
                source_code or "MISSING_PROJECT",
                source_name,
                target_name,
                source_detail,
            )
        )
        return 1
    target, target_code, target_detail = graph.resolve(target_name)
    if target is None:
        print(
            row(
                "ERROR",
                target_code or "MISSING_PROJECT",
                source_name,
                target_name,
                target_detail,
            )
        )
        return 1
    if source.registry != "active":
        print(
            row(
                "ERROR",
                "SOURCE_ARCHIVED",
                source.name,
                target.name,
                source.location,
            )
        )
        return 1
    if source.name == target.name:
        print(row("ERROR", "SELF_EDGE", source.name, target.name))
        return 1

    relevant = graph.blocking_errors_for_names({source.name, target.name})
    if relevant:
        issue = relevant[0]
        print(
            row(
                "ERROR",
                "GRAPH_INVALID",
                source.name,
                target.name,
                f"{issue.code}:{issue.detail}",
            )
        )
        return 1

    matches = [
        edge
        for edge in graph.edges
        if edge.origin == "canonical"
        and edge.source == source.name
        and edge.relation == relation
        and edge.target == target.name
    ]
    if len(matches) > 1:
        print(
            row(
                "ERROR",
                "DUPLICATE_CANONICAL_EDGE",
                source.name,
                target.name,
                ",".join(edge.location for edge in matches),
            )
        )
        return 1
    if len(matches) == 1:
        print(row("EXISTS", source.name, relation, target.name, matches[0].location))
        return 0

    if relation == "depends-on":
        path = shortest_dependency_path(graph, target.name, source.name)
        if path is not None:
            cycle = [source.name] + path
            print(
                row(
                    "ERROR",
                    "WOULD_CREATE_CYCLE",
                    source.name,
                    target.name,
                    " -> ".join(cycle),
                )
            )
            return 1

    print(row("OK", source.name, relation, target.name))
    return 0


def usage() -> None:
    print(
        "usage: graph-report.py "
        "{frontier|context|why|impact|path|audit|export|can-link} HUB [args]",
        file=sys.stderr,
    )


def main(argv: Sequence[str]) -> int:
    if len(argv) < 2:
        usage()
        return 2
    mode = argv[0]
    hub = argv[1]
    graph = compile_graph(hub)

    if mode == "frontier" and len(argv) == 2:
        return mode_frontier(graph)
    if mode == "context" and len(argv) == 3:
        return mode_context(graph, argv[2])
    if mode == "why" and len(argv) == 3:
        return mode_why(graph, argv[2])
    if mode == "impact" and len(argv) == 3:
        return mode_impact(graph, argv[2])
    if mode == "path" and len(argv) == 4:
        return mode_path(graph, argv[2], argv[3])
    if mode == "audit" and len(argv) == 2:
        return mode_audit(graph)
    if mode == "export" and len(argv) in {2, 3}:
        return mode_export(graph, argv[2] if len(argv) == 3 else "tsv")
    if mode == "can-link" and len(argv) == 5:
        return mode_can_link(graph, argv[2], argv[3], argv[4])

    usage()
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
