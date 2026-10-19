-- TLS business layer ("Empresa"): areas, CRM, offers, finance, brand,
-- direction, approvals, durable events and audit. Fork-only extension; every
-- table is prefixed biz_ and workspace-scoped (workspace = company).
--
-- Deviation from the upstream index rule, recorded deliberately: these tables
-- are created empty in a single migration, so their primary keys and the
-- idempotency UNIQUE constraints are declared inline instead of through
-- separate CONCURRENTLY migrations. There is no live data to lock.
--
-- No foreign keys (project rule): relationships are validated in
-- server/internal/biz. Money is stored in integer minor units (cents).
-- Calendar dates are DATE; instants are TIMESTAMPTZ.

CREATE TABLE IF NOT EXISTS biz_setting (
    workspace_id UUID NOT NULL,
    key TEXT NOT NULL,
    value JSONB NOT NULL DEFAULT 'null'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (workspace_id, key)
);

CREATE TABLE IF NOT EXISTS biz_area (
    workspace_id UUID NOT NULL,
    code TEXT NOT NULL CHECK (code IN ('direccion','ventas','entrega','finanzas','marca','equipo')),
    enabled BOOLEAN NOT NULL DEFAULT true,
    paused BOOLEAN NOT NULL DEFAULT false,
    owner_role_id UUID,
    note TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (workspace_id, code)
);

CREATE TABLE IF NOT EXISTS biz_role (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    area TEXT NOT NULL,
    name TEXT NOT NULL,
    mission TEXT NOT NULL DEFAULT '',
    decisions TEXT NOT NULL DEFAULT '',
    limits TEXT NOT NULL DEFAULT '',
    kpi_codes TEXT[] NOT NULL DEFAULT '{}',
    manual TEXT NOT NULL DEFAULT '',
    occupant_type TEXT CHECK (occupant_type IN ('member','agent')),
    occupant_id UUID,
    attrs JSONB NOT NULL DEFAULT '{}'::jsonb,
    version INT NOT NULL DEFAULT 1,
    archived_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Area assignment and limits for Multica agents acting as business executors.
CREATE TABLE IF NOT EXISTS biz_agent (
    agent_id UUID NOT NULL PRIMARY KEY,
    workspace_id UUID NOT NULL,
    area TEXT NOT NULL,
    role_id UUID,
    is_coordinator BOOLEAN NOT NULL DEFAULT false,
    budget_monthly_minor BIGINT NOT NULL DEFAULT 0 CHECK (budget_monthly_minor >= 0),
    max_delegation_depth INT NOT NULL DEFAULT 2 CHECK (max_delegation_depth BETWEEN 0 AND 5),
    max_steps INT NOT NULL DEFAULT 20 CHECK (max_steps > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- A service line (product). Each one owns its delivery canvas: a Multica
-- issue_workflow plus a versioned project template.
CREATE TABLE IF NOT EXISTS biz_service (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    recurrence TEXT NOT NULL DEFAULT 'one_off' CHECK (recurrence IN ('one_off','monthly','quarterly','annual')),
    workflow_id UUID,
    template JSONB NOT NULL DEFAULT '{}'::jsonb,
    template_version INT NOT NULL DEFAULT 1,
    active BOOLEAN NOT NULL DEFAULT true,
    attrs JSONB NOT NULL DEFAULT '{}'::jsonb,
    version INT NOT NULL DEFAULT 1,
    archived_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (workspace_id, code)
);

CREATE TABLE IF NOT EXISTS biz_offer_version (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    service_id UUID NOT NULL,
    version INT NOT NULL,
    price_minor BIGINT NOT NULL CHECK (price_minor >= 0),
    currency TEXT NOT NULL DEFAULT 'EUR',
    tax_rate_bp INT NOT NULL DEFAULT 2100 CHECK (tax_rate_bp BETWEEN 0 AND 10000),
    withholding_bp INT NOT NULL DEFAULT 0 CHECK (withholding_bp BETWEEN 0 AND 10000),
    billing_unit TEXT NOT NULL DEFAULT 'servicio',
    conditions TEXT NOT NULL DEFAULT '',
    active BOOLEAN NOT NULL DEFAULT true,
    valid_from DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (service_id, version)
);

CREATE TABLE IF NOT EXISTS biz_organization (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    name TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'client' CHECK (kind IN ('prospect','client','supplier','partner','other')),
    legal_form TEXT NOT NULL DEFAULT '',
    tax_id TEXT NOT NULL DEFAULT '',
    sector TEXT NOT NULL DEFAULT '',
    city TEXT NOT NULL DEFAULT '',
    email TEXT NOT NULL DEFAULT '',
    phone TEXT NOT NULL DEFAULT '',
    source_channel TEXT NOT NULL DEFAULT '',
    source_content_id UUID,
    notes TEXT NOT NULL DEFAULT '',
    origin TEXT NOT NULL DEFAULT 'app',
    attrs JSONB NOT NULL DEFAULT '{}'::jsonb,
    version INT NOT NULL DEFAULT 1,
    archived_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS biz_contact (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    organization_id UUID,
    name TEXT NOT NULL,
    email TEXT NOT NULL DEFAULT '',
    phone TEXT NOT NULL DEFAULT '',
    position TEXT NOT NULL DEFAULT '',
    kind TEXT NOT NULL DEFAULT 'lead' CHECK (kind IN ('lead','client','supplier','partner','other')),
    source_channel TEXT NOT NULL DEFAULT '',
    source_content_id UUID,
    opted_out BOOLEAN NOT NULL DEFAULT false,
    last_contact_at TIMESTAMPTZ,
    notes TEXT NOT NULL DEFAULT '',
    origin TEXT NOT NULL DEFAULT 'app',
    attrs JSONB NOT NULL DEFAULT '{}'::jsonb,
    version INT NOT NULL DEFAULT 1,
    archived_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS biz_opportunity (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    title TEXT NOT NULL,
    contact_id UUID,
    organization_id UUID,
    service_id UUID,
    stage TEXT NOT NULL DEFAULT 'entrada' CHECK (stage IN (
        'entrada','cualificacion','diagnostico','propuesta','negociacion',
        'aceptada','ganada','perdida','pausada')),
    value_minor BIGINT NOT NULL DEFAULT 0 CHECK (value_minor >= 0),
    currency TEXT NOT NULL DEFAULT 'EUR',
    owner_type TEXT CHECK (owner_type IN ('member','agent')),
    owner_id UUID,
    channel TEXT NOT NULL DEFAULT '',
    probability INT NOT NULL DEFAULT 10 CHECK (probability BETWEEN 0 AND 100),
    next_action TEXT NOT NULL DEFAULT '',
    next_action_on DATE,
    last_contact_at TIMESTAMPTZ,
    lost_reason TEXT NOT NULL DEFAULT '',
    offer_version_id UUID,
    proposal JSONB,
    accepted_at TIMESTAMPTZ,
    won_at TIMESTAMPTZ,
    project_id UUID,
    notes TEXT NOT NULL DEFAULT '',
    origin TEXT NOT NULL DEFAULT 'app',
    attrs JSONB NOT NULL DEFAULT '{}'::jsonb,
    version INT NOT NULL DEFAULT 1,
    archived_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS biz_invoice (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    direction TEXT NOT NULL CHECK (direction IN ('issued','received')),
    number TEXT,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','issued','partially_paid','paid','void','rectified')),
    organization_id UUID,
    opportunity_id UUID,
    project_id UUID,
    issue_date DATE,
    due_date DATE,
    payment_terms_days INT NOT NULL DEFAULT 15 CHECK (payment_terms_days BETWEEN 0 AND 365),
    lines JSONB NOT NULL DEFAULT '[]'::jsonb,
    base_minor BIGINT NOT NULL DEFAULT 0,
    tax_minor BIGINT NOT NULL DEFAULT 0,
    withholding_minor BIGINT NOT NULL DEFAULT 0,
    total_minor BIGINT NOT NULL DEFAULT 0,
    paid_minor BIGINT NOT NULL DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'EUR',
    category TEXT NOT NULL DEFAULT '',
    nature TEXT NOT NULL DEFAULT 'operating' CHECK (nature IN ('operating','investment','other')),
    rectifies_id UUID,
    document_id UUID,
    notes TEXT NOT NULL DEFAULT '',
    origin TEXT NOT NULL DEFAULT 'app',
    attrs JSONB NOT NULL DEFAULT '{}'::jsonb,
    version INT NOT NULL DEFAULT 1,
    archived_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (workspace_id, direction, number)
);

CREATE TABLE IF NOT EXISTS biz_payment (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    invoice_id UUID NOT NULL,
    amount_minor BIGINT NOT NULL CHECK (amount_minor <> 0),
    paid_on DATE NOT NULL,
    method TEXT NOT NULL DEFAULT 'transfer',
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','confirmed','rejected')),
    movement_id UUID,
    evidence TEXT NOT NULL DEFAULT '',
    confirmed_by_type TEXT,
    confirmed_by_id UUID,
    confirmed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    version INT NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS biz_bank_account (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    name TEXT NOT NULL,
    iban_masked TEXT NOT NULL DEFAULT '',
    currency TEXT NOT NULL DEFAULT 'EUR',
    opening_balance_minor BIGINT,
    opening_on DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    version INT NOT NULL DEFAULT 1,
    archived_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS biz_bank_movement (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    account_id UUID NOT NULL,
    booked_on DATE NOT NULL,
    value_on DATE,
    amount_minor BIGINT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    counterparty TEXT NOT NULL DEFAULT '',
    balance_after_minor BIGINT,
    import_hash TEXT NOT NULL,
    import_batch TEXT NOT NULL DEFAULT '',
    nature TEXT NOT NULL DEFAULT 'unclassified' CHECK (nature IN (
        'unclassified','operating_income','operating_expense','tax','payroll',
        'internal_transfer','owner_withdrawal','loan','investment')),
    category TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'unreconciled' CHECK (status IN ('unreconciled','proposed','reconciled','ignored')),
    invoice_id UUID,
    payment_id UUID,
    match_reason TEXT NOT NULL DEFAULT '',
    document_id UUID,
    notes TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    version INT NOT NULL DEFAULT 1,
    UNIQUE (account_id, import_hash)
);

CREATE TABLE IF NOT EXISTS biz_period (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    year INT NOT NULL CHECK (year BETWEEN 2000 AND 2100),
    quarter INT NOT NULL CHECK (quarter BETWEEN 1 AND 4),
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN (
        'open','prepared','approved','sent','filed','archived','settled','not_applicable')),
    package_path TEXT NOT NULL DEFAULT '',
    summary JSONB NOT NULL DEFAULT '{}'::jsonb,
    evidence TEXT NOT NULL DEFAULT '',
    history JSONB NOT NULL DEFAULT '[]'::jsonb,
    notes TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    version INT NOT NULL DEFAULT 1,
    UNIQUE (workspace_id, year, quarter)
);

CREATE TABLE IF NOT EXISTS biz_kpi (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    code TEXT NOT NULL,
    area TEXT NOT NULL,
    name TEXT NOT NULL,
    unit TEXT NOT NULL DEFAULT '',
    formula TEXT NOT NULL DEFAULT '',
    direction TEXT NOT NULL DEFAULT 'up' CHECK (direction IN ('up','down','range')),
    target NUMERIC,
    alert NUMERIC,
    period TEXT NOT NULL DEFAULT 'month',
    owner_role_id UUID,
    enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    version INT NOT NULL DEFAULT 1,
    UNIQUE (workspace_id, code)
);

CREATE TABLE IF NOT EXISTS biz_objective (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    area TEXT NOT NULL,
    period TEXT NOT NULL,
    title TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'cumulative' CHECK (kind IN ('cumulative','level','compliance','service')),
    kpi_code TEXT NOT NULL DEFAULT '',
    target NUMERIC,
    baseline NUMERIC,
    owner_type TEXT CHECK (owner_type IN ('member','agent')),
    owner_id UUID,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('draft','active','achieved','missed','deferred')),
    result TEXT NOT NULL DEFAULT '',
    learnings TEXT NOT NULL DEFAULT '',
    deferred_to TEXT NOT NULL DEFAULT '',
    attrs JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    version INT NOT NULL DEFAULT 1,
    archived_at TIMESTAMPTZ
);

-- Decisions are append-only: a correction is a new row with supersedes_id.
CREATE TABLE IF NOT EXISTS biz_decision (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    area TEXT NOT NULL,
    title TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','decided','superseded')),
    context TEXT NOT NULL DEFAULT '',
    decision TEXT NOT NULL DEFAULT '',
    why TEXT NOT NULL DEFAULT '',
    purpose TEXT NOT NULL DEFAULT '',
    refs JSONB NOT NULL DEFAULT '[]'::jsonb,
    author_type TEXT NOT NULL DEFAULT 'member',
    author_id UUID,
    decided_at TIMESTAMPTZ,
    supersedes_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    version INT NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS biz_content (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    title TEXT NOT NULL,
    pillar TEXT NOT NULL DEFAULT '',
    channel TEXT NOT NULL DEFAULT '',
    format TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'idea' CHECK (status IN ('idea','borrador','revision','aprobado','programado','publicado','fallido')),
    body TEXT NOT NULL DEFAULT '',
    scheduled_at TIMESTAMPTZ,
    published_at TIMESTAMPTZ,
    evidence_url TEXT NOT NULL DEFAULT '',
    failure_reason TEXT NOT NULL DEFAULT '',
    derived_from_id UUID,
    notes TEXT NOT NULL DEFAULT '',
    attrs JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    version INT NOT NULL DEFAULT 1,
    archived_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS biz_conversation (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    channel TEXT NOT NULL,
    handle TEXT NOT NULL DEFAULT '',
    summary TEXT NOT NULL DEFAULT '',
    content_id UUID,
    qualified BOOLEAN NOT NULL DEFAULT false,
    contact_id UUID,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    version INT NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS biz_routine (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('day','week','month','quarter')),
    period_key TEXT NOT NULL,
    focus TEXT NOT NULL DEFAULT '',
    plan TEXT NOT NULL DEFAULT '',
    verdict TEXT NOT NULL DEFAULT '',
    review TEXT NOT NULL DEFAULT '',
    closed_at TIMESTAMPTZ,
    author_type TEXT NOT NULL DEFAULT 'member',
    author_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    version INT NOT NULL DEFAULT 1,
    UNIQUE (workspace_id, kind, period_key)
);

CREATE TABLE IF NOT EXISTS biz_policy (
    workspace_id UUID NOT NULL,
    capability TEXT NOT NULL,
    mode TEXT NOT NULL DEFAULT 'assisted' CHECK (mode IN ('off','manual','assisted','supervised','autonomous')),
    limits JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (workspace_id, capability)
);

CREATE TABLE IF NOT EXISTS biz_approval (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    capability TEXT NOT NULL,
    action TEXT NOT NULL,
    area TEXT NOT NULL,
    title TEXT NOT NULL,
    summary TEXT NOT NULL DEFAULT '',
    entity_type TEXT NOT NULL DEFAULT '',
    entity_id UUID,
    entity_version INT,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    payload_hash TEXT NOT NULL,
    effects JSONB NOT NULL DEFAULT '[]'::jsonb,
    requested_by_type TEXT NOT NULL,
    requested_by_id UUID,
    task_id UUID,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','executed','failed','invalidated','expired')),
    decided_by UUID,
    decided_at TIMESTAMPTZ,
    reason TEXT NOT NULL DEFAULT '',
    executed_at TIMESTAMPTZ,
    result JSONB,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Transactional outbox for business events. Delivery is at-least-once; the
-- idempotency key makes re-emission of the same fact a no-op.
CREATE TABLE IF NOT EXISTS biz_event (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    type TEXT NOT NULL,
    type_version INT NOT NULL DEFAULT 1,
    entity_type TEXT NOT NULL DEFAULT '',
    entity_id UUID,
    source TEXT NOT NULL DEFAULT 'app',
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    correlation_id UUID,
    causation_id UUID,
    idempotency_key TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','processing','processed','failed','dead')),
    attempts INT NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    leased_until TIMESTAMPTZ,
    last_error TEXT NOT NULL DEFAULT '',
    processed_at TIMESTAMPTZ,
    UNIQUE (workspace_id, idempotency_key)
);

CREATE TABLE IF NOT EXISTS biz_audit (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    at TIMESTAMPTZ NOT NULL DEFAULT now(),
    actor_type TEXT NOT NULL,
    actor_id UUID,
    action TEXT NOT NULL,
    capability TEXT NOT NULL DEFAULT '',
    entity_type TEXT NOT NULL DEFAULT '',
    entity_id UUID,
    approval_id UUID,
    result TEXT NOT NULL DEFAULT 'ok',
    details JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS biz_document (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    entity_type TEXT NOT NULL DEFAULT '',
    entity_id UUID,
    kind TEXT NOT NULL DEFAULT 'document',
    title TEXT NOT NULL,
    rel_path TEXT NOT NULL,
    sha256 TEXT NOT NULL DEFAULT '',
    size_bytes BIGINT NOT NULL DEFAULT 0,
    origin TEXT NOT NULL DEFAULT 'app',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    version INT NOT NULL DEFAULT 1
);

-- Recovery journal for writes to the portable company folder.
CREATE TABLE IF NOT EXISTS biz_journal (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id UUID NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id UUID NOT NULL,
    rel_path TEXT NOT NULL,
    content_hash TEXT NOT NULL DEFAULT '',
    state TEXT NOT NULL DEFAULT 'intent' CHECK (state IN ('intent','committed','failed','superseded')),
    error TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    committed_at TIMESTAMPTZ
);

-- Business links of a Multica project. Unique opportunity_id is what makes
-- "payment confirmed -> project" idempotent.
CREATE TABLE IF NOT EXISTS biz_project_link (
    project_id UUID NOT NULL PRIMARY KEY,
    workspace_id UUID NOT NULL,
    service_id UUID,
    organization_id UUID,
    opportunity_id UUID UNIQUE,
    objective_id UUID,
    kind TEXT NOT NULL DEFAULT 'service' CHECK (kind IN ('strategic','compliance','service')),
    period_key TEXT NOT NULL DEFAULT '',
    template_version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
