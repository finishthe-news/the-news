#!/usr/bin/env python3
import argparse
import hashlib
import html
import json
import re
import unicodedata
from collections import Counter, defaultdict
from datetime import UTC, datetime
from pathlib import Path

import numpy as np
import onnxruntime as ort
from sklearn.cluster import AgglomerativeClustering
from tokenizers import Tokenizer

ROOT = Path(__file__).resolve().parents[2]
MODEL_REVISION = "5c38ec7c405ec4b44b94cc5a9bb96e735b38267a"
MODEL_ROOT = ROOT / "storage/models/embeddings/BAAI/bge-small-en-v1.5" / MODEL_REVISION
MODEL_PATH = MODEL_ROOT / "onnx/model.onnx"
TOKENIZER_PATH = MODEL_ROOT / "tokenizer.json"
MODEL_SHA256 = "828e1496d7fabb79cfa4dcd84fa38625c0d3d21da474a00f08db0f559940cf35"
THRESHOLDS = (0.145, 0.20)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("dataset", type=Path)
    parser.add_argument("output_root", type=Path)
    parser.add_argument("--batch-size", type=int, default=32)
    return parser.parse_args()


def normalized_text(article):
    title = unicodedata.normalize("NFKC", article["title"])
    body = unicodedata.normalize("NFKC", article["body_text"])
    title = re.sub(r"\s+", " ", title).strip()
    body_words = re.sub(r"\s+", " ", body).strip().split()[:350]
    return f"{title}\n\n{' '.join(body_words)}"


def verify_model():
    actual = hashlib.sha256(MODEL_PATH.read_bytes()).hexdigest()
    if actual != MODEL_SHA256:
        raise RuntimeError(f"model checksum mismatch: {actual}")


def embed(texts, batch_size=32):
    verify_model()
    tokenizer = Tokenizer.from_file(str(TOKENIZER_PATH))
    tokenizer.enable_truncation(max_length=512)
    tokenizer.enable_padding()
    session = ort.InferenceSession(str(MODEL_PATH), providers=["CPUExecutionProvider"])
    input_names = {item.name for item in session.get_inputs()}
    vectors = []
    for start in range(0, len(texts), batch_size):
        encodings = tokenizer.encode_batch(texts[start : start + batch_size])
        inputs = {
            "input_ids": np.asarray([item.ids for item in encodings], dtype=np.int64),
            "attention_mask": np.asarray([item.attention_mask for item in encodings], dtype=np.int64),
        }
        if "token_type_ids" in input_names:
            inputs["token_type_ids"] = np.asarray(
                [item.type_ids for item in encodings], dtype=np.int64
            )
        hidden = session.run(None, inputs)[0]
        cls_vectors = hidden[:, 0, :]
        norms = np.linalg.norm(cls_vectors, axis=1, keepdims=True)
        vectors.append(cls_vectors / np.maximum(norms, 1e-12))
    return np.vstack(vectors)


def cluster_labels(vectors, threshold):
    return AgglomerativeClustering(
        n_clusters=None,
        distance_threshold=threshold,
        linkage="average",
        metric="cosine",
    ).fit_predict(vectors)


def cluster_result(articles, vectors, threshold):
    similarities = vectors @ vectors.T
    labels = cluster_labels(vectors, threshold)
    groups = defaultdict(list)
    for index, label in enumerate(labels):
        groups[int(label)].append(index)
    clusters = []
    for indexes in groups.values():
        if len(indexes) < 2:
            continue
        pairwise = [
            {
                "left": articles[left]["title"],
                "left_source": articles[left]["source_name"],
                "right": articles[right]["title"],
                "right_source": articles[right]["source_name"],
                "similarity": float(similarities[left, right]),
            }
            for offset, left in enumerate(indexes)
            for right in indexes[offset + 1 :]
        ]
        pair_scores = [pair["similarity"] for pair in pairwise]
        outside = [index for index in range(len(articles)) if index not in indexes]
        nearest_outside = None
        if outside:
            best_inside, best_outside = max(
                ((inside, other) for inside in indexes for other in outside),
                key=lambda pair: similarities[pair[0], pair[1]],
            )
            nearest_outside = {
                "similarity": float(similarities[best_inside, best_outside]),
                "inside_title": articles[best_inside]["title"],
                "outside_title": articles[best_outside]["title"],
                "outside_source": articles[best_outside]["source_name"],
            }
        clusters.append(
            {
                "size": len(indexes),
                "source_count": len({articles[index]["source_slug"] for index in indexes}),
                "sources": sorted({articles[index]["source_name"] for index in indexes}),
                "average_similarity": float(np.mean(pair_scores)),
                "minimum_similarity": float(np.min(pair_scores)),
                "maximum_similarity": float(np.max(pair_scores)),
                "pairwise_similarities": sorted(pairwise, key=lambda pair: pair["similarity"]),
                "nearest_outside": nearest_outside,
                "articles": [
                    {
                        "title": articles[index]["title"],
                        "source": articles[index]["source_name"],
                        "published_at": articles[index]["published_at"],
                        "canonical_url": articles[index]["canonical_url"],
                        "excerpt": " ".join(articles[index]["body_text"].split()[:55]),
                        "content_hash": articles[index]["content_hash"],
                    }
                    for index in indexes
                ],
            }
        )
    clusters.sort(
        key=lambda cluster: (
            -cluster["source_count"],
            -cluster["size"],
            -cluster["average_similarity"],
            cluster["articles"][0]["title"],
        )
    )
    grouped_articles = sum(cluster["size"] for cluster in clusters)
    return {
        "distance_threshold": threshold,
        "equivalent_pair_similarity": 1 - threshold,
        "cluster_count": len(clusters),
        "grouped_articles": grouped_articles,
        "singleton_count": len(articles) - grouped_articles,
        "multi_source_clusters": sum(cluster["source_count"] > 1 for cluster in clusters),
        "clusters": clusters,
    }


def render_html(result):
    summary_cards = "".join(
        f"""<article><h2>Distance {run['distance_threshold']:.3f}</h2>
        <p><strong>{run['cluster_count']}</strong> clusters · <strong>{run['grouped_articles']}</strong>
        grouped articles · <strong>{run['multi_source_clusters']}</strong> multi-source clusters ·
        <strong>{run['singleton_count']}</strong> singletons</p></article>"""
        for run in result["runs"]
    )
    sections = []
    for run in result["runs"]:
        cards = []
        for number, cluster in enumerate(run["clusters"], 1):
            articles = "".join(
                f"""<li><p><span class="source">{html.escape(article['source'])}</span>
                <a href="{html.escape(article['canonical_url'])}">{html.escape(article['title'])}</a></p>
                <p class="meta">{html.escape(article['published_at'] or 'publication date unknown')}</p>
                <p>{html.escape(article['excerpt'])}</p></li>"""
                for article in cluster["articles"]
            )
            outside = cluster["nearest_outside"]
            outside_html = ""
            if outside:
                outside_html = (
                    f"<p class='near'><strong>Nearest excluded:</strong> {outside['similarity']:.3f} — "
                    f"{html.escape(outside['outside_source'])}: {html.escape(outside['outside_title'])}</p>"
                )
            pairs = "".join(
                f"<tr><td>{pair['similarity']:.3f}</td><td>{html.escape(pair['left_source'])}: "
                f"{html.escape(pair['left'])}</td><td>{html.escape(pair['right_source'])}: "
                f"{html.escape(pair['right'])}</td></tr>"
                for pair in cluster["pairwise_similarities"]
            )
            pairs_html = (
                "<details><summary>Pairwise similarities</summary><div class='table-wrap'><table>"
                f"<thead><tr><th>Score</th><th>Article A</th><th>Article B</th></tr></thead><tbody>{pairs}</tbody>"
                "</table></div></details>"
            )
            cards.append(
                f"""<article class="cluster"><h3>Cluster {number} · {cluster['size']} articles ·
                {cluster['source_count']} sources</h3><p class="metrics">Similarity: average
                {cluster['average_similarity']:.3f}, minimum {cluster['minimum_similarity']:.3f},
                maximum {cluster['maximum_similarity']:.3f}</p><ul>{articles}</ul>{pairs_html}{outside_html}</article>"""
            )
        sections.append(
            f"<section><h2>Average linkage at distance {run['distance_threshold']:.3f}</h2>{''.join(cards)}</section>"
        )
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1"><title>The News clustering experiment</title>
    <style>
    :root{{--ink:#17211b;--muted:#667269;--paper:#f4f1e8;--card:#fffdf7;--line:#d7d2c4;--accent:#8c2f24}}
    *{{box-sizing:border-box}} body{{margin:0;background:var(--paper);color:var(--ink);font:16px/1.55 Georgia,serif}}
    main{{max-width:1100px;margin:auto;padding:48px 24px}} h1{{font-size:clamp(2.2rem,5vw,4.5rem);line-height:1;margin:.2em 0}}
    .dek,.meta,.metrics,.near{{color:var(--muted)}} .summary{{display:grid;grid-template-columns:repeat(2,1fr);gap:16px;margin:32px 0}}
    .summary article,.cluster{{background:var(--card);border:1px solid var(--line);padding:22px;margin:18px 0}}
    section>h2{{border-bottom:3px solid var(--ink);padding-bottom:8px;margin-top:56px}} ul{{list-style:none;padding:0}}
    li{{border-top:1px solid var(--line);padding:14px 0}} li:first-child{{border-top:0}} li p{{margin:.35em 0}}
    a{{color:var(--accent)}} .source{{display:inline-block;font:700 .72rem system-ui,sans-serif;letter-spacing:.08em;text-transform:uppercase;margin-right:8px}}
    .meta,.metrics,.near,summary,table{{font:13px/1.45 system-ui,sans-serif}} summary{{cursor:pointer;font-weight:700}}
    .table-wrap{{overflow:auto}} table{{border-collapse:collapse;width:100%;margin:12px 0}} th,td{{border:1px solid var(--line);padding:7px;text-align:left;vertical-align:top}}
    @media(max-width:700px){{.summary{{grid-template-columns:1fr}}}}
    </style></head><body><main><p class="source">The News · HITL benchmark</p><h1>Clustering proposals</h1>
    <p class="dek">Frozen dataset: {html.escape(result['dataset_id'])}. These are unaccepted review proposals,
    not newsroom evidence packets.</p><div class="summary">{summary_cards}</div>{''.join(sections)}</main></body></html>"""


def main():
    args = parse_args()
    articles = [json.loads(line) for line in args.dataset.open()]
    texts = [normalized_text(article) for article in articles]
    vectors = embed(texts, args.batch_size)
    run_id = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    output = args.output_root / run_id
    output.mkdir(parents=True, exist_ok=False)
    np.save(output / "embeddings.npy", vectors)
    result = {
        "experiment": "bge-small-average-linkage-v1",
        "run_id": run_id,
        "dataset_id": args.dataset.parent.name,
        "dataset_sha256": hashlib.sha256(args.dataset.read_bytes()).hexdigest(),
        "model": "BAAI/bge-small-en-v1.5",
        "model_revision": MODEL_REVISION,
        "model_sha256": MODEL_SHA256,
        "text_contract": "complete title plus first 350 normalized body words; 512-token model limit",
        "linkage": "average",
        "metric": "cosine",
        "article_count": len(articles),
        "exact_cross_url_content_groups": sum(
            count > 1 for count in Counter(article["content_hash"] for article in articles).values()
        ),
        "runs": [cluster_result(articles, vectors, threshold) for threshold in THRESHOLDS],
    }
    (output / "result.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    (output / "report.html").write_text(render_html(result))
    print(json.dumps({
        "output": str(output),
        "article_count": len(articles),
        "runs": [{key: run[key] for key in ("distance_threshold", "cluster_count", "grouped_articles", "multi_source_clusters", "singleton_count")} for run in result["runs"]],
    }, indent=2))


if __name__ == "__main__":
    main()
