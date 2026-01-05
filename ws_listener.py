#!/usr/bin/env python3
"""ws_listener.py

Escucha el WebSocket en ws://localhost:21213/ y guarda cada mensaje
recibido en formato JSONL incluyendo timestamp y payload original.

Uso:
  python ws_listener.py --url ws://localhost:21213/ --out events.jsonl

El script intenta reconectar con backoff exponencial si la conexión falla.
"""

from __future__ import annotations

import asyncio
import json
import datetime
import argparse
import sys
import traceback

import websockets
from typing import Any


DEFAULT_URL = "ws://localhost:21213/"
DEFAULT_OUT = "tiktok-live-connector-events.jsonl"


def _write_sync(path: str, data: str) -> None:
    with open(path, "a", encoding="utf-8") as f:
        f.write(data + "\n")


async def save_entry(path: str, entry: dict) -> None:
    loop = asyncio.get_running_loop()
    data = json.dumps(entry, ensure_ascii=False)
    await loop.run_in_executor(None, _write_sync, path, data)


async def listen(url: str, out: str, reconnect: bool = True) -> None:
    backoff = 1
    while True:
        try:
            async with websockets.connect(url) as ws:
                print(f"Conectado a {url}")
                backoff = 1
                async for msg in ws:
                    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
                    entry: dict[str, Any] = {
                        "received_at": now,
                    }
                    try:
                        decoded_msg = msg if isinstance(msg, str) else bytes(msg).decode('utf-8')
                        entry["data"] = json.loads(decoded_msg)
                    except (json.JSONDecodeError, UnicodeDecodeError):
                        entry["raw"] = msg

                    try:
                        await save_entry(out, entry)
                    except Exception:
                        print("Error guardando evento:")
                        traceback.print_exc()
                    else:
                        ev_name = None
                        try:
                            ev_name = entry.get("data", {}).get("event")
                        except Exception:
                            ev_name = None
                        summary = f" evento={ev_name}" if ev_name else ""
                        print(f"Guardado evento{summary}")

        except (asyncio.CancelledError, KeyboardInterrupt):
            print("Interrumpido, cerrando listener")
            raise
        except Exception as e:
            print(f"Conexión fallida: {e}")
            traceback.print_exc()
            if not reconnect:
                raise
            print(f"Reconectando en {backoff} segundos...")
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 60)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Escucha WS y guarda eventos en JSONL")
    p.add_argument("--url", default=DEFAULT_URL, help="URL del WebSocket (por defecto: %(default)s)")
    p.add_argument("--out", default=DEFAULT_OUT, help="Archivo de salida JSONL (por defecto: %(default)s)")
    p.add_argument("--no-reconnect", dest="reconnect", action="store_false", help="No reconectar tras fallo")
    return p


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    try:
        asyncio.run(listen(args.url, args.out, args.reconnect))
    except KeyboardInterrupt:
        print("Cerrado por usuario")
    except Exception:
        print("Listener terminado con error:")
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
