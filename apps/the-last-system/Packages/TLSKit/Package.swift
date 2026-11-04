// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TLSKit",
    defaultLocalization: "es",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TLSCore", targets: ["TLSCore"]),
        .library(name: "TLSImport", targets: ["TLSImport"]),
        .library(name: "TLSDesign", targets: ["TLSDesign"]),
        .library(name: "TLSEditor", targets: ["TLSEditor"]),
        .library(name: "TLSVisores", targets: ["TLSVisores"]),
        .library(name: "TLSUI", targets: ["TLSUI"]),
        .library(name: "TLSMCPShared", targets: ["TLSMCPShared"]),
        // F4 · servidor de herramientas de los asistentes en la app (socket, PeerValidator, AgentView, catálogo).
        .library(name: "TLSMCPHost", targets: ["TLSMCPHost"]),
        // F3 · puesta en marcha: la ventana y sus pasos (el motor vive en TLSCore/PuestaEnMarcha).
        .library(name: "TLSOnboarding", targets: ["TLSOnboarding"]),
        // F4 · integración: los asistentes de cada empresa abierta (motor, `tls-mcp` y chat) y su ciclo de vida.
        .library(name: "TLSIntegracion", targets: ["TLSIntegracion"]),
        // F5 · pasarela: otros programas por MCP (conexiones, Llavero, catálogo con huella, plantillas, `GatewayRouter`).
        .library(name: "TLSGateway", targets: ["TLSGateway"]),
        // F5 · núcleo: Mail (Cartero), Calendario y los permisos del sistema, con protocolos inyectables.
        .library(name: "TLSIntegrations", targets: ["TLSIntegrations"]),
        .executable(name: "tls-tool", targets: ["tls-tool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", .upToNextMinor(from: "0.9.0")),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.7.3"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
    ],
    targets: [
        .target(
            name: "TLSCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "OrderedCollections", package: "swift-collections"),
            ],
            // Plantillas de serie (F1) y el estándar de Programa (F2 · números: capacidades.yaml con su LICENSE
            // Apache-2.0, semillas, sistemas estándar y catálogo de números clave).
            resources: [.copy("Recursos/Plantillas"), .copy("Recursos/Programa")]
        ),
        .target(name: "TLSImport", dependencies: ["TLSCore"]),
        // Mosaico v2: colores, letra (Space Grotesk, DM Sans y JetBrains Mono, OFL, en el paquete) y componentes.
        .target(name: "TLSDesign", resources: [.copy("Recursos/Fuentes")]),
        // Editor de notas (F1 · editor). Solo diseño y Markdown: no conoce TLSCore.
        .target(
            name: "TLSEditor",
            dependencies: ["TLSDesign", .product(name: "Markdown", package: "swift-markdown")]
        ),
        // Visores de PDF, imagen, audio, vídeo y Quick Look (F1 · visores, R1). Solo diseño y frameworks del sistema.
        .target(name: "TLSVisores", dependencies: ["TLSDesign"]),
        .target(
            name: "TLSUI",
            dependencies: [
                // F4 · rol mika: TLSAgents para ⌘J, la ficha de los asistentes y su estado (PLAN §3.3: TLSUI ── TLSAgents).
                "TLSCore", "TLSImport", "TLSDesign", "TLSEditor", "TLSVisores", "TLSAgents",
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        .target(
            name: "TLSMCPShared",
            dependencies: [.product(name: "MCP", package: "swift-sdk")]
        ),
        // F4 · motor de asistentes (PLAN §5.3): cola, disparos, rutinas, Claude Code en su sandbox, simulación y uso.
        .target(
            name: "TLSAgents",
            dependencies: [
                "TLSCore",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Yams", package: "Yams"),
            ],
            // F4 · rol roles: las grabaciones de Ribera (stream-json) que reproduce `SimulatedRuntime`.
            resources: [.copy("Simulado/Grabaciones")]
        ),
        // F4 · `tls-mcp` en la app (PLAN §5.4): socket BSD, PeerValidator, tokens por ejecución, AgentView y catálogo.
        .target(
            name: "TLSMCPHost",
            dependencies: [
                // F5 · pasarela: TLSGateway para las herramientas `ext_<servidor>_<herramienta>`.
                "TLSCore", "TLSAgents", "TLSMCPShared", "TLSGateway",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        // F5 · pasarela (PLAN §7.4): clientes MCP de otros programas (HTTP preferente; stdio con aviso y sandbox),
        // `conexiones.json` sin secretos, secretos en el Llavero, catálogo con huella, plantillas y `GatewayRouter`.
        .target(
            name: "TLSGateway",
            dependencies: ["TLSCore", "TLSMCPShared", .product(name: "MCP", package: "swift-sdk")]
        ),
        // F5 · núcleo (PLAN §7.1, §7.2 y §8): `Permisos/` (estado de cada permiso del sistema, explicación previa y
        // recuperación), `Mail/` (LectorDeCorreo por JXA lanzado por la app, MailComposer y el Cartero) y `Calendario/`
        // (EventKit). Todo lo del sistema va detrás de un protocolo con su doble de prueba.
        .target(
            name: "TLSIntegrations",
            dependencies: ["TLSCore", "TLSAgents", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        // Copia para pruebas del binario `Helpers/tls-mcp` (mismo código: `TLSMCPHelper.main()`).
        .executableTarget(name: "tls-mcp-dev", dependencies: ["TLSMCPShared"]),
        // F3 · puesta en marcha (PLAN §6.7): ventana, flujo y una vista por paso. El motor (`OnboardingEngine`) está en
        // TLSCore; aquí, la interfaz y el lanzador de Claude Code para el entrevistador (TLSAgents, en el sandbox).
        .target(
            name: "TLSOnboarding",
            dependencies: ["TLSCore", "TLSImport", "TLSDesign", "TLSUI", "TLSAgents"]
        ),
        // F4 · integración (PLAN §3.3: «App ── todos»): monta, por empresa abierta con escritor, el motor de los
        // asistentes, el servidor de herramientas y el chat de Mika con las piezas de la sesión, y lo para al cerrar o salir.
        .target(
            name: "TLSIntegracion",
            // F5 · integración: Mail, Calendario y permisos (TLSIntegrations) y otros programas (TLSGateway), por empresa.
            dependencies: ["TLSCore", "TLSAgents", "TLSMCPHost", "TLSMCPShared", "TLSUI", "TLSIntegrations", "TLSGateway",
                           .product(name: "MCP", package: "swift-sdk")]
        ),
        .executableTarget(
            name: "tls-tool",
            dependencies: [
                "TLSCore", "TLSImport",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "TLSCoreTests",
            dependencies: ["TLSCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "TLSImportTests",
            dependencies: ["TLSImport", "TLSCore"]
        ),
        .testTarget(
            name: "TLSUITests",
            dependencies: ["TLSUI", "TLSDesign", "TLSCore", "TLSImport", "TLSEditor", "TLSVisores", "TLSAgents"]
        ),
        .testTarget(name: "TLSEditorTests", dependencies: ["TLSEditor", "TLSDesign"]),
        .testTarget(name: "TLSVisoresTests", dependencies: ["TLSVisores", "TLSDesign"]),
        .testTarget(
            name: "TLSOnboardingTests",
            dependencies: ["TLSOnboarding", "TLSCore", "TLSAgents", "TLSDesign", "TLSImport", "TLSUI"]
        ),
        .testTarget(
            name: "TLSAgentsTests",
            dependencies: ["TLSAgents", "TLSCore"],
            resources: [.copy("Grabaciones")]
        ),
        .testTarget(
            name: "TLSMCPTests",
            dependencies: [
                "TLSMCPHost", "TLSMCPShared", "TLSCore", "TLSAgents", "tls-mcp-dev",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        // F4 · integración: los 10 criterios de aceptación de F4 (PLAN §9) de punta a punta, sin Claude de verdad.
        // F5/F6 · integración: los criterios de F5 y F6 y «una semana en la copia» (PLAN §10), con dobles de Mail,
        // EventKit y Llavero, un servidor de herramientas propio y carpetas sintéticas.
        .testTarget(
            name: "TLSIntegracionTests",
            dependencies: [
                "TLSIntegracion", "TLSUI", "TLSDesign", "TLSCore", "TLSAgents", "TLSMCPHost", "TLSMCPShared", "TLSOnboarding",
                "tls-mcp-dev", "TLSIntegrations", "TLSGateway", "TLSImport",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        // F5 · pasarela: con un servidor MCP de prueba propio (SDK Swift) dentro de las pruebas; nada se descarga.
        .testTarget(
            name: "TLSGatewayTests",
            dependencies: [
                "TLSGateway", "TLSMCPHost", "TLSMCPShared", "TLSCore",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        // F5 · núcleo: Mail, Calendario y permisos con dobles (nunca Mail, Calendario ni TCC de verdad).
        .testTarget(
            name: "TLSIntegrationsTests",
            dependencies: [
                "TLSIntegrations", "TLSCore", "TLSAgents", "TLSMCPHost", "TLSMCPShared",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .testTarget(
            name: "ConformidadTests",
            dependencies: ["TLSImport", "TLSCore"],
            path: "Tests/Conformidad",
            exclude: ["Casos"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
