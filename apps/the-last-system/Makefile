# The Last System · cadena de build (PLAN §3.1, §9 y §10).
# Compatible con el GNU Make 3.81 de macOS. Escribe «make» para ver la ayuda.

SHELL := /bin/bash

PROJECT     := TheLastSystem.xcodeproj
SCHEME      := TheLastSystem
PKG         := Packages/TLSKit
DERIVED     ?= build/DerivedData
DIST        ?= dist
SPM_SCRATCH ?= build/spm
DESTINATION ?= platform=macOS,arch=arm64

# Equipo de firma (Config/Signing.local.xcconfig, lo escribe «make firma»). Con equipo,
# Xcode puede preparar el certificado y el perfil durante la compilación.
TEAM := $(shell sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Z0-9]+).*/\1/p' Config/Signing.local.xcconfig 2>/dev/null | tail -n 1)
SIGN_FLAGS := $(if $(TEAM),-allowProvisioningUpdates,)

XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) \
              -destination '$(DESTINATION)' $(SIGN_FLAGS)

# Los scripts leen las mismas rutas.
export DERIVED DIST

.DEFAULT_GOAL := help
.PHONY: help bootstrap gen build release test capturas conformidad sandbox tls-tool firma dmg verify clean

help:
	@echo "The Last System · objetivos:"
	@echo "  make bootstrap    comprueba Xcode y xcodegen (lo instala con Homebrew si falta)"
	@echo "  make firma        configura la firma con tu equipo de Apple (Config/Signing.local.xcconfig)"
	@echo "  make gen          regenera TheLastSystem.xcodeproj desde project.yml"
	@echo "  make build        compila la app en Debug"
	@echo "  make release      compila Release arm64 y comprueba la firma"
	@echo "  make test         swift test del paquete TLSKit + compilación de la app"
	@echo "  make capturas     PNG de las pantallas de F1 a F6 (claro y oscuro) en build/capturas/"
	@echo "  make conformidad  pruebas de conformidad (y TLS_CONFORMIDAD_G3=<copia> opcional)"
	@echo "  make sandbox      sandbox de los asistentes con Claude Code real (necesita make build y sesión iniciada)"
	@echo "  make tls-tool     compila la herramienta de desarrollo en $(SPM_SCRATCH)/release/tls-tool"
	@echo "  make dmg          Release → $(DIST)/The-Last-System-<versión>.dmg + SHA256SUMS"
	@echo "  make verify       firma, permisos, último DMG, sumas SHA-256 y sandbox de los asistentes"
	@echo "  make clean        borra $(DERIVED), $(DIST) y $(SPM_SCRATCH)"
	@echo "Firma actual: $(if $(TEAM),equipo $(TEAM),ad hoc (ejecuta make firma))"

bootstrap:
	@xcode-select -p >/dev/null 2>&1 || { echo "Falta Xcode. Instálalo desde la App Store y ábrelo una vez."; exit 1; }
	@command -v xcodebuild >/dev/null || { echo "Falta xcodebuild. Ejecuta: sudo xcode-select -s /Applications/Xcode.app"; exit 1; }
	@xcodebuild -version | head -n 1
	@if ! command -v xcodegen >/dev/null; then \
	  if command -v brew >/dev/null; then echo "Instalando xcodegen con Homebrew…"; brew install xcodegen; \
	  else echo "Falta xcodegen y no hay Homebrew. Instala Homebrew (https://brew.sh) o sigue sin él: el .xcodeproj va versionado."; exit 1; fi; \
	fi
	@echo "xcodegen $$(xcodegen --version | sed 's/^Version: //')"
	@echo "Resolviendo dependencias Swift…"
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) -resolvePackageDependencies -quiet
	@if [ -n "$(TEAM)" ]; then echo "Firma: equipo $(TEAM)."; else echo "Firma: ad hoc. Ejecuta make firma para firmar con tu equipo."; fi

gen:
	@command -v xcodegen >/dev/null || { echo "Falta xcodegen: ejecuta make bootstrap."; exit 1; }
	xcodegen generate --spec project.yml

build:
	$(XCODEBUILD) -configuration Debug -quiet build

release:
	scripts/build-dmg.sh --solo-compilar

# F1+: añadir «xcodebuild test» cuando exista el target de UITests.
test:
	swift test --package-path $(PKG) --scratch-path $(SPM_SCRATCH)
	$(XCODEBUILD) -configuration Debug -quiet build

# Sin abrir la app: pinta las pantallas fuera de pantalla y deja build/capturas/index.html.
capturas:
	SPM_SCRATCH=$(SPM_SCRATCH) scripts/capturas.sh

conformidad:
	scripts/conformidad.sh

# «make test» no lanza las pruebas con Claude Code de verdad; esta sí (y también «make verify»).
sandbox:
	SPM_SCRATCH=$(SPM_SCRATCH) scripts/verificar-sandbox.sh

tls-tool:
	swift build -c release --package-path $(PKG) --scratch-path $(SPM_SCRATCH) --product tls-tool
	@echo "Herramienta lista: $(SPM_SCRATCH)/release/tls-tool"

firma:
	scripts/configurar-firma.sh

dmg:
	scripts/build-dmg.sh

verify:
	scripts/verificar.sh

clean:
	rm -rf "$(DERIVED)" "$(DIST)" "$(SPM_SCRATCH)" build/spm-conformidad build/xcodebuild-release.log
