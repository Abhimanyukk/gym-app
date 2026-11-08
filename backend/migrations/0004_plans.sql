CREATE TABLE plan_catalog (
    id smallint PRIMARY KEY CHECK (id = 1),
    revision bigint NOT NULL CHECK (revision > 0),
    data jsonb NOT NULL CHECK (
        jsonb_typeof(data) = 'object' AND data ? 'plans'
        AND jsonb_typeof(data->'plans') = 'array'
    ),
    updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO plan_catalog(id, revision, data) VALUES (1, 1, '{
    "plans": [
        {"code":"silver","name":"Silver Plan","description":"Strength & Fitness","active":true,
         "prices_paise":{"1":120000,"3":320000,"6":600000,"12":1200000}},
        {"code":"gold","name":"Gold Plan","description":"Silver + Cardio Access","active":true,
         "prices_paise":{"1":170000,"3":470000,"6":900000,"12":1800000}}
    ],
    "training_monthly_paise":500000,
    "insurance_monthly_paise":20000
}');
-- The runtime can edit the one catalogue, not delete it or alter old receipts.
GRANT SELECT, UPDATE ON plan_catalog TO replab_app;
ALTER TABLE replab_schema DROP CONSTRAINT replab_schema_version_check;
ALTER TABLE replab_schema ADD CONSTRAINT replab_schema_version_check CHECK (version IN (1,2,3,4));
UPDATE replab_schema SET version = 4;
