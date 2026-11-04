import Foundation
import TLSMCPShared

// Copia para pruebas del binario auxiliar `Helpers/tls-mcp` (el de la app lo compila Xcode y va firmado en
// `Contents/Helpers`). Mismo código: `TLSMCPHelper.main()`. Lo usan las pruebas de TLSMCPTests y `make sandbox`.
exit(await TLSMCPHelper.main())
