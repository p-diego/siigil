#!/usr/bin/env python3
"""La versione scura di un file di Icon Composer, per il build: le impostazioni "-specializations" con "appearance": "dark"
diventano quelle di base (actool disegna solo l'aspetto di base). Modifica icon.json sul posto: va usato su una copia.
Uso: dark.py <file.icon>/icon.json"""
import json, sys

def dark(node):
    if isinstance(node, dict):
        for key in [k for k in node if k.endswith("-specializations")]:
            for entry in node[key]:
                if entry.get("appearance") == "dark":
                    node[key[: -len("-specializations")]] = entry["value"]
            del node[key]
        for v in node.values():
            dark(v)
    elif isinstance(node, list):
        for v in node:
            dark(v)

t = json.load(open(sys.argv[1]))
dark(t)
json.dump(t, open(sys.argv[1], "w"), indent=2)
