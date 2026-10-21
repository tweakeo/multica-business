package biz

import (
	"context"
	"strings"
	"testing"
)

// Fictitious ledger in the shape of Registros/importar/*.csv: «importe» is
// before tax, so the money that moved is importe + IVA − retención; refunds
// with negative tax and drafts are reported, never guessed.
const ledgerCSV = `id,fecha,fecha_factura,concepto,importe,tipo,tipo_fiscal,categoria,naturaleza,recurrencia,iva,retencion_irpf,numero_factura,justificante,cuenta_nombre,proyecto_nombre,factura_numero
mv-1,2026-01-08,2026-01-05,F-1 — Cliente Uno (enero),1000.00,Ingreso,ingreso,Consultoría,,Único,210.00,70.00,F-1,,Cuenta,,
mv-2,2026-01-20,2026-01-20,Proveedor Dos — cuota,-30.00,Gasto,estandar,Software,Fijo,Mensual,6.30,,P-2,,Cuenta,,
mv-3,2026-03-24,2026-03-24,Proveedor Tres — reembolso,-50.00,Gasto,rectificativa,,,,-10.50,,,,Cuenta,,
mv-4,2026-07-24,2026-06-10,"BORRADOR (plantilla, dato de muestra)",2500.00,Ingreso,borrador,Proyecto,,Único,525.00,175.00,Borrador,,Cuenta,,
mv-5,2026-04-20,2026-04-20,Metro — 10 viajes (no incluido),-9.91,Gasto,borrador,Transporte,,Único,0.99,,X,,Cuenta,,
`

func TestParseStatementLedgerAndBank(t *testing.T) {
	rows, errs := parseStatement(ledgerCSV)
	if len(errs) != 0 || len(rows) != 5 {
		t.Fatalf("rows %d errs %v", len(rows), errs)
	}
	want := map[string]struct {
		amount int64
		skip   bool
	}{"mv-1": {114000, false}, "mv-2": {-3630, false}, "mv-3": {0, true}, "mv-4": {0, true}, "mv-5": {-1090, false}}
	for _, r := range rows {
		w := want[r.ExtID]
		if (r.Skip != "") != w.skip || (!w.skip && r.Amount != w.amount) {
			t.Errorf("%s: amount %d skip %q", r.ExtID, r.Amount, r.Skip)
		}
	}
	if rows[0].Line != 2 || rows[0].Hash("a") != rows[0].Hash("b") {
		t.Error("a row with its own id is identified by it, whatever the account")
	}

	bank, errs := parseStatement("01/10/2026;01/10/2026;RECIBO ALQUILER;-663,00;1.200,50\n")
	if len(errs) != 0 || len(bank) != 1 || bank[0].Amount != -66300 || bank[0].Balance == nil || *bank[0].Balance != 120050 {
		t.Fatalf("bank format: %+v %v", bank, errs)
	}
	if bank[0].Hash("a") == bank[0].Hash("b") {
		t.Error("a bank line without id is identified per account")
	}
}

// An invoice that exists as a document is recorded with its own number and
// the amounts read from it; an unknown amount keeps it out of the app. The
// ledger import proposes the match and «Bases de datos» shows both as done.
func TestRegisteredInvoicesAndLedgerImport(t *testing.T) {
	f := newFixture(t)
	dir := t.TempDir()
	writeFile(t, dir, ".tls/layout.json", `{"preset": "humana"}`)
	writeFile(t, dir, "4 · Finanzas/Fiscal/2026/T1/Ingresos/F-1 Cliente Uno.pdf", "%PDF")
	writeFile(t, dir, "4 · Finanzas/Registros/importar/2026 T1 movimientos.csv", ledgerCSV)
	f.must(owner, "settings.set", map[string]any{"key": "company_folder", "value": dir})

	base := map[string]any{"direction": "issued", "number": "F-1", "issue_date": "2026-01-05", "party": "Cliente Uno", "registro_id": "EMI-1",
		"base_minor": 100000, "tax_minor": 21000, "withholding_minor": 7000, "document_path": "4 · Finanzas/Fiscal/2026/T1/Ingresos/F-1 Cliente Uno.pdf"}
	unknown := map[string]any{}
	for k, v := range base {
		unknown[k] = v
	}
	if _, err := f.run(owner, "invoice.register", unknown); err == nil {
		t.Fatal("an invoice without its total was recorded")
	}
	base["total_minor"] = 114001
	if _, err := f.run(owner, "invoice.register", base); err == nil {
		t.Fatal("amounts that do not add up were recorded")
	}
	base["total_minor"] = 114000
	inv := f.must(owner, "invoice.register", base)
	if again := f.must(owner, "invoice.register", base); again["id"] != inv["id"] {
		t.Fatal("registering the same register id twice created two invoices")
	}

	acc := f.must(owner, "account.create", map[string]any{"name": "Cuenta"})
	res := f.must(owner, "bank.import", map[string]any{"account_id": acc["id"], "batch": "importar/2026 T1 movimientos.csv", "csv": ledgerCSV})
	if res["inserted"] != 3 || len(res["skipped"].([]map[string]any)) != 2 || res["proposed_matches"] != 1 {
		t.Fatalf("import: %v", res)
	}
	if again := f.must(owner, "bank.import", map[string]any{"account_id": acc["id"], "csv": ledgerCSV}); again["inserted"] != 0 {
		t.Fatalf("re-import duplicated movements: %v", again)
	}

	ctx := context.Background()
	f.s.Folder.FlushPending(ctx, f.ws) // the register row comes from the journal
	rd, err := f.s.newDBReader(ctx, f.ws, owner)
	if err != nil {
		t.Fatal(err)
	}
	status := map[string]int{}
	for _, r := range append(rd.facturas(), rd.pagos()...) {
		if strings.HasPrefix(r.Origin, "PDF") || strings.HasPrefix(r.Origin, "Extracto") {
			status[r.Status]++
		}
	}
	if status["Registrada"] != 1 || status["Importado"] != 3 || status["No importable"] != 2 || status["Sin registrar"]+status["Por importar"] != 0 {
		t.Fatalf("statuses: %v", status)
	}
}
