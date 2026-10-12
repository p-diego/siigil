APP = .build/Siigil.app
BIN = .build/release/Siigil
INSTALLED = $(HOME)/Applications/Siigil.app
DMG = .build/Siigil-$(VERSION).dmg
STAGE = .build/dmg
VERSION = $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
# Firma: il certificato "Apple Development" del portachiavi se c'è (lo crea Xcode con l'Apple ID), altrimenti ad-hoc.
# Con il certificato macOS lega i permessi (Posizione, Accesso completo al disco) al nome sul certificato: restano da
# una build all'altra e dopo il rinnovo annuale. Ad-hoc li lega all'hash della singola build: si azzerano a ogni
# installazione (verificato il 2026-09-22). Si usa l'impronta SHA-1 del primo certificato valido.
SIGN_ID = $(or $(shell security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $$2; exit}'),-)

.PHONY: build run cpu test install uninstall dist dmg release

build:
	swift build -c release
	rm -rf $(APP)   # da capo: un file tolto dalle risorse non deve restare nell'app (e nelle release)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/Siigil
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/siigil-hook $(APP)/Contents/Resources/siigil-hook
	cp Resources/*.shortcut $(APP)/Contents/Resources/
	# Le icone delle impostazioni dell'autore (Resources/settings-icons/README.md). I file di
	# Icon Composer (<nome>.icon) li compila actool come l'icona dell'app e sips li porta a PNG 256. Gli SVG esportati da SF
	# Symbols hanno un rettangolo invisibile dei bordi che actool, col riempimento del livello, colora tutto (misurato il
	# 27/9: un quadrato grigio al posto dell'ingranaggio): si toglie da una copia, il file dell'autore resta com'è.
	# La versione scura (<nome>-dark.png, col Mac in scuro) dalle impostazioni "dark" del file (dark.py, su una copia).
	mkdir -p $(APP)/Contents/Resources/settings-icons
	rm -rf .build/settings-icons
	for i in Resources/settings-icons/*.icon; do n=$$(basename "$$i" .icon); d=$(CURDIR)/.build/settings-icons/$$n; \
		mkdir -p $$d && cp -R "$$i" $$d/ && sed -i '' '/<rect [^>]*opacity="0"[^>]*\/>/d' $$d/$$n.icon/Assets/*.svg && \
		for v in "" -dark; do [ -z "$$v" ] || python3 scripts/settings-icons/dark.py $$d/$$n.icon/icon.json && \
			xcrun actool $$d/$$n.icon --compile $$d --platform macosx --minimum-deployment-target 26.0 --app-icon $$n \
				--output-partial-info-plist /dev/null >/dev/null && \
			sips -s format png -Z 256 $$d/$$n.icns --out $(APP)/Contents/Resources/settings-icons/$$n$$v.png >/dev/null && \
			rm -f $$d/$$n.icns; done; done
	# La licenza di Siigil e quelle dei pezzi di altri (colori dei temi): le cita Informazioni su Siigil.
	cp -R Resources/Licenses $(APP)/Contents/Resources/ && cp LICENSE $(APP)/Contents/Resources/Licenses/Siigil.txt
	cp -R Resources/*.lproj $(APP)/Contents/Resources/
	# Icona (Icon Composer, Resources/icon/siigil_icon.icon): actool produce Assets.car (glass, macOS 26+) e l'.icns
	# Percorsi assoluti: actool passa il lavoro a un servizio che resta aperto e risolve quelli relativi dalla cartella della
	# sua prima chiamata, non da quella di make (visto il 27/9: "output directory does not exist" in un'altra cartella).
	xcrun actool $(CURDIR)/Resources/icon/siigil_icon.icon --compile $(CURDIR)/$(APP)/Contents/Resources --platform macosx \
		--minimum-deployment-target 26.0 --app-icon siigil_icon --output-partial-info-plist /dev/null >/dev/null
	# Firma dell'intero bundle con identificatore stabile (SIGN_ID: certificato Apple Development o ad-hoc). Nessun
	# timestamp: la build non è notarizzata e così non serve la rete.
	codesign --force --deep --timestamp=none --sign $(SIGN_ID) --identifier com.siigil.app $(APP)

# Chiude la vecchia istanza e aspetta che sia uscita prima di chiamare open
# (altrimenti LaunchServices "riapre" la vecchia). Non tocca SketchyBar né AeroSpace.
run: build
	pkill -x Siigil; while pgrep -x Siigil >/dev/null; do sleep 0.1; done; true
	open $(APP)

# Misura la differenza di tempo CPU in 16 s (spec prestazioni §2): rilancia la build di sviluppo, aspetta che si assesti.
# ps %cpu è una media decadente che include l'avvio. Misura anche il WindowServer: è lì che finisce il costo del vetro
# (ogni ridisegno della barra lo paga il compositore, non Siigil). Serve prima/dopo ogni modifica al ridisegno.
cpu: run
	@sleep 8; pid=$$(pgrep -x Siigil) || { echo "Siigil non è partita"; exit 1; }; ws=$$(pgrep -x WindowServer); \
	t0=$$(ps -o cputime= -p $$pid); w0=$$(ps -o cputime= -p $$ws); sleep 16; t1=$$(ps -o cputime= -p $$pid); w1=$$(ps -o cputime= -p $$ws); \
	echo "$$t0 $$t1 $$w0 $$w1" | awk '{ split($$1, a, ":"); split($$2, b, ":"); split($$3, c, ":"); split($$4, d, ":"); \
	  printf "CPU media: Siigil %.1f%%, WindowServer %.1f%%\n", ((b[1]*60+b[2]) - (a[1]*60+a[2])) / 16 * 100, ((d[1]*60+d[2]) - (c[1]*60+c[2])) / 16 * 100 }'

# I test del pacchetto (swift test); `release` li lancia prima di taggare.
test:
	swift test

# Copia in ~/Applications e lancia; l'app si registra da sola come elemento di login (SMAppService, main.swift).
install: build
	pkill -x Siigil; while pgrep -x Siigil >/dev/null; do sleep 0.1; done; true
	mkdir -p $(HOME)/Applications
	rm -rf $(INSTALLED) && cp -R $(APP) $(INSTALLED)
	open $(INSTALLED)

uninstall:
	pkill -x Siigil; rm -rf $(INSTALLED); true

# Zip da distribuire a mano (firma ad-hoc: chi lo installa toglie la quarantena, vedi README).
dist: build
	ditto -c -k --keepParent $(APP) .build/Siigil-$(VERSION).zip
	@echo .build/Siigil-$(VERSION).zip

# Immagine disco per le persone: l'app e il collegamento ad Applicazioni in una finestra con sfondo quasi nero, freccia e
# nota sul primo avvio (Resources/dmg/background.swift la disegna a ogni build; layout.applescript la fa impaginare al
# Finder, che la prima volta chiede il permesso Automazione a chi lancia make). HFS+ in lettura-scrittura per impostare la
# finestra, poi convertita compressa. Lo zip resta per gli script (dotfiles) e per l'aggiornamento da dentro l'app.
dmg: build
	rm -rf $(STAGE) $(DMG) .build/Siigil-rw.dmg
	mkdir -p $(STAGE)/.background
	cp -R $(APP) $(STAGE)/
	ln -s /Applications $(STAGE)/Applications
	swift Resources/dmg/background.swift $(STAGE)/.background/background.png
	cp $(APP)/Contents/Resources/siigil_icon.icns $(STAGE)/.VolumeIcon.icns
	hdiutil create -volname Siigil -srcfolder $(STAGE) -fs HFS+ -format UDRW -ov -quiet .build/Siigil-rw.dmg
	hdiutil attach -readwrite -noverify -noautoopen -quiet .build/Siigil-rw.dmg
	command -v SetFile >/dev/null && SetFile -a C /Volumes/Siigil || true
	osascript Resources/dmg/layout.applescript
	hdiutil detach -quiet /Volumes/Siigil
	hdiutil convert -format UDZO -o $(DMG) -quiet .build/Siigil-rw.dmg
	rm -f .build/Siigil-rw.dmg
	@echo $(DMG)

# Pubblica lo zip e il DMG come GitHub Release v<versione> (da Info.plist): servono i test verdi, l'albero pulito
# e una versione nuova. Il tag punta al commit locale, non alla testa del remote.
release: test dist dmg
	# Una release ad-hoc (nessun certificato Apple Development valido) non la installerebbe nessuno: nessuna copia si aggiornerebbe da sola.
	[ "$(SIGN_ID)" != "-" ] || { echo "Nessun certificato Apple Development valido: una release ad-hoc non si aggiornerebbe"; exit 1; }
	# Anche i file nuovi: lo zip si fa dall'albero, il tag dal commit, e un file mai aggiunto finirebbe solo nel primo (review 4/10).
	[ -z "$$(git status --porcelain)" ] || { echo "Modifiche o file nuovi non committati: fai commit prima"; exit 1; }
	git tag v$(VERSION)
	git push origin v$(VERSION)
	# Sul repo pubblico del codice: da lì l'app si aggiorna e gli altri scaricano il DMG. Le note sono l'oggetto del commit.
	gh release create v$(VERSION) .build/Siigil-$(VERSION).zip $(DMG) --verify-tag --notes "$$(git log -1 --format=%s)"
