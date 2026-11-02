CREATE TABLE member_enrollments (
    id uuid PRIMARY KEY,
    member_id uuid NOT NULL UNIQUE REFERENCES members(id),
    request_hash varchar(64) NOT NULL,
    photo bytea NOT NULL CHECK (octet_length(photo) BETWEEN 1 AND 524288),
    details jsonb NOT NULL,
    base_paise bigint NOT NULL CHECK (base_paise > 0),
    training_paise bigint NOT NULL CHECK (training_paise >= 0),
    insurance_paise bigint NOT NULL CHECK (insurance_paise >= 0),
    total_paise bigint NOT NULL CHECK (total_paise = base_paise + training_paise + insurance_paise),
    payment_method varchar(4) NOT NULL CHECK (payment_method IN ('cash','upi')),
    payment_reference varchar(100) NOT NULL,
    invoice_serial bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
    confirmed_by uuid NOT NULL REFERENCES admins(id),
    received_at timestamptz NOT NULL DEFAULT now()
);
-- Receipts are append-only. Corrections/refunds must never overwrite a receipt.
GRANT SELECT, INSERT ON member_enrollments TO replab_app;
GRANT USAGE, SELECT ON SEQUENCE member_enrollments_invoice_serial_seq TO replab_app;
ALTER TABLE replab_schema DROP CONSTRAINT replab_schema_version_check;
ALTER TABLE replab_schema ADD CONSTRAINT replab_schema_version_check CHECK (version IN (1,2,3));
UPDATE replab_schema SET version=3;
