#!/usr/bin/env python3
"""Prüft master-webui.db vor der Auslieferung.

Die Master-DB geht an jede Installation und liegt in einem öffentlichen Repository.
Dieses Skript fängt die Fehler ab, die beim Neuaufbau tatsächlich passiert sind:
liegengebliebene Testdaten, fehlende Freigaben, Bildverarbeitung bei Modellen ohne
Bildfähigkeit, Platzhalter in Prompts, WAL-Modus, installationsspezifische Werte und
Abweichungen zwischen DB, models.sh/models.ps1 und MODELS.md.

    python3 scripts/check_master_db.py

Exit-Code 0 = alles in Ordnung, 1 = mindestens ein Fehler.
"""
import json
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "master-webui.db"
sys.path.insert(0, str(ROOT / "scripts"))
import gen_models_md  # noqa: E402

ADMIN_EMAIL = "info@kommunalgpt.de"
# Modellfamilien, die Bilder verarbeiten können (Ollama-Fähigkeit "vision")
VISION_PREFIXES = ("gemma3:", "gemma4:", "llava", "llama3.2-vision", "granite3.2-vision",
                   "qwen2.5vl", "qwen3-vl", "minicpm-v", "mistral-small3.1", "mistral-small3.2")
# Tabellen, die in der Auslieferung leer sein müssen
MUST_BE_EMPTY = ("chat", "chat_message", "file", "knowledge", "memory", "feedback", "note",
                 "document", "channel", "message", "api_key", "oauth_session", "folder")
SECRET_KEY = re.compile(r"(api_key|_key|password|secret|auth_token|client_secret)$")
PLACEHOLDER = re.compile(r"\[[A-ZÄÖÜ_]{3,}\]")

errors, notes = [], []


def fail(msg):
    errors.append(msg)


def main():
    if not DB.exists():
        print(f"FEHLER: {DB.name} nicht gefunden"); return 1
    for suffix in ("-wal", "-shm"):
        if (ROOT / f"master-webui.db{suffix}").exists():
            fail(f"master-webui.db{suffix} liegt neben der DB – Änderungen evtl. nicht eingearbeitet")
    if DB.read_bytes()[18:20] != b"\x01\x01":
        fail("DB ist im WAL-Modus gespeichert – vorher PRAGMA journal_mode=DELETE ausführen")

    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    q = lambda sql, *a: con.execute(sql, a).fetchall()
    tables = {r[0] for r in q("select name from sqlite_master where type='table'")}

    if q("PRAGMA integrity_check")[0][0] != "ok":
        fail("integrity_check meldet Beschädigung")

    # Nutzer und Testdaten
    users = q("select email, role from user")
    if users != [(ADMIN_EMAIL, "admin")]:
        fail(f"Erwartet genau einen Admin {ADMIN_EMAIL}, gefunden: {users}")
    for t in MUST_BE_EMPTY:
        if t in tables and (n := q(f'select count(*) from "{t}"')[0][0]):
            fail(f"Tabelle {t} enthält {n} Einträge (Testdaten?)")
    if "config_old" in tables:
        fail("Tabelle config_old (Alt-Konfiguration einer Migration) noch vorhanden")

    # Konfiguration
    config_cols = {r[1] for r in q("PRAGMA table_info(config)")}
    if "key" not in config_cols:
        fail("Konfiguration im alten Format – DB ist nicht auf die gepinnte Open-WebUI-Version migriert")
        return report()
    # Werte sind JSON; SQLite liefert Zahlen aber teils direkt als int/float
    cfg = {k: json.loads(v) if isinstance(v, str) else v for k, v in q("select key, value from config")}
    if "webui.url" in cfg:
        fail(f"webui.url steht in der DB ({cfg['webui.url']}) – gehört per WEBUI_URL ins Setup")
    for key, want in (("web.search.enable", False), ("openai.enable", False),
                      ("ui.enable_signup", False), ("ui.enable_community_sharing", False)):
        if cfg.get(key) != want:
            fail(f"{key} = {cfg.get(key)!r}, erwartet {want!r}")
    if cfg.get("ollama.base_urls") != ["http://host.docker.internal:11434"]:
        fail(f"ollama.base_urls = {cfg.get('ollama.base_urls')}")
    for key, val in cfg.items():
        if SECRET_KEY.search(key) and val not in ("", None, [], {}):
            fail(f"Möglicher Schlüssel/Passwort in der Konfiguration: {key}")

    # Assistenten
    assistants = q("select id, name, base_model_id, meta, params from model "
                   "where base_model_id is not null and base_model_id != ''")
    others = [r[0] for r in q("select id from model where base_model_id is null or base_model_id = ''")]
    unexpected = [mid for mid in others if "embed" not in mid]
    if unexpected:
        shown = ", ".join(unexpected[:5]) + (f" … (+{len(unexpected) - 5})" if len(unexpected) > 5 else "")
        fail(f"{len(unexpected)} unerwartete Basismodell-Einträge (nur ausgeblendete Embedding-Modelle "
             f"erlaubt): {shown}")
    granted = {r[0] for r in q("select resource_id from access_grant where resource_type='model' "
                               "and principal_type='user' and principal_id='*' and permission='read'")}
    for mid, name, base, meta, params in assistants:
        m, p = json.loads(meta), json.loads(params)
        if mid not in granted:
            fail(f"{name}: nicht für alle Nutzer freigegeben – normale Nutzer sehen ihn nicht")
        if (m.get("capabilities") or {}).get("vision") and not base.startswith(VISION_PREFIXES):
            fail(f"{name}: Bildverarbeitung aktiv, aber {base} kann keine Bilder")
        if not (m.get("description") or "").strip():
            fail(f"{name}: Beschreibung fehlt")
        if not str(m.get("profile_image_url", "")).startswith("data:image"):
            fail(f"{name}: kein Icon hinterlegt")
        system = (p.get("system") or "").strip()
        if not system:
            fail(f"{name}: Systemprompt fehlt")
        elif ph := PLACEHOLDER.findall(system):
            fail(f"{name}: Platzhalter im Systemprompt: {', '.join(ph)}")
    notes.append(f"{len(assistants)} Assistenten geprüft")

    # Modell-Listen der Setups
    needed = {r[2] for r in assistants} | {cfg.get("task.model.default"), cfg.get("rag.embedding_model")}
    needed.discard(None); needed.discard("")
    for f in ("models.sh", "models.ps1"):
        listed = set(re.findall(r'"([\w./-]+:[\w.-]+|[\w-]+/[\w.-]+)"\s*(?:#|,|$)',
                                (ROOT / f).read_text(encoding="utf-8"), re.M))
        if missing := sorted(needed - listed):
            fail(f"{f}: Modelle fehlen: {', '.join(missing)}")
        if extra := sorted(listed - needed):
            fail(f"{f}: Modelle werden geladen, aber nicht verwendet: {', '.join(extra)}")

    # MODELS.md aktuell?
    if (ROOT / "MODELS.md").read_text(encoding="utf-8") != gen_models_md.render()[0]:
        fail("MODELS.md passt nicht zur DB – python3 scripts/gen_models_md.py ausführen")

    # Open-WebUI-Version gepinnt?
    env = (ROOT / ".env.example").read_text(encoding="utf-8")
    tag = re.search(r"^WEBUI_TAG='?([^'\n]+)'?", env, re.M)
    if not tag or tag.group(1) in ("latest", "main"):
        fail("WEBUI_TAG in .env.example ist nicht auf eine feste Version gepinnt")
    else:
        notes.append(f"Open WebUI {tag.group(1)}, Migration {q('select version_num from alembic_version')[0][0]}")

    return report()


def report():
    for n in notes:
        print(f"  ✓ {n}")
    if errors:
        print(f"\n{len(errors)} Problem(e) in master-webui.db:")
        for e in errors:
            print(f"  ✗ {e}")
        return 1
    print("\nmaster-webui.db ist auslieferbar.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
