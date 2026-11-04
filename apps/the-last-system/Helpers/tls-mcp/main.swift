import Foundation
import TLSMCPShared

// Binario auxiliar de los asistentes (PLAN §5.4): servidor MCP por stdio que reenvía cada herramienta a la app por
// el socket. No lee la carpeta. Toda la lógica está en `TLSMCPHelper` (TLSMCPShared) para poder probarla.
exit(await TLSMCPHelper.main())
