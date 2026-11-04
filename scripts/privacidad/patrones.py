#!/usr/bin/env python3
"""Personal-data patterns over added lines (layer 2 of escanear.sh).

Reads `file<TAB>line` records from stdin and prints `kind<TAB>file<TAB>match`
for every hit. Usage: patrones.py <permitidos.txt> [<local deny list>]
"""
import os
import re
import sys

PATTERNS = [
    ("NIF/DNI", r"\b[0-9]{8}[A-HJ-NP-TV-Z]\b"),
    ("NIE", r"\b[XYZ][0-9]{7}[A-HJ-NP-TV-Z]\b"),
    ("CIF", r"\b[ABCDEFGHJNPQRSUVW][0-9]{7}[0-9A-J]\b"),
    ("IBAN", r"\b[A-Z]{2}[0-9]{2}(?: ?[0-9]{4}){5}\b"),
    ("Teléfono", r"(?:\+34|0034)[ -]?[6-9][0-9]{2}(?:[ -]?[0-9]{2,3}){2,3}"),
    ("Correo", r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"),
    ("Ruta de un Mac", r"/Users/[a-z][a-z0-9._-]+"),
    ("Carpeta personal de iCloud", r"Mobile Documents/com~apple~CloudDocs/[A-Z]"),
    ("Salud", r"[Bb]aja (?:médica|laboral)|incapacidad temporal|parte de (?:baja|alta)|mutua laboral"),  # privacidad:permitir
]
# Example or technical domains and paths.
EMAIL_OK = re.compile(
    r"@(?:example\.(?:com|org|net)|[a-z0-9-]+\.example|tls\.local|test|localhost|"
    r"(?:users\.)?noreply\.github\.com|anthropic\.com|multica\.ai|ejemplo\.(?:com|es|test)|empresa\.test|dominio\.es)\b"
    r"|\.invalid\b|\.example\b"
    r"|noreply@|^git@"
)
PATH_OK = re.compile(r"/Users/(?:prueba|ejemplo|persona|a|tu-usuario|usuario|runner|you|me|shared)\b")
SKIP_FILES = re.compile(r"(\.lock|pnpm-lock\.yaml|\.png|\.jpe?g|\.pdf|\.svg|\.ico|\.icns|\.gif|\.webp|\.mp4|\.zip)$")
MARKER = "privacidad:permitir"


def read_list(path):
    if not path or not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip() and not l.startswith("#")]


allowed = set(read_list(sys.argv[1] if len(sys.argv) > 1 else None))
patterns = [(k, re.compile(p)) for k, p in PATTERNS]
patterns += [("Lista local", re.compile(p)) for p in read_list(sys.argv[2] if len(sys.argv) > 2 else None)]

hits = set()
for record in sys.stdin:
    path, _, line = record.rstrip("\n").partition("\t")
    if SKIP_FILES.search(path) or MARKER in line:
        continue
    for kind, rx in patterns:
        for m in rx.finditer(line):
            value = m.group(0)
            if value in allowed:
                continue
            if kind == "Correo" and EMAIL_OK.search(value):
                continue
            if kind == "Correo" and re.match(r"^[^@]*@v?[0-9]", value):
                continue
            if kind == "Ruta de un Mac" and PATH_OK.match(value):
                continue
            hits.add((kind, path, value))
for h in sorted(hits):
    print("\t".join(h))
