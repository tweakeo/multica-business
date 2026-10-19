package biz

import (
	"context"
	"crypto/sha256"
	"encoding/csv"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// parseAmount reads Spanish-formatted money ("1.234,56", "-80,00", "1234.56")
// into integer cents without going through floating point.
func parseAmount(raw string) (int64, error) {
	s := strings.TrimSpace(strings.ReplaceAll(raw, "€", ""))
	s = strings.ReplaceAll(s, " ", "")
	if s == "" {
		return 0, fmt.Errorf("importe vacío")
	}
	neg := false
	if strings.HasPrefix(s, "-") {
		neg, s = true, s[1:]
	} else if strings.HasPrefix(s, "+") {
		s = s[1:]
	}
	if strings.Contains(s, ",") {
		s = strings.ReplaceAll(s, ".", "")
		s = strings.Replace(s, ",", ".", 1)
	}
	whole, frac := s, ""
	if i := strings.IndexByte(s, '.'); i >= 0 {
		whole, frac = s[:i], s[i+1:]
	}
	if len(frac) > 2 {
		return 0, fmt.Errorf("importe con más de dos decimales: %s", raw)
	}
	for len(frac) < 2 {
		frac += "0"
	}
	w, err := strconv.ParseInt(whole, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("importe no válido: %s", raw)
	}
	fv, err := strconv.ParseInt(frac, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("importe no válido: %s", raw)
	}
	v := w*100 + fv
	if neg {
		v = -v
	}
	return v, nil
}

func parseDate(raw string) (time.Time, error) {
	raw = strings.TrimSpace(raw)
	for _, layout := range []string{"02/01/2006", "2006-01-02", "02-01-2006", "2/1/2006"} {
		if t, err := time.Parse(layout, raw); err == nil {
			return t, nil
		}
	}
	return time.Time{}, fmt.Errorf("fecha no válida: %s", raw)
}

var classifyRules = []struct {
	re       *regexp.Regexp
	nature   string
	category string
}{
	{regexp.MustCompile(`(?i)traspaso|transferencia interna`), "internal_transfer", "Traspaso entre cuentas"},
	{regexp.MustCompile(`(?i)aeat|hacienda|modelo \d{3}|tgss|seguridad social`), "tax", "Impuestos y cotizaciones"},
	{regexp.MustCompile(`(?i)n[oó]mina`), "payroll", "Nóminas"},
	{regexp.MustCompile(`(?i)retirada socio|disposici[oó]n titular`), "owner_withdrawal", "Retirada del titular"},
	{regexp.MustCompile(`(?i)pr[eé]stamo|cuota hipoteca`), "loan", "Préstamo"},
}

// ImportStatement ingests a bank CSV (documented in docs/tls/FORMATOS.md):
// fecha;fecha_valor;concepto;importe;saldo — semicolon separated, Spanish
// decimals. Re-importing the same file inserts nothing (import_hash).
func (s *Service) importStatement(ctx context.Context, tx pgx.Tx, ws, accountID, batch, content string) (map[string]any, error) {
	if err := requireRow(ctx, tx, ws, "account", accountID); err != nil {
		return nil, invalid("El movimiento necesita una cuenta bancaria válida (FIN-01)")
	}
	r := csv.NewReader(strings.NewReader(content))
	r.Comma = ';'
	r.FieldsPerRecord = -1
	r.TrimLeadingSpace = true
	inserted, duplicates, line := 0, 0, 0
	var errs []string
	for {
		rec, err := r.Read()
		if err == io.EOF {
			break
		}
		line++
		if err != nil {
			errs = append(errs, fmt.Sprintf("línea %d: %v", line, err))
			continue
		}
		if len(rec) < 4 || strings.EqualFold(strings.TrimSpace(rec[0]), "fecha") {
			continue
		}
		booked, err := parseDate(rec[0])
		if err != nil {
			errs = append(errs, fmt.Sprintf("línea %d: %v", line, err))
			continue
		}
		var valueOn any
		if v, err := parseDate(rec[1]); err == nil {
			valueOn = v
		}
		desc := strings.TrimSpace(rec[2])
		amount, err := parseAmount(rec[3])
		if err != nil {
			errs = append(errs, fmt.Sprintf("línea %d: %v", line, err))
			continue
		}
		var balance any
		balanceRaw := ""
		if len(rec) > 4 && strings.TrimSpace(rec[4]) != "" {
			if b, err := parseAmount(rec[4]); err == nil {
				balance, balanceRaw = b, strconv.FormatInt(b, 10)
			}
		}
		sum := sha256.Sum256([]byte(fmt.Sprintf("%s|%s|%d|%s|%s", accountID, booked.Format("2006-01-02"), amount, strings.ToLower(desc), balanceRaw)))
		nature, category := "unclassified", ""
		for _, rule := range classifyRules {
			if rule.re.MatchString(desc) {
				nature, category = rule.nature, rule.category
				break
			}
		}
		if nature == "unclassified" {
			if amount > 0 {
				nature = "operating_income"
			} else {
				nature = "operating_expense"
			}
		}
		tag, err := tx.Exec(ctx, `INSERT INTO biz_bank_movement (workspace_id, account_id, booked_on, value_on, amount_minor, description, counterparty,
				balance_after_minor, import_hash, import_batch, nature, category)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) ON CONFLICT (account_id, import_hash) DO NOTHING`,
			ws, accountID, booked, valueOn, amount, desc, counterparty(desc), balance, hex.EncodeToString(sum[:]), batch, nature, category)
		if err != nil {
			return nil, err
		}
		if tag.RowsAffected() == 1 {
			inserted++
		} else {
			duplicates++
		}
	}
	proposed, err := s.proposeMatches(ctx, tx, ws)
	if err != nil {
		return nil, err
	}
	rows, _ := tx.Query(ctx, `SELECT id FROM biz_bank_movement WHERE workspace_id=$1 AND import_batch=$2`, ws, batch)
	var ids []string
	for rows.Next() {
		var id string
		_ = rows.Scan(&id)
		ids = append(ids, id)
	}
	rows.Close()
	for _, id := range ids {
		s.Folder.Journal(ctx, tx, ws, "movement", id)
	}
	return map[string]any{"entity_type": "account", "id": accountID, "inserted": inserted, "duplicates": duplicates, "proposed_matches": proposed, "errors": errs}, nil
}

func counterparty(desc string) string {
	for _, prefix := range []string{"TRANSFERENCIA DE ", "TRANSF. DE ", "RECIBO ", "PAGO A ", "TRANSFERENCIA A "} {
		if strings.HasPrefix(strings.ToUpper(desc), prefix) {
			rest := desc[len(prefix):]
			if i := strings.IndexAny(rest, ",-/"); i > 0 {
				rest = rest[:i]
			}
			return strings.TrimSpace(rest)
		}
	}
	return ""
}

// proposeMatches pairs unreconciled movements with open invoices when the
// amount is exact and the invoice number or the counterparty appears in the
// concept. Each invoice is proposed at most once, preferring the reference
// match and then the closest date. Proposals are never confirmations: a
// person (or an approved agent request) confirms.
func (s *Service) proposeMatches(ctx context.Context, tx pgx.Tx, ws string) (int, error) {
	type inv struct {
		id, direction, number, org string
		pending                    int64
		date                       time.Time
	}
	rows, err := tx.Query(ctx, `SELECT i.id::text, i.direction, coalesce(i.number,''), lower(coalesce(o.name,'')), i.total_minor - i.paid_minor, coalesce(i.issue_date, i.created_at::date)
		FROM biz_invoice i LEFT JOIN biz_organization o ON o.id=i.organization_id
		WHERE i.workspace_id=$1 AND i.status IN ('issued','partially_paid') AND i.total_minor - i.paid_minor <> 0
		AND NOT EXISTS (SELECT 1 FROM biz_bank_movement m WHERE m.invoice_id=i.id AND m.status='proposed')`, ws)
	if err != nil {
		return 0, err
	}
	var invoices []inv
	for rows.Next() {
		var x inv
		if err := rows.Scan(&x.id, &x.direction, &x.number, &x.org, &x.pending, &x.date); err != nil {
			rows.Close()
			return 0, err
		}
		invoices = append(invoices, x)
	}
	rows.Close()
	mrows, err := tx.Query(ctx, `SELECT id::text, amount_minor, lower(description), booked_on FROM biz_bank_movement WHERE workspace_id=$1 AND status='unreconciled' ORDER BY booked_on, created_at`, ws)
	if err != nil {
		return 0, err
	}
	type mov struct {
		id     string
		amount int64
		desc   string
		date   time.Time
	}
	var movs []mov
	for mrows.Next() {
		var m mov
		if err := mrows.Scan(&m.id, &m.amount, &m.desc, &m.date); err != nil {
			mrows.Close()
			return 0, err
		}
		movs = append(movs, m)
	}
	mrows.Close()
	used := map[string]bool{}
	proposed := 0
	for _, m := range movs {
		best, bestScore, reason := -1, -1<<62, ""
		for i, x := range invoices {
			if used[x.id] {
				continue
			}
			if !((m.amount > 0 && x.direction == "issued" && m.amount == x.pending) || (m.amount < 0 && x.direction == "received" && -m.amount == x.pending)) {
				continue
			}
			byNumber := x.number != "" && strings.Contains(m.desc, strings.ToLower(x.number))
			word := strings.Fields(x.org)
			byName := len(word) > 0 && len(word[0]) > 2 && strings.Contains(m.desc, word[0])
			if !byNumber && !byName {
				continue
			}
			days := int(m.date.Sub(x.date).Hours() / 24)
			if days < -3 {
				continue // money does not move long before the invoice exists
			}
			if days < 0 {
				days = -days
			}
			score := -days
			if byNumber {
				score += 10000
			}
			if score > bestScore {
				best, bestScore = i, score
				reason = map[bool]string{true: "Importe exacto y número de factura en el concepto", false: "Importe exacto, contraparte coincidente y fecha más próxima"}[byNumber]
			}
		}
		if best < 0 {
			continue
		}
		used[invoices[best].id] = true
		if _, err := tx.Exec(ctx, `UPDATE biz_bank_movement SET status='proposed', invoice_id=$2, match_reason=$3, version=version+1, updated_at=now() WHERE id=$1`,
			m.id, invoices[best].id, reason); err != nil {
			return 0, err
		}
		proposed++
	}
	return proposed, nil
}

// applyPayment records a confirmed payment, updates the invoice and emits
// cobro.confirmado once the issued invoice is fully paid.
func (s *Service) applyPayment(ctx context.Context, tx pgx.Tx, ws string, a Actor, invoiceID string, amount int64, paidOn time.Time, method, evidence, movementID string) (json.RawMessage, error) {
	var direction, status string
	var total, paid int64
	var oppID *string
	if err := tx.QueryRow(ctx, `SELECT direction, status, total_minor, paid_minor, opportunity_id::text FROM biz_invoice WHERE id=$1 AND workspace_id=$2 FOR UPDATE`,
		invoiceID, ws).Scan(&direction, &status, &total, &paid, &oppID); err != nil {
		return nil, errf(404, "not_found", "Factura no encontrada")
	}
	if status != "issued" && status != "partially_paid" {
		return nil, invalid("Solo se cobran o pagan facturas emitidas (estado actual: %s)", status)
	}
	if amount <= 0 || paid+amount > total {
		return nil, invalid("Importe %s fuera del pendiente %s", eur(amount), eur(total-paid))
	}
	var row json.RawMessage
	if err := tx.QueryRow(ctx, `INSERT INTO biz_payment (workspace_id, invoice_id, amount_minor, paid_on, method, status, movement_id, evidence, confirmed_by_type, confirmed_by_id, confirmed_at)
		VALUES ($1,$2,$3,$4,$5,'confirmed',$6,$7,$8,$9, now()) RETURNING to_jsonb(biz_payment.*)`,
		ws, invoiceID, amount, paidOn, method, nullable(movementID), evidence, a.Type, nullable(a.UserID)).Scan(&row); err != nil {
		return nil, err
	}
	newPaid := paid + amount
	newStatus := "partially_paid"
	if newPaid == total {
		newStatus = "paid"
	}
	if _, err := tx.Exec(ctx, `UPDATE biz_invoice SET paid_minor=$3, status=$4, version=version+1, updated_at=now() WHERE id=$1 AND workspace_id=$2`, invoiceID, ws, newPaid, newStatus); err != nil {
		return nil, err
	}
	paymentID := str(entityResult("payment", row)["id"])
	if movementID != "" {
		if _, err := tx.Exec(ctx, `UPDATE biz_bank_movement SET status='reconciled', invoice_id=$3, payment_id=$4, version=version+1, updated_at=now() WHERE id=$1 AND workspace_id=$2`,
			movementID, ws, invoiceID, paymentID); err != nil {
			return nil, err
		}
		s.Folder.Journal(ctx, tx, ws, "movement", movementID)
	}
	if direction == "issued" && newStatus == "paid" {
		if err := s.Emit(ctx, tx, ws, "cobro.confirmado", "invoice", invoiceID, "paid:"+invoiceID, map[string]any{
			"invoice_id": invoiceID, "opportunity_id": deref(oppID), "payment_id": paymentID,
		}); err != nil {
			return nil, err
		}
	}
	s.Folder.Journal(ctx, tx, ws, "invoice", invoiceID)
	s.Folder.Journal(ctx, tx, ws, "payment", paymentID)
	return row, nil
}

func quarterOf(t time.Time) (int, int) { return t.Year(), (int(t.Month())-1)/3 + 1 }

func quarterRange(year, q int) (time.Time, time.Time) {
	start := time.Date(year, time.Month((q-1)*3+1), 1, 0, 0, 0, 0, time.UTC)
	return start, start.AddDate(0, 3, 0)
}

// nextInvoiceNumber allocates F-YYYY-NNNN, serialised by the row lock on the
// per-year counter setting.
func nextInvoiceNumber(ctx context.Context, tx pgx.Tx, ws string, year int) (string, error) {
	key := fmt.Sprintf("invoice_counter_%d", year)
	var n int
	err := tx.QueryRow(ctx, `INSERT INTO biz_setting (workspace_id, key, value) VALUES ($1,$2,'1'::jsonb)
		ON CONFLICT (workspace_id, key) DO UPDATE SET value=to_jsonb((biz_setting.value::text)::int + 1), updated_at=now()
		RETURNING (value::text)::int`, ws, key).Scan(&n)
	return fmt.Sprintf("F-%d-%04d", year, n), err
}

func (s *Service) registerFinance() {
	s.register(&Command{
		Action: "account.create", Capability: "FIN-01", Area: "finanzas",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				Name                string `json:"name"`
				IbanMasked          string `json:"iban_masked"`
				OpeningBalanceMinor *int64 `json:"opening_balance_minor"`
				OpeningOn           string `json:"opening_on"`
			}](p)
			if err != nil {
				return nil, err
			}
			if in.Name == "" {
				return nil, invalid("La cuenta necesita nombre")
			}
			var row json.RawMessage
			if err := tx.QueryRow(ctx, `INSERT INTO biz_bank_account (workspace_id, name, iban_masked, opening_balance_minor, opening_on)
				VALUES ($1,$2,$3,$4,$5) RETURNING to_jsonb(biz_bank_account.*)`, ws, in.Name, in.IbanMasked, in.OpeningBalanceMinor, nullable(in.OpeningOn)).Scan(&row); err != nil {
				return nil, err
			}
			res := entityResult("account", row)
			s.Folder.Journal(ctx, tx, ws, "account", str(res["id"]))
			return res, nil
		},
	})

	s.register(&Command{
		Action: "invoice.draft", Capability: "FIN-02", Area: "finanzas",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				OpportunityID string `json:"opportunity_id"`
			}](p)
			if err != nil {
				return nil, err
			}
			return s.draftInvoiceFromOpportunity(ctx, tx, ws, in.OpportunityID)
		},
	})

	s.register(&Command{
		Action: "invoice.issue", Capability: "FIN-02", Area: "finanzas", Sensitive: always(true),
		Describe: func(ctx context.Context, s *Service, ws string, p json.RawMessage) Description {
			var in struct {
				ID string `json:"id"`
			}
			_ = json.Unmarshal(p, &in)
			m, _ := rowMap(ctx, s.Pool, "invoice", in.ID)
			total, _ := m["total_minor"].(float64)
			return Description{Title: "Emitir factura por " + eur(int64(total)), Summary: "Se asigna número, fecha de emisión y vencimiento. Una factura emitida ya no se edita: se rectifica.",
				EntityType: "invoice", EntityID: in.ID, Effects: []Effect{{Field: "estado", Before: str(m["status"]), After: "issued"}, {Field: "total", After: eur(int64(total))}}}
		},
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				ID        string `json:"id"`
				IssueDate string `json:"issue_date"`
			}](p)
			if err != nil {
				return nil, err
			}
			var status string
			var terms int
			var total int64
			if err := tx.QueryRow(ctx, `SELECT status, payment_terms_days, total_minor FROM biz_invoice WHERE id=$1 AND workspace_id=$2 AND direction='issued' FOR UPDATE`, in.ID, ws).Scan(&status, &terms, &total); err != nil {
				return nil, errf(404, "not_found", "Factura emitible no encontrada")
			}
			if status != "draft" {
				return nil, invalid("Solo se emiten borradores (estado actual: %s)", status)
			}
			if total <= 0 {
				return nil, invalid("La factura no tiene importe")
			}
			issue := today()
			if in.IssueDate != "" {
				if issue, err = parseDate(in.IssueDate); err != nil {
					return nil, invalid("%v", err)
				}
			}
			number, err := nextInvoiceNumber(ctx, tx, ws, issue.Year())
			if err != nil {
				return nil, err
			}
			var row json.RawMessage
			if err := tx.QueryRow(ctx, `UPDATE biz_invoice SET status='issued', number=$3, issue_date=$4, due_date=$5, version=version+1, updated_at=now()
				WHERE id=$1 AND workspace_id=$2 RETURNING to_jsonb(biz_invoice.*)`, in.ID, ws, number, issue, issue.AddDate(0, 0, terms)).Scan(&row); err != nil {
				return nil, err
			}
			if err := s.Emit(ctx, tx, ws, "factura.emitida", "invoice", in.ID, "issued:"+in.ID, map[string]any{"number": number}); err != nil {
				return nil, err
			}
			s.Folder.Journal(ctx, tx, ws, "invoice", in.ID)
			return entityResult("invoice", row), nil
		},
	})

	s.register(&Command{
		Action: "invoice.received", Capability: "FIN-08", Area: "finanzas",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				OrganizationID   string `json:"organization_id"`
				SupplierName     string `json:"supplier_name"`
				Number           string `json:"number"`
				IssueDate        string `json:"issue_date"`
				DueDate          string `json:"due_date"`
				Concept          string `json:"concept"`
				BaseMinor        int64  `json:"base_minor"`
				TaxMinor         int64  `json:"tax_minor"`
				WithholdingMinor int64  `json:"withholding_minor"`
				Category         string `json:"category"`
				Nature           string `json:"nature"`
				DocumentPath     string `json:"document_path"`
			}](p)
			if err != nil {
				return nil, err
			}
			if in.Number == "" || in.IssueDate == "" {
				return nil, invalid("La factura recibida necesita número y fecha")
			}
			issue, err := parseDate(in.IssueDate)
			if err != nil {
				return nil, invalid("%v", err)
			}
			orgID := in.OrganizationID
			if orgID == "" {
				if in.SupplierName == "" {
					return nil, invalid("Indica el proveedor")
				}
				_ = tx.QueryRow(ctx, `SELECT id FROM biz_organization WHERE workspace_id=$1 AND lower(name)=lower($2)`, ws, in.SupplierName).Scan(&orgID)
				if orgID == "" {
					if err := tx.QueryRow(ctx, `INSERT INTO biz_organization (workspace_id, name, kind) VALUES ($1,$2,'supplier') RETURNING id`, ws, in.SupplierName).Scan(&orgID); err != nil {
						return nil, err
					}
					s.Folder.Journal(ctx, tx, ws, "organization", orgID)
				}
			}
			nature := in.Nature
			if nature == "" {
				nature = "operating"
			}
			due := any(nil)
			if in.DueDate != "" {
				if d, err := parseDate(in.DueDate); err == nil {
					due = d
				}
			}
			lines, _ := json.Marshal([]map[string]any{{"concept": in.Concept, "base_minor": in.BaseMinor}})
			var row json.RawMessage
			if err := tx.QueryRow(ctx, `INSERT INTO biz_invoice (workspace_id, direction, number, status, organization_id, issue_date, due_date, lines,
					base_minor, tax_minor, withholding_minor, total_minor, category, nature, notes)
				VALUES ($1,'received',$2,'issued',$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING to_jsonb(biz_invoice.*)`,
				ws, in.Number, orgID, issue, due, lines, in.BaseMinor, in.TaxMinor, in.WithholdingMinor, in.BaseMinor+in.TaxMinor-in.WithholdingMinor,
				in.Category, nature, in.Concept).Scan(&row); err != nil {
				return nil, invalid("No se pudo registrar (¿número repetido?): %v", err)
			}
			res := entityResult("invoice", row)
			if in.DocumentPath != "" {
				if err := s.attachDocument(ctx, tx, ws, "invoice", str(res["id"]), "justificante", in.Number, in.DocumentPath); err != nil {
					return nil, err
				}
			}
			s.Folder.Journal(ctx, tx, ws, "invoice", str(res["id"]))
			return res, nil
		},
	})

	// Confirming money is sensitive: an agent can only propose it, and a
	// customer's word is not evidence — a movement or a receipt is required.
	s.register(&Command{
		Action: "payment.confirm", Capability: "FIN-07", Area: "finanzas", Sensitive: always(true),
		Describe: func(ctx context.Context, s *Service, ws string, p json.RawMessage) Description {
			var in struct {
				InvoiceID   string `json:"invoice_id"`
				AmountMinor int64  `json:"amount_minor"`
				MovementID  string `json:"movement_id"`
			}
			_ = json.Unmarshal(p, &in)
			m, _ := rowMap(ctx, s.Pool, "invoice", in.InvoiceID)
			return Description{Title: fmt.Sprintf("Confirmar cobro de %s (%s)", eur(in.AmountMinor), str(m["number"])), Summary: "Marca el cobro como confirmado y, si completa la factura, dispara la creación del proyecto.",
				EntityType: "invoice", EntityID: in.InvoiceID, Effects: []Effect{{Field: "cobrado", Before: eur(int64(num(m["paid_minor"]))), After: eur(int64(num(m["paid_minor"])) + in.AmountMinor)}}}
		},
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				InvoiceID   string `json:"invoice_id"`
				AmountMinor int64  `json:"amount_minor"`
				PaidOn      string `json:"paid_on"`
				Method      string `json:"method"`
				Evidence    string `json:"evidence"`
				MovementID  string `json:"movement_id"`
			}](p)
			if err != nil {
				return nil, err
			}
			if in.MovementID == "" && strings.TrimSpace(in.Evidence) == "" {
				return nil, invalid("Un cobro se confirma con un movimiento bancario o un justificante, no con una frase del cliente")
			}
			paidOn := today()
			if in.PaidOn != "" {
				if paidOn, err = parseDate(in.PaidOn); err != nil {
					return nil, invalid("%v", err)
				}
			}
			if in.MovementID != "" {
				var amount int64
				var mstatus string
				var booked time.Time
				if err := tx.QueryRow(ctx, `SELECT amount_minor, status, booked_on FROM biz_bank_movement WHERE id=$1 AND workspace_id=$2 FOR UPDATE`, in.MovementID, ws).Scan(&amount, &mstatus, &booked); err != nil {
					return nil, invalid("Movimiento no encontrado")
				}
				if mstatus == "reconciled" {
					return nil, invalid("El movimiento ya está conciliado")
				}
				if amount < 0 {
					amount = -amount
				}
				if in.AmountMinor == 0 {
					in.AmountMinor = amount
				}
				paidOn = booked
			}
			if in.Method == "" {
				in.Method = "transferencia"
			}
			row, err := s.applyPayment(ctx, tx, ws, a, in.InvoiceID, in.AmountMinor, paidOn, in.Method, in.Evidence, in.MovementID)
			if err != nil {
				return nil, err
			}
			return entityResult("payment", row), nil
		},
	})

	s.register(&Command{
		Action: "bank.import", Capability: "FIN-07", Area: "finanzas",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				AccountID string `json:"account_id"`
				Batch     string `json:"batch"`
				CSV       string `json:"csv"`
			}](p)
			if err != nil {
				return nil, err
			}
			if in.Batch == "" {
				in.Batch = time.Now().Format("2006-01-02T15:04")
			}
			return s.importStatement(ctx, tx, ws, in.AccountID, in.Batch, in.CSV)
		},
	})

	s.register(&Command{
		Action: "movement.classify", Capability: "FIN-08", Area: "finanzas",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				ID       string `json:"id"`
				Nature   string `json:"nature"`
				Category string `json:"category"`
				Notes    string `json:"notes"`
				Ignore   bool   `json:"ignore"`
			}](p)
			if err != nil {
				return nil, err
			}
			var row json.RawMessage
			err = tx.QueryRow(ctx, `UPDATE biz_bank_movement SET nature=coalesce(nullif($3,''), nature), category=coalesce(nullif($4,''), category),
				notes=CASE WHEN $5<>'' THEN $5 ELSE notes END, status=CASE WHEN $6 THEN 'ignored' ELSE status END, version=version+1, updated_at=now()
				WHERE id=$1 AND workspace_id=$2 AND status<>'reconciled' RETURNING to_jsonb(biz_bank_movement.*)`, in.ID, ws, in.Nature, in.Category, in.Notes, in.Ignore).Scan(&row)
			if err != nil {
				return nil, invalid("Movimiento no encontrado o ya conciliado: %v", err)
			}
			s.Folder.Journal(ctx, tx, ws, "movement", in.ID)
			return entityResult("movement", row), nil
		},
	})

	s.register(&Command{
		Action: "movement.match", Capability: "FIN-07", Area: "finanzas",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				ID        string `json:"id"`
				InvoiceID string `json:"invoice_id"`
				Reject    bool   `json:"reject"`
			}](p)
			if err != nil {
				return nil, err
			}
			var row json.RawMessage
			if in.Reject {
				err = tx.QueryRow(ctx, `UPDATE biz_bank_movement SET status='unreconciled', invoice_id=NULL, match_reason='', version=version+1, updated_at=now()
					WHERE id=$1 AND workspace_id=$2 AND status='proposed' RETURNING to_jsonb(biz_bank_movement.*)`, in.ID, ws).Scan(&row)
			} else {
				if err := requireRow(ctx, tx, ws, "invoice", in.InvoiceID); err != nil {
					return nil, err
				}
				err = tx.QueryRow(ctx, `UPDATE biz_bank_movement SET status='proposed', invoice_id=$3, match_reason='Propuesta manual', version=version+1, updated_at=now()
					WHERE id=$1 AND workspace_id=$2 AND status IN ('unreconciled','proposed') RETURNING to_jsonb(biz_bank_movement.*)`, in.ID, ws, in.InvoiceID).Scan(&row)
			}
			if err != nil {
				return nil, invalid("Movimiento no disponible para conciliar")
			}
			s.Folder.Journal(ctx, tx, ws, "movement", in.ID)
			return entityResult("movement", row), nil
		},
	})

	s.register(&Command{
		Action: "period.prepare", Capability: "FIN-09", Area: "finanzas",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				Year    int `json:"year"`
				Quarter int `json:"quarter"`
			}](p)
			if err != nil {
				return nil, err
			}
			return s.preparePeriod(ctx, tx, ws, in.Year, in.Quarter)
		},
	})

	s.register(&Command{
		Action: "period.transition", Capability: "FIN-09", Area: "finanzas",
		Sensitive: func(p json.RawMessage) bool {
			var in struct {
				To string `json:"to"`
			}
			_ = json.Unmarshal(p, &in)
			return in.To != "prepared"
		},
		Describe: func(ctx context.Context, s *Service, ws string, p json.RawMessage) Description {
			var in struct{ ID, To, Evidence string }
			_ = json.Unmarshal(p, &in)
			m, _ := rowMap(ctx, s.Pool, "period", in.ID)
			return Description{Title: fmt.Sprintf("Trimestre %v T%v → %s", m["year"], m["quarter"], periodLabel(in.To)), Summary: in.Evidence,
				EntityType: "period", EntityID: in.ID, Effects: []Effect{{Field: "estado", Before: periodLabel(str(m["status"])), After: periodLabel(in.To)}}}
		},
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				ID       string `json:"id"`
				To       string `json:"to"`
				Evidence string `json:"evidence"`
				Reason   string `json:"reason"`
			}](p)
			if err != nil {
				return nil, err
			}
			return s.transitionPeriod(ctx, tx, ws, a, in.ID, in.To, in.Evidence, in.Reason)
		},
	})
}

func num(v any) float64 {
	switch n := v.(type) {
	case float64:
		return n
	case int64:
		return float64(n)
	case int:
		return float64(n)
	case json.Number:
		f, _ := n.Float64()
		return f
	}
	return 0
}

func (s *Service) draftInvoiceFromOpportunity(ctx context.Context, tx pgx.Tx, ws, oppID string) (map[string]any, error) {
	var proposal json.RawMessage
	var orgID, title string
	if err := tx.QueryRow(ctx, `SELECT proposal, coalesce(organization_id::text,''), title FROM biz_opportunity WHERE id=$1 AND workspace_id=$2`, oppID, ws).Scan(&proposal, &orgID, &title); err != nil {
		return nil, errf(404, "not_found", "Oportunidad no encontrada")
	}
	if len(proposal) == 0 || string(proposal) == "null" {
		return nil, invalid("Sin propuesta aceptada no hay precio que facturar")
	}
	var existing json.RawMessage
	if err := tx.QueryRow(ctx, `SELECT to_jsonb(i) FROM biz_invoice i WHERE workspace_id=$1 AND opportunity_id=$2 AND direction='issued' AND status<>'void' LIMIT 1`, ws, oppID).Scan(&existing); err == nil {
		return entityResult("invoice", existing), nil
	}
	var snap struct {
		Service          string `json:"service"`
		Quantity         int    `json:"quantity"`
		UnitPriceMinor   int64  `json:"unit_price_minor"`
		BaseMinor        int64  `json:"base_minor"`
		TaxMinor         int64  `json:"tax_minor"`
		WithholdingMinor int64  `json:"withholding_minor"`
		TotalMinor       int64  `json:"total_minor"`
		Conditions       string `json:"conditions"`
		OfferVersion     int    `json:"offer_version"`
	}
	_ = json.Unmarshal(proposal, &snap)
	lines, _ := json.Marshal([]map[string]any{{
		"concept": snap.Service, "quantity": snap.Quantity, "unit_price_minor": snap.UnitPriceMinor, "base_minor": snap.BaseMinor,
		"offer_version": snap.OfferVersion, "conditions": snap.Conditions,
	}})
	var row json.RawMessage
	if err := tx.QueryRow(ctx, `INSERT INTO biz_invoice (workspace_id, direction, status, organization_id, opportunity_id, lines, base_minor, tax_minor, withholding_minor, total_minor, category, notes)
		VALUES ($1,'issued','draft',$2,$3,$4,$5,$6,$7,$8,'Servicios',$9) RETURNING to_jsonb(biz_invoice.*)`,
		ws, nullable(orgID), oppID, lines, snap.BaseMinor, snap.TaxMinor, snap.WithholdingMinor, snap.TotalMinor, "Desde propuesta: "+title).Scan(&row); err != nil {
		return nil, err
	}
	res := entityResult("invoice", row)
	s.Folder.Journal(ctx, tx, ws, "invoice", str(res["id"]))
	return res, nil
}

var periodOrder = []string{"open", "prepared", "approved", "sent", "filed", "archived", "settled"}

func periodLabel(s string) string {
	return map[string]string{"open": "abierto", "prepared": "preparado", "approved": "aprobado para envío", "sent": "enviado",
		"filed": "presentado con justificante", "archived": "justificantes archivados", "settled": "liquidación verificada", "not_applicable": "no aplica"}[s]
}

func (s *Service) transitionPeriod(ctx context.Context, tx pgx.Tx, ws string, a Actor, id, to, evidence, reason string) (any, error) {
	var status string
	var history json.RawMessage
	if err := tx.QueryRow(ctx, `SELECT status, history FROM biz_period WHERE id=$1 AND workspace_id=$2 FOR UPDATE`, id, ws).Scan(&status, &history); err != nil {
		return nil, errf(404, "not_found", "Periodo no encontrado")
	}
	idx := func(st string) int {
		for i, x := range periodOrder {
			if x == st {
				return i
			}
		}
		return -1
	}
	switch {
	case to == "open":
		if strings.TrimSpace(reason) == "" {
			return nil, invalid("Reabrir un periodo exige motivo")
		}
	case to == "not_applicable":
		if status != "filed" && status != "archived" {
			return nil, invalid("«No aplica» solo tras presentar")
		}
	case idx(to) != idx(status)+1:
		return nil, invalid("Del estado %s solo se pasa a %s", periodLabel(status), periodLabel(periodOrder[min(idx(status)+1, len(periodOrder)-1)]))
	}
	if (to == "sent" || to == "filed" || to == "settled") && strings.TrimSpace(evidence) == "" {
		return nil, invalid("El paso a %s exige evidencia (justificante, número de registro o referencia)", periodLabel(to))
	}
	var h []map[string]any
	_ = json.Unmarshal(history, &h)
	h = append(h, map[string]any{"from": status, "to": to, "at": time.Now().UTC(), "by": a.Type + ":" + a.ID, "evidence": evidence, "reason": reason})
	hb, _ := json.Marshal(h)
	var row json.RawMessage
	if err := tx.QueryRow(ctx, `UPDATE biz_period SET status=$3, history=$4, evidence=CASE WHEN $5<>'' THEN $5 ELSE evidence END, version=version+1, updated_at=now()
		WHERE id=$1 AND workspace_id=$2 RETURNING to_jsonb(biz_period.*)`, id, ws, to, hb, evidence).Scan(&row); err != nil {
		return nil, err
	}
	s.Folder.Journal(ctx, tx, ws, "period", id)
	return entityResult("period", row), nil
}

// preparePeriod builds the quarterly package: books with traceability to
// every operation, the exception list and an index for the tax adviser. It
// prepares documentation only; it computes no official return.
func (s *Service) preparePeriod(ctx context.Context, tx pgx.Tx, ws string, year, quarter int) (any, error) {
	if quarter < 1 || quarter > 4 || year < 2000 {
		return nil, invalid("Periodo no válido")
	}
	start, end := quarterRange(year, quarter)
	var periodID, status string
	if err := tx.QueryRow(ctx, `INSERT INTO biz_period (workspace_id, year, quarter) VALUES ($1,$2,$3)
		ON CONFLICT (workspace_id, year, quarter) DO UPDATE SET updated_at=now() RETURNING id, status`, ws, year, quarter).Scan(&periodID, &status); err != nil {
		return nil, err
	}
	if status != "open" && status != "prepared" {
		return nil, invalid("El periodo está %s; reábrelo con motivo para volver a prepararlo", periodLabel(status))
	}
	type sums struct{ Base, Tax, Wh, Total, Count int64 }
	var issued, received sums
	if err := tx.QueryRow(ctx, `SELECT coalesce(sum(base_minor),0), coalesce(sum(tax_minor),0), coalesce(sum(withholding_minor),0), coalesce(sum(total_minor),0), count(*)
		FROM biz_invoice WHERE workspace_id=$1 AND direction='issued' AND status NOT IN ('draft','void') AND issue_date >= $2 AND issue_date < $3`, ws, start, end).
		Scan(&issued.Base, &issued.Tax, &issued.Wh, &issued.Total, &issued.Count); err != nil {
		return nil, err
	}
	if err := tx.QueryRow(ctx, `SELECT coalesce(sum(base_minor),0), coalesce(sum(tax_minor),0), coalesce(sum(withholding_minor),0), coalesce(sum(total_minor),0), count(*)
		FROM biz_invoice WHERE workspace_id=$1 AND direction='received' AND status<>'void' AND issue_date >= $2 AND issue_date < $3`, ws, start, end).
		Scan(&received.Base, &received.Tax, &received.Wh, &received.Total, &received.Count); err != nil {
		return nil, err
	}
	var unreconciled, unclassified, movements int64
	_ = tx.QueryRow(ctx, `SELECT count(*) FILTER (WHERE status IN ('unreconciled','proposed') AND nature IN ('operating_income','operating_expense')),
		count(*) FILTER (WHERE nature='unclassified'), count(*) FROM biz_bank_movement WHERE workspace_id=$1 AND booked_on >= $2 AND booked_on < $3`, ws, start, end).
		Scan(&unreconciled, &unclassified, &movements)
	var missingReceipts int64
	_ = tx.QueryRow(ctx, `SELECT count(*) FROM biz_invoice i WHERE i.workspace_id=$1 AND i.direction='received' AND i.issue_date >= $2 AND i.issue_date < $3
		AND NOT EXISTS (SELECT 1 FROM biz_document d WHERE d.entity_type='invoice' AND d.entity_id=i.id)`, ws, start, end).Scan(&missingReceipts)
	var expensesWithoutInvoice int64
	_ = tx.QueryRow(ctx, `SELECT count(*) FROM biz_bank_movement WHERE workspace_id=$1 AND booked_on >= $2 AND booked_on < $3 AND amount_minor < 0
		AND nature='operating_expense' AND invoice_id IS NULL AND status<>'ignored'`, ws, start, end).Scan(&expensesWithoutInvoice)

	exceptions := []map[string]any{}
	add := func(kind, msg string, n int64) {
		if n > 0 {
			exceptions = append(exceptions, map[string]any{"kind": kind, "message": msg, "count": n})
		}
	}
	add("unreconciled", "Movimientos operativos sin conciliar", unreconciled)
	add("unclassified", "Movimientos sin clasificar", unclassified)
	add("missing_receipt", "Facturas recibidas sin justificante adjunto", missingReceipts)
	add("expense_without_invoice", "Pagos sin factura recibida asociada", expensesWithoutInvoice)

	summary := map[string]any{
		"period": fmt.Sprintf("%d-T%d", year, quarter), "from": start.Format("2006-01-02"), "to": end.AddDate(0, 0, -1).Format("2006-01-02"),
		"issued":   map[string]int64{"count": issued.Count, "base_minor": issued.Base, "tax_minor": issued.Tax, "withholding_minor": issued.Wh, "total_minor": issued.Total},
		"received": map[string]int64{"count": received.Count, "base_minor": received.Base, "tax_minor": received.Tax, "withholding_minor": received.Wh, "total_minor": received.Total},
		"movements": movements, "exceptions": exceptions, "ready": len(exceptions) == 0,
		"note": "Documentación preparada para la gestoría. No es una declaración oficial ni calcula importes a ingresar; el asesor valida y presenta.",
	}
	sb, _ := json.Marshal(summary)
	rel := fmt.Sprintf("Finanzas/%d/T%d/Paquete gestoría", year, quarter)
	var row json.RawMessage
	if err := tx.QueryRow(ctx, `UPDATE biz_period SET status='prepared', summary=$3, package_path=$4, version=version+1, updated_at=now()
		WHERE id=$1 AND workspace_id=$2 RETURNING to_jsonb(biz_period.*)`, periodID, ws, sb, rel).Scan(&row); err != nil {
		return nil, err
	}
	if err := s.Emit(ctx, tx, ws, "periodo.preparado", "period", periodID, fmt.Sprintf("period-prepared:%s:%d", periodID, time.Now().Unix()), map[string]any{"year": year, "quarter": quarter, "path": rel}); err != nil {
		return nil, err
	}
	s.Folder.Journal(ctx, tx, ws, "period", periodID)
	return entityResult("period", row), nil
}
