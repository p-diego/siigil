# Icone delle impostazioni

Le disegna l'autore. Per ogni icona **un file di Icon Composer** (`<nome>.icon`, come l'icona dell'app). Il build compila i
`.icon` con actool e li porta a PNG 256 (togliendo da una copia il rettangolo invisibile dei bordi che hanno gli SVG
esportati da SF Symbols: actool lo colorerebbe tutto). Col Mac in scuro la versione scura (`<nome>-dark.png`), dalle
impostazioni "dark" del file di Icon Composer. Siigil le mostra a 24 pt nella barra laterale, 28 pt nell'elenco di Pillole,
44 pt in cima alla schermata di un widget. Se un file manca, al suo posto non compare niente (il simbolo di riserva è
stato tolto il 4/10).

Pagine (barra laterale): `pane-general`, `pane-pills`, `pane-appearance`, `pane-mascots` (provvisoria: un simbolo di sistema
finché non si decidono le icone), `pane-ai`

Widget (elenco di Pillole e schermata): `workspaces`, `hidden`, `focus`, `wifi`, `bluetooth`, `nowPlaying`, `volume`, `battery`, `clock`

Le icone di adesso (27/9) le ha fatte `scripts/settings-icons/make.sh` nello stile della prima icona Generali
dell'autore (`scripts/settings-icons/template.json`): si rifanno tutte da lì, per esempio dopo aver cambiato un simbolo nell'elenco dello script.
