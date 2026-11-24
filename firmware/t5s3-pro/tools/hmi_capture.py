"""Captura a tela e toca no terminal pela USB (só firmware de bancada).

    uv run --no-project --python 3.12 --with pyserial==3.5 --with pillow==11.1.0 \
        python tools/hmi_capture.py COM3 screen saida.png
    ... COM3 tap 270 880          # toque sintético em coordenadas lógicas
    ... COM3 tap 270 880 saida.png  # toca, espera a tela nova e captura

A imagem é o canvas lógico (540×960 em retrato), exatamente o que o
firmware desenhou, sem câmera no meio. Comandos do console: "mnemos screen"
e {"cmd":"tap","x":..,"y":..}, ambos só existem com MNEMOS_BENCH_BUILD.
"""

from __future__ import annotations

import base64
import json
import sys
import time

import serial
from PIL import Image


def open_port(name: str) -> serial.Serial:
    # DTR/RTS baixos antes de abrir: no USB nativo do ESP32-S3 a borda de
    # DTR reinicia a placa.
    port = serial.Serial()
    port.port = name
    port.baudrate = 115200
    port.timeout = 0.5
    port.dtr = False
    port.rts = False
    port.open()
    if hasattr(port, "set_buffer_size"):
        port.set_buffer_size(rx_size=1 << 20)
    return port


def read_line(port: serial.Serial, deadline: float) -> str | None:
    while time.time() < deadline:
        raw = port.readline()
        if raw:
            return raw.decode("utf-8", "replace").rstrip("\r\n")
    return None


def screen(port: serial.Serial, out: str, attempts: int = 6) -> None:
    """Captura e completa com novas capturas as linhas que o CDC perder.

    Cada linha vem numerada ("0042:<base64>"); a tela fica parada entre as
    capturas, então linhas de capturas diferentes se completam.
    """
    rows: dict[int, bytes] = {}
    size = None
    for attempt in range(attempts):
        size, expected = _collect(port, rows)
        missing = expected - len(rows)
        if missing == 0:
            break
        print(f"captura {attempt + 1}: faltam {missing} linhas; completando")
    else:
        raise SystemExit("não consegui completar a captura")

    w, h = size
    data = b"".join(rows[i] for i in range(expected))
    pixels = bytearray()
    for byte in data:
        pixels.append((byte >> 4) * 17)
        pixels.append((byte & 0x0F) * 17)
    Image.frombytes("L", (w, h), bytes(pixels[: w * h])).save(out)
    print(f"{out} {w}x{h}")


def _collect(port: serial.Serial, rows: dict[int, bytes]):
    port.reset_input_buffer()
    port.write(b"mnemos screen\n")
    # Logo depois de ligar, o laço principal demora a atender o console:
    # repete o pedido até a resposta começar.
    give_up = time.time() + 120
    size = None
    while True:
        line = read_line(port, time.time() + (6 if size is None else 30))
        if line is None:
            if size is None and time.time() < give_up:
                port.write(b"mnemos screen\n")
                continue
            raise SystemExit("sem resposta do terminal (firmware de bancada?)")
        if size is None:
            if line.startswith("@mnemos-screen "):
                w, h = (int(v) for v in line.split()[1:3])
                size = (w, h)
            continue
        if line == "@mnemos-screen-end":
            break
        index, sep, payload = line.partition(":")
        if not sep or not index.isdigit() or len(index) != 4:
            continue  # log do firmware intercalado
        try:
            chunk = base64.b64decode(payload, validate=True)
        except ValueError:
            continue
        if len(chunk) == 48 or int(index) == (size[0] * size[1] - 1) // 96:
            rows[int(index)] = chunk
    expected = (size[0] * size[1] + 95) // 96
    return size, expected


def tap(port: serial.Serial, x: int, y: int) -> dict:
    port.reset_input_buffer()
    port.write((json.dumps({"cmd": "tap", "x": x, "y": y}) + "\n").encode())
    deadline = time.time() + 10
    while True:
        line = read_line(port, deadline)
        if line is None:
            raise SystemExit("sem resposta ao toque")
        if line.startswith("@mnemos "):
            reply = json.loads(line[len("@mnemos ") :])
            print(reply)
            return reply


def wait_idle(port: serial.Serial, quiet: float = 1.5, limit: float = 20) -> None:
    """Espera o painel terminar de atualizar: o log fica quieto."""
    end = time.time() + limit
    last = time.time()
    while time.time() < end:
        if port.readline():
            last = time.time()
        elif time.time() - last > quiet:
            return


def main() -> None:
    name, action, *args = sys.argv[1:]
    port = open_port(name)
    try:
        if action == "screen":
            screen(port, args[0])
        elif action == "tap":
            tap(port, int(args[0]), int(args[1]))
            if len(args) > 2:
                wait_idle(port)
                screen(port, args[2])
        else:
            raise SystemExit(f"ação desconhecida: {action}")
    finally:
        port.close()


if __name__ == "__main__":
    main()
