from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from graphify.analyze import god_nodes, suggest_questions, surprising_connections
from graphify.build import build
from graphify.cluster import cluster, score_all
from graphify.detect import detect
from graphify.export import to_json
from graphify.extract import collect_files, extract
from graphify.report import generate


def main() -> None:
    parser = argparse.ArgumentParser(prog="droidcodegraph")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("build", "update"):
        command = sub.add_parser(name)
        command.add_argument("--project", required=True)
        command.add_argument("--out", required=True)
    query = sub.add_parser("query")
    query.add_argument("--graph", required=True)
    query.add_argument("--text", required=True)
    args = parser.parse_args()
    if args.command in ("build", "update"):
        run_build(Path(args.project).resolve(), Path(args.out).resolve(), args.command)
    else:
        run_query(Path(args.graph).resolve(), args.text)


def run_build(project: Path, out: Path, mode: str) -> None:
    out.mkdir(parents=True, exist_ok=True)
    detection = detect(project)
    code_files = [Path(path) for path in detection["files"].get("code", [])]
    ast = extract(code_files, cache_root=project) if code_files else empty_result()
    graph = build([ast], dedup=True)
    if graph.number_of_nodes() == 0:
        write_status(out, mode, False, 0, 0, 0, "No graphable code files found")
        return
    communities = cluster(graph)
    cohesion = score_all(graph, communities)
    labels = {cid: f"Community {cid}" for cid in communities}
    gods = safe(lambda: god_nodes(graph), [])
    surprises = safe(lambda: surprising_connections(graph, communities), [])
    questions = safe(lambda: suggest_questions(graph, communities, labels), [])
    tokens = {
        "input": ast.get("input_tokens", 0),
        "output": ast.get("output_tokens", 0),
    }
    report = generate(
        graph,
        communities,
        cohesion,
        labels,
        gods,
        surprises,
        detection,
        tokens,
        str(project),
        suggested_questions=questions,
    )
    report_path = out / "GRAPH_REPORT.md"
    graph_path = out / "graph.json"
    droid_path = out / "droid-graph.json"
    report_path.write_text(report, encoding="utf-8")
    to_json(graph, communities, str(graph_path), force=True)
    graph_json = json.loads(graph_path.read_text(encoding="utf-8"))
    droid_path.write_text(
        json.dumps(to_droid_graph(project, graph_json, communities, labels), indent=2),
        encoding="utf-8",
    )
    analysis = {
        "communities": {str(key): value for key, value in communities.items()},
        "cohesion": {str(key): value for key, value in cohesion.items()},
        "gods": gods,
        "surprises": surprises,
        "questions": questions,
        "tokens": tokens,
    }
    (out / "analysis.json").write_text(json.dumps(analysis, indent=2), encoding="utf-8")
    (out / "manifest.json").write_text(json.dumps(detection, indent=2), encoding="utf-8")
    write_status(
        out,
        mode,
        True,
        graph.number_of_nodes(),
        graph.number_of_edges(),
        len(communities),
        None,
    )


def to_droid_graph(project: Path, graph_json: dict, communities: dict, labels: dict) -> dict:
    degree = {}
    for link in graph_json.get("links", []):
        degree[link.get("source")] = degree.get(link.get("source"), 0) + 1
        degree[link.get("target")] = degree.get(link.get("target"), 0) + 1
    nodes = []
    for node in graph_json.get("nodes", []):
        nodes.append({
            "id": node.get("id"),
            "label": node.get("label") or node.get("id"),
            "file_type": node.get("file_type", "unknown"),
            "source_file": node.get("source_file"),
            "community": node.get("community"),
            "degree": degree.get(node.get("id"), 0),
        })
    edges = []
    for link in graph_json.get("links", []):
        edges.append({
            "source": link.get("source"),
            "target": link.get("target"),
            "relation": link.get("relation", "related_to"),
            "confidence": link.get("confidence", "EXTRACTED"),
        })
    community_list = [
        {"id": cid, "label": labels.get(cid, f"Community {cid}"), "node_count": len(members)}
        for cid, members in sorted(communities.items())
    ]
    return {
        "projectPath": str(project),
        "builtAt": datetime.now(timezone.utc).isoformat(),
        "nodes": nodes,
        "edges": edges,
        "communities": community_list,
    }


def write_status(out: Path, mode: str, ok: bool, nodes: int, edges: int, communities: int, message: str | None) -> None:
    status = {
        "ok": ok,
        "mode": mode,
        "nodes": nodes,
        "edges": edges,
        "communities": communities,
        "graphPath": str(out / "graph.json"),
        "droidGraphPath": str(out / "droid-graph.json"),
        "reportPath": str(out / "GRAPH_REPORT.md"),
        "message": message,
    }
    (out / "status.json").write_text(json.dumps(status, indent=2), encoding="utf-8")


def run_query(graph_path: Path, text: str) -> None:
    from graphify.serve import _query_graph_text
    from networkx.readwrite import json_graph

    raw = json.loads(graph_path.read_text(encoding="utf-8"))
    graph = json_graph.node_link_graph(raw, edges="links")
    print(_query_graph_text(graph, text, mode="bfs", depth=2, token_budget=2000))


def empty_result() -> dict:
    return {"nodes": [], "edges": [], "hyperedges": [], "input_tokens": 0, "output_tokens": 0}


def safe(callable_value, default):
    try:
        return callable_value()
    except Exception:
        return default


if __name__ == "__main__":
    main()
