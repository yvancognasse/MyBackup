import os
import sys
import json
import mimetypes
import traceback
import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from datetime import datetime

import httplib2
import google_auth_httplib2
from google.auth.transport.requests import Request
from google_auth_oauthlib.flow import InstalledAppFlow
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

os.umask(0o077)
httplib2.REDIRECT_CODES = frozenset(c for c in httplib2.REDIRECT_CODES if c != 308)

SCOPES = ["https://www.googleapis.com/auth/drive"]
HOME = Path(os.environ.get("MYBACKUP_HOME", Path.cwd())).resolve()
ENV_FILE = HOME / "MyBackup.env"
LOG_FILE = HOME / "MyBackup.log"
CACHE_FILE = HOME / "MyBackup.cache.json"
TOKEN_FILE = HOME / "token.json"
CREDENTIALS_FILE = HOME / "credentials.json"
CRASH_FILE = HOME / "crash.log"

_thread_local = threading.local()
_folder_lock_global = threading.Lock()
_folder_locks = {}
_cache_lock = threading.Lock()
_stats_lock = threading.Lock()


def emit(event, **kwargs):
    payload = {"event": event, **kwargs}
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def write_log(message):
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(f"{datetime.now():%Y-%m-%d %H:%M:%S} {message}\n")


def parse_bool(value, default=False):
    if value is None:
        return default
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def load_env():
    cfg = {}
    if ENV_FILE.exists():
        for raw in ENV_FILE.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            cfg[k.strip()] = v.strip()
    for key in (
        "SOURCE_DIRS",
        "DRIVE_FOLDER_NAME",
        "DRIVE_PARENT_ID",
        "SKIP_HIDDEN",
        "MAX_WORKERS",
        "UPLOAD_CHUNK_MB",
        "SMALL_FILE_LIMIT_MB",
        "MAX_RETRIES",
        "RETRY_DELAY_SECONDS",
        "HTTP_TIMEOUT_SECONDS",
        "CACHE_SAVE_EVERY",
    ):
        if os.environ.get(key):
            cfg[key] = os.environ[key]
    raw_sources = cfg.get("SOURCE_DIRS", "")
    sep = "|" if "|" in raw_sources else ","
    sources = [Path(s.strip()).expanduser() for s in raw_sources.split(sep) if s.strip()]
    if not sources:
        raise ValueError("SOURCE_DIRS is empty. Open MyBackup > Setup and choose at least one source folder.")
    cfg["SOURCE_DIRS"] = sources
    cfg["DRIVE_FOLDER_NAME"] = cfg.get("DRIVE_FOLDER_NAME", "MyBackup")
    cfg["DRIVE_PARENT_ID"] = cfg.get("DRIVE_PARENT_ID") or None
    cfg["SKIP_HIDDEN"] = parse_bool(cfg.get("SKIP_HIDDEN", "true"), True)
    cfg["MAX_WORKERS"] = int(cfg.get("MAX_WORKERS", "8"))
    cfg["UPLOAD_CHUNK_SIZE"] = int(float(cfg.get("UPLOAD_CHUNK_MB", "32")) * 1024 * 1024)
    cfg["SMALL_FILE_LIMIT"] = int(float(cfg.get("SMALL_FILE_LIMIT_MB", "20")) * 1024 * 1024)
    cfg["MAX_RETRIES"] = int(cfg.get("MAX_RETRIES", "4"))
    cfg["RETRY_DELAY_SECONDS"] = int(cfg.get("RETRY_DELAY_SECONDS", "5"))
    cfg["HTTP_TIMEOUT_SECONDS"] = int(cfg.get("HTTP_TIMEOUT_SECONDS", "300"))
    cfg["CACHE_SAVE_EVERY"] = int(cfg.get("CACHE_SAVE_EVERY", "500"))
    for key in ("MAX_WORKERS", "UPLOAD_CHUNK_SIZE", "MAX_RETRIES", "HTTP_TIMEOUT_SECONDS", "CACHE_SAVE_EVERY"):
        if cfg[key] <= 0:
            raise ValueError(f"{key} must be greater than zero")
    return cfg


def load_cache(destination=None):
    if CACHE_FILE.exists():
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                cache = json.load(f)
            if isinstance(cache, dict):
                if cache.get("version") == 2 and isinstance(cache.get("files"), dict):
                    if destination is None or cache.get("destination") == destination:
                        return cache["files"]
                    return {}
                # Legacy entries do not identify their Drive destination.
                if destination is None:
                    return cache
                return {}
        except Exception:
            pass
        write_log("WARNING cache is unreadable; starting with an empty cache")
    return {}


def atomic_write_json(path, value):
    tmp = path.with_name(path.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(value, f, ensure_ascii=False, separators=(",", ":"))
            f.flush()
            os.fsync(f.fileno())
        tmp.replace(path)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise


def save_cache(cache, destination=None):
    with _cache_lock:
        snapshot = dict(cache)
    if destination is not None:
        snapshot = {"version": 2, "destination": destination, "files": snapshot}
    atomic_write_json(CACHE_FILE, snapshot)


def authenticate():
    creds = None
    if TOKEN_FILE.exists():
        creds = Credentials.from_authorized_user_file(str(TOKEN_FILE), SCOPES)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            try:
                creds.refresh(Request())
            except Exception:
                TOKEN_FILE.unlink(missing_ok=True)
                creds = None
        if not creds:
            if not CREDENTIALS_FILE.exists():
                raise FileNotFoundError(f"credentials.json manquant : {CREDENTIALS_FILE}")
            flow = InstalledAppFlow.from_client_secrets_file(str(CREDENTIALS_FILE), SCOPES)
            creds = flow.run_local_server(port=0)
        atomic_write_json(TOKEN_FILE, json.loads(creds.to_json()))
    return creds


def build_service(creds, timeout):
    http = httplib2.Http(timeout=timeout)
    authed_http = google_auth_httplib2.AuthorizedHttp(creds, http=http)
    return build("drive", "v3", http=authed_http, cache_discovery=False)


def get_service(creds, timeout):
    svc = getattr(_thread_local, "service", None)
    if svc is None:
        svc = build_service(creds, timeout)
        _thread_local.service = svc
    return svc


def folder_lock(key):
    with _folder_lock_global:
        if key not in _folder_locks:
            _folder_locks[key] = threading.Lock()
        return _folder_locks[key]


def get_or_create_folder(service, name, parent_id=None):
    effective_parent = parent_id or "root"
    key = f"{effective_parent}::{name}"
    with folder_lock(key):
        safe_name = name.replace("\\", "\\\\").replace("'", "\\'")
        query = (
            f"name='{safe_name}' and mimeType='application/vnd.google-apps.folder' "
            f"and trashed=false and '{effective_parent}' in parents"
        )
        results = service.files().list(q=query, fields="files(id,name)", pageSize=10).execute()
        files = results.get("files", [])
        if files:
            return files[0]["id"], False
        meta = {"name": name, "mimeType": "application/vnd.google-apps.folder", "parents": [effective_parent]}
        return service.files().create(body=meta, fields="id").execute()["id"], True


def list_folder(service, folder_id):
    out = {}
    page_token = None
    while True:
        kwargs = {
            "q": f"'{folder_id}' in parents and trashed=false",
            "fields": "nextPageToken, files(id,name,size,modifiedTime,mimeType)",
            "pageSize": 1000,
        }
        if page_token:
            kwargs["pageToken"] = page_token
        resp = service.files().list(**kwargs).execute()
        for item in resp.get("files", []):
            out[item["name"]] = item
        page_token = resp.get("nextPageToken")
        if not page_token:
            return out


def signature(path):
    st = path.stat()
    return {"size": st.st_size, "mtime_ns": st.st_mtime_ns,
            "ctime_ns": st.st_ctime_ns, "inode": st.st_ino, "device": st.st_dev}


def unchanged(path, cache):
    try:
        with _cache_lock:
            cached = cache.get(str(path))
        return cached == signature(path)
    except OSError:
        return False


def upload_file(service, path, folder_id, drive_item, cfg):
    mime_type, _ = mimetypes.guess_type(str(path))
    mime_type = mime_type or "application/octet-stream"
    last_exc = None
    for attempt in range(1, cfg["MAX_RETRIES"] + 1):
        try:
            media = MediaFileUpload(
                str(path),
                mimetype=mime_type,
                resumable=path.stat().st_size >= cfg["SMALL_FILE_LIMIT"],
                chunksize=cfg["UPLOAD_CHUNK_SIZE"],
            )
            if drive_item:
                service.files().update(fileId=drive_item["id"], media_body=media).execute()
                return "updated"
            service.files().create(body={"name": path.name, "parents": [folder_id]}, media_body=media, fields="id").execute()
            return "created"
        except Exception as exc:
            last_exc = exc
            if attempt < cfg["MAX_RETRIES"]:
                time.sleep(cfg["RETRY_DELAY_SECONDS"] * attempt)
    raise last_exc


def scan_tree(source_dirs, skip_hidden):
    dirs = []
    files = []
    runtime_home = HOME.resolve()

    def is_runtime_dir(path):
        resolved = path.resolve()
        return resolved == runtime_home or runtime_home in resolved.parents

    for src in source_dirs:
        if is_runtime_dir(src):
            raise ValueError(f"Source folder is inside MyBackup runtime: {src}")
        if not src.is_dir():
            raise FileNotFoundError(f"Source folder is unavailable; backup is incomplete: {src}")
        dirs.append(src)
        def scan_failed(error):
            raise OSError(f"Cannot scan source; backup is incomplete: {error}") from error

        for root, subdirs, names in os.walk(src, onerror=scan_failed):
            root_path = Path(root)
            subdirs[:] = [d for d in subdirs if not is_runtime_dir(root_path / d)]
            if skip_hidden:
                subdirs[:] = [d for d in subdirs if not d.startswith(".")]
                names = [n for n in names if not n.startswith(".")]
            for d in subdirs:
                dirs.append(root_path / d)
            for name in names:
                p = root_path / name
                if not p.is_symlink() and p.is_file():
                    files.append(p)
    return dirs, files


def root_for_path(path, roots):
    return next((r for r in roots if path == r or r in path.parents), None)


def required_dirs_for_files(files, source_dirs, dirs):
    needed = set()
    roots = sorted(source_dirs, key=lambda p: len(str(p)), reverse=True)
    for path in files:
        root = root_for_path(path, roots)
        if root is None:
            continue
        needed.add(str(root))
        current = path.parent
        while current != root:
            needed.add(str(current))
            current = current.parent
        needed.add(str(path.parent))
    return [d for d in dirs if str(d) in needed]


def build_drive_folder_map(service, root_drive_id, source_dirs, dirs, start_time):
    folder_map = {}
    created_count = 0
    total = len(dirs)
    source_dirs_sorted = sorted(source_dirs, key=lambda p: len(str(p)), reverse=True)
    for idx, d in enumerate(dirs, start=1):
        src = next((s for s in source_dirs_sorted if d == s or s in d.parents), None)
        if src is None:
            continue
        if d == src:
            parent_id = root_drive_id
            name = src.name
        else:
            parent_local = d.parent
            parent_id = folder_map.get(str(parent_local))
            if parent_id is None:
                continue
            name = d.name
        folder_id, created = get_or_create_folder(service, name, parent_id)
        folder_map[str(d)] = folder_id
        if created:
            created_count += 1
        if idx == 1 or idx % 5 == 0 or idx == total:
            emit(
                "folder_progress",
                current=str(d),
                checked=idx,
                total=total,
                created=created_count,
                elapsed=int(time.time() - start_time),
            )
    return folder_map


def process_one_file(path, folder_id, creds, cfg, cache, stats, folder_contents):
    try:
        before = signature(path)
        with _cache_lock:
            cached = cache.get(str(path))
        if cached == before:
            with _stats_lock:
                stats["skipped"] += 1
            return "skipped"
        # A changed source is authoritative, even if Drive has a newer timestamp.
        # Remove the old entry before upload so errors always leave this file retryable.
        with _cache_lock:
            cache.pop(str(path), None)
        service = get_service(creds, cfg["HTTP_TIMEOUT_SECONDS"])
        result = upload_file(service, path, folder_id, folder_contents.get(path.name), cfg)
        if signature(path) != before:
            raise OSError("File changed during upload; it will be retried on the next backup")
        with _cache_lock:
            cache[str(path)] = before
        with _stats_lock:
            stats[result] += 1
        return result
    except Exception as exc:
        write_log(f"ERROR file {path}: {exc}")
        with _stats_lock:
            stats["errors"] += 1
        return "error"


def run_backup():
    cfg = load_env()
    stats = {"created": 0, "updated": 0, "skipped": 0, "errors": 0, "total": 0}
    t0 = time.time()
    write_log("Backup started")

    emit("status", message="Authenticating with Google Drive...")
    creds = authenticate()
    service = build_service(creds, cfg["HTTP_TIMEOUT_SECONDS"])

    emit("status", message="Finding the Drive root folder...")
    root_drive_id, _ = get_or_create_folder(service, cfg["DRIVE_FOLDER_NAME"], cfg["DRIVE_PARENT_ID"])
    # Drive IDs identify the actual destination (including the account). Source
    # roots affect the relative folder mapping and must invalidate the cache too.
    cache_destination = {"root_id": root_drive_id,
                   "sources": sorted(str(p.resolve()) for p in cfg["SOURCE_DIRS"])}
    cache = load_cache(cache_destination)

    emit("status", message="Scanning local folders and files...")
    dirs, files = scan_tree(cfg["SOURCE_DIRS"], cfg["SKIP_HIDDEN"])
    stats["total"] = len(files)
    emit("scan_done", folders=len(dirs), files=len(files), elapsed=int(time.time() - t0))

    emit("status", message="Detecting changed files...")
    changed_files = []
    skipped_unchanged = 0
    for p in files:
        if unchanged(p, cache):
            skipped_unchanged += 1
        else:
            changed_files.append(p)
    stats["skipped"] = skipped_unchanged
    needed_dirs = required_dirs_for_files(changed_files, cfg["SOURCE_DIRS"], dirs)

    emit("status", message="Preparing Drive folders...")
    folder_map = build_drive_folder_map(service, root_drive_id, cfg["SOURCE_DIRS"], needed_dirs, t0)

    emit("status", message="Backing up files...")
    roots = sorted(cfg["SOURCE_DIRS"], key=lambda p: len(str(p)), reverse=True)
    file_jobs = []
    destinations = set()
    for p in changed_files:
        root = root_for_path(p, roots)
        if root is None:
            continue
        folder_id = folder_map.get(str(p.parent))
        if folder_id:
            destination = (folder_id, p.name)
            if destination in destinations:
                raise ValueError(f"Multiple source files map to the same Drive destination: {p.name}")
            destinations.add(destination)
            file_jobs.append((p, folder_id))

    done = 0
    folder_contents = {folder_id: list_folder(service, folder_id) for folder_id in {fid for _, fid in file_jobs}}
    last_emit = 0.0
    if not file_jobs:
        emit(
            "upload_progress",
            percent=100,
            done=0,
            total=0,
            created=stats["created"],
            updated=stats["updated"],
            skipped=stats["skipped"],
            errors=stats["errors"],
            elapsed=int(time.time() - t0),
        )
    with ThreadPoolExecutor(max_workers=max(1, cfg["MAX_WORKERS"])) as executor:
        futures = [executor.submit(process_one_file, p, fid, creds, cfg, cache, stats, folder_contents[fid]) for p, fid in file_jobs]
        for future in as_completed(futures):
            done += 1
            try:
                future.result()
            except Exception as exc:
                write_log(f"ERROR upload task: {exc}")
                with _stats_lock:
                    stats["errors"] += 1
            if done % cfg["CACHE_SAVE_EVERY"] == 0:
                save_cache(cache, cache_destination)
            now = time.time()
            if done == 1 or done == len(futures) or now - last_emit >= 0.25:
                last_emit = now
                with _stats_lock:
                    snapshot = dict(stats)
                pct = int(done * 100 / len(futures)) if futures else 100
                emit(
                    "upload_progress",
                    percent=pct,
                    done=done,
                    total=len(futures),
                    created=snapshot["created"],
                    updated=snapshot["updated"],
                    skipped=snapshot["skipped"],
                    errors=snapshot["errors"],
                    elapsed=int(time.time() - t0),
                )

    save_cache(cache, cache_destination)
    with _stats_lock:
        final_stats = dict(stats)
    write_log(f"Backup completed: {final_stats}")
    emit("done", stats=final_stats, elapsed=int(time.time() - t0))


if __name__ == "__main__":
    try:
        run_backup()
    except Exception:
        CRASH_FILE.write_text(traceback.format_exc(), encoding="utf-8")
        emit("error", message=str(CRASH_FILE))
        sys.exit(1)
