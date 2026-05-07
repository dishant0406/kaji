from __future__ import annotations

import argparse
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(prog="droidcodegraph")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("build", "update"):
        command = sub.add_parser(name)
        command.add_argument("--project", required=True)
        command.add_argument("--out", required=True)
    finalize = sub.add_parser("finalize")
    finalize.add_argument("--project", required=True)
    finalize.add_argument("--out", required=True)
    finalize.add_argument("--work", required=True)
    finalize.add_argument("--mode", required=True)
    finalize.add_argument("--build-id", required=True)
    query = sub.add_parser("query")
    query.add_argument("--graph", required=True)
    query.add_argument("--text", required=True)
    args = parser.parse_args()
    if args.command in ("build", "update"):
        run_legacy(Path(args.out).resolve(), args.command)
    elif args.command == "finalize":
        run_finalize(
            project=Path(args.project).resolve(),
            out=Path(args.out).resolve(),
            work=Path(args.work).resolve(),
            mode=args.mode,
            build_id=args.build_id,
        )
    else:
        run_query(Path(args.graph).resolve(), args.text)


def run_legacy(out: Path, mode: str) -> None:
    out.mkdir(parents=True, exist_ok=True)
    write_status(out, mode, False, 0, 0, 0, "legacy", "failed", "DroidCodeGraph now requires the Droid Parent Agent.")


def run_finalize(project: Path, out: Path, work: Path, mode: str, build_id: str) -> None:
    out.mkdir(parents=True, exist_ok=True)
    graph_dir = work / "graphify-out"
    if not (graph_dir / "graph.json").exists():
        write_status(out, mode, False, 0, 0, 0, build_id, "failed", "Graphify did not produce graphify-out/graph.json.")
        return
    copy_outputs(work, graph_dir, out)
    graph_path = out / "graph.json"
    graph_json = json.loads(graph_path.read_text(encoding="utf-8"))
    labels = read_labels(out)
    analysis = read_json(out / ".graphify_analysis.json", {})
    communities = read_communities(graph_json, analysis)
    droid_graph = to_droid_graph(project, graph_json, communities, labels)
    (out / "droid-graph.json").write_text(json.dumps(droid_graph, indent=2), encoding="utf-8")
    write_public_json(out / "analysis.json", analysis)
    write_public_json(out / "manifest.json", read_json(out / ".graphify_detect.json", {}))
    write_status(
        out,
        mode,
        True,
        len(droid_graph["nodes"]),
        len(droid_graph["edges"]),
        len(droid_graph["communities"]),
        build_id,
        "complete",
        None,
    )


def copy_outputs(work: Path, graph_dir: Path, out: Path) -> None:
    for name in ("graph.json", "GRAPH_REPORT.md", "graph.html", "cost.json"):
        copy_file(graph_dir / name, out / name)
    for name in (
        ".graphify_detect.json",
        ".graphify_extract.json",
        ".graphify_analysis.json",
        ".graphify_labels.json",
        ".graphify_semantic.json",
        ".graphify_ast.json",
    ):
        copy_file(work / name, out / name)
        copy_file(graph_dir / name, out / name)


def copy_file(source: Path, destination: Path) -> None:
    if source.exists():
        shutil.copy2(source, destination)


def read_json(path: Path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def read_labels(out: Path) -> dict[int, str]:
    raw = read_json(out / ".graphify_labels.json", {})
    labels = {}
    for key, value in raw.items():
        try:
            labels[int(key)] = str(value)
        except Exception:
            continue
    return labels


def read_communities(graph_json: dict, analysis: dict) -> dict[int, list[str]]:
    raw = analysis.get("communities", {})
    if raw:
        return {int(key): list(value) for key, value in raw.items()}
    result: dict[int, list[str]] = {}
    for node in graph_json.get("nodes", []):
        community = node.get("community")
        if community is None:
            community = 0
        result.setdefault(int(community), []).append(node.get("id"))
    return result


def to_droid_graph(project: Path, graph_json: dict, communities: dict[int, list[str]], labels: dict[int, str]) -> dict:
    degree = {}
    for link in graph_json.get("links", []):
        degree[link.get("source")] = degree.get(link.get("source"), 0) + 1
        degree[link.get("target")] = degree.get(link.get("target"), 0) + 1
    nodes = [droid_node(node, degree) for node in graph_json.get("nodes", [])]
    edges = [{
        "source": link.get("source"),
        "target": link.get("target"),
        "relation": link.get("relation", "related_to"),
        "confidence": link.get("confidence", "EXTRACTED"),
    } for link in graph_json.get("links", [])]
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


def droid_node(node: dict, degree: dict) -> dict:
    community = node.get("community")
    if community is None:
        community = 0
    return {
        "id": node.get("id"),
        "label": node.get("label") or node.get("id"),
        "file_type": node.get("file_type") or node.get("type") or "unknown",
        "source_file": node.get("source_file"),
        "community": int(community),
        "degree": degree.get(node.get("id"), 0),
    }


def write_public_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2), encoding="utf-8")


def write_status(out: Path, mode: str, ok: bool, nodes: int, edges: int, communities: int, build_id: str, state: str, message: str | None) -> None:
    status = {
        "ok": ok,
        "mode": mode,
        "nodes": nodes,
        "edges": edges,
        "communities": communities,
        "graphPath": str(out / "graph.json"),
        "droidGraphPath": str(out / "droid-graph.json"),
        "reportPath": str(out / "GRAPH_REPORT.md"),
        "buildID": build_id,
        "state": state,
        "message": message,
    }
    (out / "status.json").write_text(json.dumps(status, indent=2), encoding="utf-8")


def run_query(graph_path: Path, text: str) -> None:
    from graphify.serve import _query_graph_text
    from networkx.readwrite import json_graph

    raw = json.loads(graph_path.read_text(encoding="utf-8"))
    graph = json_graph.node_link_graph(raw, edges="links")
    print(_query_graph_text(graph, text, mode="bfs", depth=2, token_budget=2000))


if __name__ == "__main__":
    main()
