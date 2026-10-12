#!/bin/bash
# Un video del README dalla modalità demo (Sources/Siigil/Demo.swift): chiude Siigil, lancia la demo della scena, registra
# la striscia della barra mentre il puntatore vero fa i suoi passi (demo-pointer.swift), chiude la demo, controlla che le
# impostazioni vere siano rimaste uguali e riapre Siigil; poi images/<scena>.webp in loop. Muove il puntatore: col Mac
# libero.
#   scripts/demo-video.sh workspaces|mascots|widgets
set -euo pipefail
cd "$(dirname "$0")/.."
scene=${1:-}
# ponytail: rettangoli (x,y,larghezza,altezza in punti) e coordinate misurati sulla barra demo di questo Mac (schermo da
# 1710 pt col notch); su un altro schermo vanno rimisurati con una cattura ferma della barra demo.
case $scene in
    workspaces) rect=0,0,330,38; seconds=11
                steps=(move 300 70 wait 1.0 click 148 19 wait 1.4 click 214 19 wait 1.4 drag 194 19 60 19 1.2 wait 1.8) ;;
    #           pillola 2, pillola 3, Musica dalla 3 alla 1 (lo spazio la segue)
    mascots)    rect=945,0,290,38; seconds=10
                steps=(move 1300 70 wait 5.0 move 970 19 wait 0.7 move 1007 19 wait 0.7 move 1125 19 wait 0.7 move 1300 70) ;;
    #           a metà il puntatore passa sopra le tre mascotte
    widgets)    rect=0,0,505,38; seconds=13; steps=(move 700 70) ;;   # il puntatore lontano dai widget
    *) echo "uso: $0 workspaces|mascots|widgets" >&2; exit 2 ;;
esac
W=.build/demo-video/$scene
rm -rf $W && mkdir -p $W/frames
make build >/dev/null
swiftc -O scripts/demo-pointer.swift -o .build/demo-pointer
# La Siigil che gira adesso (sviluppo o installata): è quella da riaprire alla fine; nessuna se non girava.
real=$(ps -o comm= -p "$(pgrep -x Siigil | head -1)" 2>/dev/null | sed 's|/Contents/MacOS/Siigil$||' || true)
defaults export com.siigil.app $W/prima.plist
# Da qui in poi, qualunque cosa succeda (un errore, Ctrl-C): chiudere la demo, controllare che le impostazioni vere siano
# rimaste uguali e riaprire la Siigil di prima.
restore() {
    pkill -x Siigil || true
    while pgrep -x Siigil >/dev/null; do sleep 0.1; done
    defaults delete com.siigil.demo 2>/dev/null || true
    defaults export com.siigil.app $W/dopo.plist
    if cmp -s $W/prima.plist $W/dopo.plist; then echo "impostazioni vere uguali"; else echo "ATTENZIONE: impostazioni vere cambiate ($W)" >&2; fi
    if [ -n "$real" ]; then open "$real"; fi
}
trap restore EXIT
pkill -x Siigil || true
while pgrep -x Siigil >/dev/null; do sleep 0.1; done
open -n .build/Siigil.app --args --demo "$scene" -AppleLanguages "(en)"
sleep 1.5
screencapture -v -V "$seconds" -x -R"$rect" $W/video.mov &
.build/demo-pointer "${steps[@]}"
wait
trap - EXIT
restore
ffmpeg -loglevel error -i $W/video.mov -vf fps=20 $W/frames/%04d.png
img2webp -loop 0 -lossy -q 82 -d 50 $W/frames/*.png -o images/$scene.webp
ls -l images/$scene.webp
