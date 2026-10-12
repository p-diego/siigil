#!/usr/bin/env python3
"""I tracciati di un simbolo disegnato da ImageRenderer in un PDF, in JSON per boolsvg: ogni riempimento con i suoi buchi.
Uso: pdf2svg.py in.pdf out.json <lato massimo in pt>

Interpreta il flusso della pagina: q/Q, cm, gs, Do (form annidati con la loro /Matrix), m l c v y h re, riempimenti.
Un riempimento fatto con uno stato grafico che ha una maschera (/SMask, luminosità su fondo bianco) porta con sé i
disegni neri della maschera: sono i buchi da togliere a quel riempimento soltanto. Coordinate finali come gli SVG di SF
Symbols: origine in alto a sinistra, lato più lungo = <lato massimo>."""
import json, re, sys, zlib

src, out, side = sys.argv[1], sys.argv[2], float(sys.argv[3])
data = open(src, "rb").read()
objects = {int(n): body for n, body in re.findall(rb"(\d+)\s+0\s+obj(.*?)endobj", data, re.S)}

def head(n):
    return objects[n].split(b"stream")[0]

def stream(n):
    m = re.search(rb"stream\r?\n(.*?)\r?\nendstream", objects[n], re.S)
    if not m:
        return b""
    try:
        return zlib.decompress(m.group(1))
    except Exception:
        return m.group(1)

def dict_entries(text, key):
    """Le coppie /Nome n 0 R dentro /key << ... >> (anche se il dizionario è in un oggetto a parte)."""
    m = re.search(rb"/" + key + rb"\s*(<<.*?>>|\d+\s+0\s+R)", text, re.S)
    if not m:
        return {}
    d = m.group(1)
    if d.endswith(b"R"):
        d = head(int(d.split()[0]))
    return {name.decode(): int(n) for name, n in re.findall(rb"/([^\s/<>\[\]]+)\s+(\d+)\s+0\s+R", d)}

def resources(obj_head):
    m = re.search(rb"/Resources\s*(\d+)\s+0\s+R", obj_head)
    if m:
        return head(int(m.group(1)))
    m = re.search(rb"/Resources\s*(<<.*>>)", obj_head, re.S)
    return m.group(1) if m else b""

def matrix(obj_head):
    m = re.search(rb"/Matrix\s*\[([^\]]*)\]", obj_head)
    return [float(v) for v in m.group(1).split()] if m else [1, 0, 0, 1, 0, 0]

def mul(a, b):
    return [a[0]*b[0] + a[1]*b[2], a[0]*b[1] + a[1]*b[3], a[2]*b[0] + a[3]*b[2], a[2]*b[1] + a[3]*b[3],
            a[4]*b[0] + a[5]*b[2] + b[4], a[4]*b[1] + a[5]*b[3] + b[5]]

NUM = rb"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?"

def run(content, res, ctm, fills, mask_holes=None):
    """Aggiunge a fills i riempimenti del flusso: (sottotracciati, regola, buchi)."""
    ext, xobj = dict_entries(res, b"ExtGState"), dict_entries(res, b"XObject")
    state, stack, ops, cur, last = {"ctm": ctm, "holes": mask_holes}, [], [], [], None
    def pt(x, y):
        c = state["ctm"]
        return (c[0]*x + c[2]*y + c[4], c[1]*x + c[3]*y + c[5])
    for tok in re.findall(rb"/[^\s/\[\]()<>]+|\[|\]|" + NUM + rb"|[A-Za-z*'\"]+", content):
        if re.fullmatch(NUM, tok):
            ops.append(float(tok)); continue
        t = tok.decode()
        if t.startswith("/"):
            ops.append(t[1:]); continue
        if t == "q": stack.append(dict(state))
        elif t == "Q": state = stack.pop() if stack else {"ctm": ctm, "holes": mask_holes}
        elif t == "cm": state["ctm"] = mul(ops[-6:], state["ctm"])
        elif t == "gs":
            g = ext.get(ops[-1])
            m = re.search(rb"/SMask\s*<<[^>]*?/G\s+(\d+)\s+0\s+R", head(g)) if g else None
            if m:   # i disegni della maschera, nelle coordinate di adesso, sono i buchi dei riempimenti che seguono
                holes, form = [], int(m.group(1))
                run(stream(form), resources(head(form)), mul(matrix(head(form)), state["ctm"]), holes)
                state["holes"] = [(f, r) for f, r, _ in holes]
            elif g is not None and b"/SMask" in head(g):
                state["holes"] = None
        elif t == "Do":
            n = xobj.get(ops[-1])
            if n is not None:
                run(stream(n), resources(head(n)), mul(matrix(head(n)), state["ctm"]), fills, state["holes"])
        elif t == "m": cur.append(("M", [pt(*ops[-2:])])); last = pt(*ops[-2:])
        elif t == "l": cur.append(("L", [pt(*ops[-2:])])); last = pt(*ops[-2:])
        elif t == "c": p = ops[-6:]; cur.append(("C", [pt(p[0], p[1]), pt(p[2], p[3]), pt(p[4], p[5])])); last = pt(p[4], p[5])
        elif t == "v": p = ops[-4:]; cur.append(("C", [last, pt(p[0], p[1]), pt(p[2], p[3])])); last = pt(p[2], p[3])
        elif t == "y": p = ops[-4:]; cur.append(("C", [pt(p[0], p[1]), pt(p[2], p[3]), pt(p[2], p[3])])); last = pt(p[2], p[3])
        elif t == "h": cur.append(("Z", []))
        elif t == "re":
            x, y, w, h = ops[-4:]
            cur += [("M", [pt(x, y)]), ("L", [pt(x + w, y)]), ("L", [pt(x + w, y + h)]), ("L", [pt(x, y + h)]), ("Z", [])]
        elif t in ("f", "F", "f*", "B", "B*", "b", "b*"):
            if cur: fills.append((cur, "evenodd" if "*" in t else "nonzero", state["holes"] or []))
            cur = []
        elif t in ("n", "S", "s"):
            cur = []
        if t not in ("[", "]"):
            ops = []

page = next(n for n in objects if b"/Type /Page" in head(n) and b"/Pages" not in head(n))
content = b"".join(stream(int(n)) for n in re.findall(rb"(\d+)\s+0\s+R", re.search(rb"/Contents\s*(\[[^\]]*\]|\d+\s+0\s+R)", head(page)).group(1)))
fills = []
run(content, resources(head(page)), [1, 0, 0, 1, 0, 0], fills)

pts = [p for f, _, _ in fills for _, ps in f for p in ps if p]
minx, maxx = min(p[0] for p in pts), max(p[0] for p in pts)
miny, maxy = min(p[1] for p in pts), max(p[1] for p in pts)
k = side / max(maxx - minx, maxy - miny)
def d_of(f):
    return "".join(c + " ".join("%.3f %.3f" % ((p[0] - minx) * k, (maxy - p[1]) * k) for p in ps) for c, ps in f)
json.dump({"w": (maxx - minx) * k, "h": (maxy - miny) * k,
           "layers": [{"d": d_of(f), "rule": r, "holes": [{"d": d_of(hf), "rule": hr} for hf, hr in holes]} for f, r, holes in fills]},
          open(out, "w"))
print(out, "%.1f×%.1f" % ((maxx - minx) * k, (maxy - miny) * k), len(fills), "riempimenti,", sum(len(h) for _, _, h in fills), "buchi")
