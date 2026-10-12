#!/bin/bash
# Rifà i file di Icon Composer delle impostazioni (Resources/settings-icons/<nome>.icon) come Impostazioni di Sistema:
# simbolo bianco su uno sfondo colorato, una tinta smorzata per significato (autore, 27/9: variante 4 di un foglio di
# quattro; le pagine e App nascoste grigie). Ombra, trasparenza e scala dalla prima icona Generali dell'autore
# (template.json). Chiaro e scuro nello stesso file: in scuro lo sfondo si fa più profondo.
#
# Come arriva l'SVG di un simbolo (27/9): macOS non dà i contorni dei simboli (NSImage li disegna come bitmap, i font non
# legano i nomi ai glifi); ImageRenderer di SwiftUI li scrive in PDF come tracciati (symrender), pdf2svg.py li legge con i
# buchi delle maschere di ogni pezzo, boolsvg li toglie con le operazioni booleane di CoreGraphics.
#
# Uso, dalla radice del repo: scripts/settings-icons/make.sh   (poi make build)
set -e
cd "$(dirname "$0")/../.."
OUT=Resources/settings-icons
TOOLS=.build/icon-tools
mkdir -p $TOOLS
swiftc -O scripts/settings-icons/symrender.swift -o $TOOLS/symrender
swiftc -O scripts/settings-icons/boolsvg.swift -o $TOOLS/boolsvg

make_icon() {   # nome, svg, nome del livello, scala del livello, tinta "r,g,b" o grey
  local name=$1 svg=$2 layer=$3 scale=$4 hue=$5
  rm -rf $OUT/$name.icon && mkdir -p $OUT/$name.icon/Assets
  cp "$svg" $OUT/$name.icon/Assets/$layer.svg
  python3 - scripts/settings-icons/template.json $OUT/$name.icon/icon.json "$layer" "$scale" "$hue" <<'EOF'
import json, sys
t = json.load(open(sys.argv[1]))
layer = t["groups"][0]["layers"][0]
layer["image-name"], layer["name"] = sys.argv[3] + ".svg", sys.argv[3]
layer["position"]["scale"] = float(sys.argv[4])   # 6,4 come l'ingranaggio dell'autore; più piccolo per i simboli pieni
# Chiaro e scuro nello stesso file, come fa Icon Composer ("appearance": "dark"); il build ricava lo scuro con dark.py.
def c(v):
    return "extended-srgb:%.5f,%.5f,%.5f,1.00000" % tuple(min(1, max(0, x)) for x in v)
def grad(a, b):
    return {"linear-gradient": [c(a), c(b)]}
if sys.argv[5] == "grey":
    light, dark = grad((0.62, 0.62, 0.66), (0.46, 0.46, 0.50)), grad((0.40, 0.40, 0.44), (0.26, 0.26, 0.30))
else:   # la tinta mescolata col grigio: smorzata, non arlecchino
    hue = [float(x) for x in sys.argv[5].split(",")]
    lt = [v * 0.6 + 0.55 * 0.4 + 0.10 for v in hue]; lb = [v * 0.6 + 0.55 * 0.4 - 0.06 for v in hue]
    dt = [v * 0.5 + 0.35 * 0.5 for v in hue]; db = [v - 0.12 for v in dt]
    light, dark = grad(lt, lb), grad(dt, db)
t.pop("fill", None)
t["fill-specializations"] = [{"value": light}, {"appearance": "dark", "value": dark}]
layer.pop("fill", None)   # il simbolo bianco, come in Impostazioni di Sistema
layer["fill-specializations"] = [{"value": grad((1, 1, 1), (0.90, 0.90, 0.93))}, {"appearance": "dark", "value": grad((1, 1, 1), (0.88, 0.88, 0.91))}]
json.dump(t, open(sys.argv[2], "w"), indent=2)
EOF
  echo "$name.icon"
}

# Il simbolo di ogni pagina e widget (gli stessi di Page.symbol e WidgetID.icon, SettingsView.swift), la scala del
# livello (6,4 di base; un filo più piccoli spazi, Full immersione e orologio, che riempiono il riquadro: autore, 27/9) e
# la tinta dello sfondo per significato: le pagine della barra laterale tutte grigie come Generali (autore, 27/9); i
# widget blu spazi e Wi-Fi, ambra orologio, indaco Full immersione, rosso volume, verde batteria, grigio il resto.
# Generali: gearshape, meno dettagliato dell'ingranaggio con tanti denti della prima icona (autore, 27/9).
while read name symbol scale hue; do
  $TOOLS/symrender $symbol $TOOLS/$name.pdf >/dev/null
  python3 scripts/settings-icons/pdf2svg.py $TOOLS/$name.pdf $TOOLS/$name.json 114.5 >/dev/null
  $TOOLS/boolsvg $TOOLS/$name.json $TOOLS/$name.svg >/dev/null
  make_icon $name $TOOLS/$name.svg $symbol $scale $hue
done <<'LIST'
pane-general gearshape.fill 6.4 grey
pane-pills ellipsis.rectangle.fill 6.4 grey
pane-appearance swatchpalette.fill 6.4 grey
pane-mascots face.smiling.fill 6.4 grey
pane-ai sparkle 6.4 grey
workspaces square.grid.2x2.fill 5.8 0,0.48,1
hidden eye.slash.fill 6.4 grey
focus moon.fill 5.8 0.35,0.34,0.84
wifi wifi 6.4 0,0.48,1
volume speaker.wave.2.fill 6.4 1,0.18,0.33
nowPlaying music.note 5.8 0.98,0.24,0.27
battery battery.75percent 6.4 0.20,0.78,0.35
clock clock.fill 5.8 1,0.58,0
LIST

# Bluetooth (blu come il Wi-Fi): SF Symbols non ha il logo, la runa la disegna boolsvg --rune (lo stesso tracciato della pillola).
$TOOLS/boolsvg --rune $TOOLS/bluetooth.svg >/dev/null
make_icon bluetooth $TOOLS/bluetooth.svg bluetooth 6.4 0,0.48,1
