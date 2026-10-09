#!/usr/bin/env python3
"""Erzeugt MODELS.md aus master-webui.db.

Die Assistenten werden in Open WebUI gepflegt und als master-webui.db ausgeliefert.
Damit die Dokumentation nicht wieder vom ausgelieferten Stand abweicht, wird MODELS.md
nicht von Hand geschrieben, sondern aus der Datenbank erzeugt:

    python3 scripts/gen_models_md.py
"""
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "master-webui.db"
OUT = ROOT / "MODELS.md"

# Reihenfolge wie auf dem Dashboard
ORDER = [
    "chatbot", "textzusammenfassung", "textueberprfung", "uebersetzung",
    "code-unterstuetzung", "brainstorming-hilfe", "recherche",
    "niederschrift-assistent", "schreib-assistent", "bildbeschreiber",
    "dateninterpretation", "social-media-texter",
]


def render():
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    rows = {
        r[0]: r for r in con.execute(
            "select id, name, base_model_id, meta, params from model "
            "where base_model_id is not null and base_model_id != ''")
    }
    cfg = dict(con.execute(
        "select key, value from config where key in "
        "('task.model.default', 'rag.embedding_model')").fetchall())
    # Stand = letzte Aenderung an einem Assistenten. Damit ist die Ausgabe reproduzierbar und
    # die CI kann pruefen, ob MODELS.md zur DB passt (heutiges Datum wuerde jeden Tag abweichen).
    stand = datetime.fromtimestamp(con.execute(
        "select max(updated_at) from model where base_model_id != ''").fetchone()[0], timezone.utc)
    task_model = json.loads(cfg.get("task.model.default", '""'))
    embed_model = json.loads(cfg.get("rag.embedding_model", '""'))

    ids = [i for i in ORDER if i in rows] + sorted(i for i in rows if i not in ORDER)
    out = []
    out.append("# MODELLE IN KommunalGPT powered by compAInion\n")
    out.append(f"*Stand: {stand:%d.%m.%Y} – erzeugt aus `master-webui.db` "
               "mit `scripts/gen_models_md.py`. Bitte nicht von Hand bearbeiten.*\n")
    out.append("Die Assistenten, ihre Beschreibungen und Systemprompts wurden von der "
               "deepmentation UG (haftungsbeschränkt) entwickelt. Siehe [NOTICE](NOTICE).\n")
    out.append("## Übersicht\n")
    out.append("| Assistent | Basismodell | Bilder |")
    out.append("|---|---|---|")
    for i in ids:
        _, name, base, meta, _ = rows[i]
        vision = (json.loads(meta).get("capabilities") or {}).get("vision")
        out.append(f"| {name} | `{base}` | {'ja' if vision else '–'} |")
    out.append("")
    out.append("Weitere Modelle:\n")
    out.append(f"- **Chat-Titel und Autovervollständigung:** `{task_model}`")
    out.append(f"- **Dokumente und Wissensdatenbanken (Embedding):** `{embed_model}`\n")
    bases = sorted({rows[i][2] for i in ids} | {task_model, embed_model} - {""})
    out.append("Benötigte Modelle insgesamt (werden von `models.sh` / `models.ps1` geladen): "
               + ", ".join(f"`{b}`" for b in bases) + "\n")
    out.append("Die Zuordnung ist auf die kleinste Ausbaustufe (16 GB Grafikspeicher) ausgelegt. "
               "Auf größerer Hardware können die Basismodelle in Open WebUI unter "
               "*Arbeitsbereich › Modelle* umgestellt werden.\n")

    for i in ids:
        _, name, base, meta, params = rows[i]
        m, p = json.loads(meta), json.loads(params)
        out.append("---\n")
        out.append(f"## {name}\n")
        out.append(f"**Basismodell:** `{base}`\n")
        if (m.get("description") or "").strip():
            out.append(f"**Beschreibung:** {m['description'].strip()}\n")
        system = (p.get("system") or "").strip()
        if system:
            out.append("**Systemprompt:**\n")
            out.append("```text\n" + system + "\n```\n")
    return "\n".join(out), ids, bases


def main():
    text, ids, bases = render()
    OUT.write_text(text, encoding="utf-8")
    print(f"{OUT.name} geschrieben: {len(ids)} Assistenten, Modelle: {', '.join(bases)}")


if __name__ == "__main__":
    main()
