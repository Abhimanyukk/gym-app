use anyhow::{Context, bail};
use sqlx::PgPool;
pub const INITIAL_SQL: &str = include_str!("../migrations/0001_initial.sql");

pub async fn migrate(pool: &PgPool) -> anyhow::Result<()> {
    let mut tx = pool.begin().await.context("Cannot begin migration")?;
    sqlx::query("SELECT pg_advisory_xact_lock(73421002)")
        .execute(&mut *tx)
        .await?;
    let has_version: bool =
        sqlx::query_scalar("SELECT to_regclass('public.replab_schema') IS NOT NULL")
            .fetch_one(&mut *tx)
            .await?;
    if has_version {
        let versions: Vec<i16> = sqlx::query_scalar("SELECT version FROM replab_schema")
            .fetch_all(&mut *tx)
            .await?;
        if versions == vec![3] {
            tx.commit().await?;
            return Ok(());
        }
        if versions != vec![1] && versions != vec![2] {
            bail!("Unsupported schema version; nothing was changed.");
        }
        if versions == vec![1] {
            single_admin(&mut tx).await?;
        }
        enrollment(&mut tx).await?;
        tx.commit().await?;
        return Ok(());
    }
    let legacy: bool =
        sqlx::query_scalar("SELECT to_regclass('public.alembic_version') IS NOT NULL")
            .fetch_one(&mut *tx)
            .await?;
    if legacy {
        let versions: Vec<String> = sqlx::query_scalar("SELECT version_num FROM alembic_version")
            .fetch_all(&mut *tx)
            .await?;
        if versions != vec!["0001".to_owned()] {
            bail!("Unknown legacy revision; refusing migration.");
        }
        let columns: Vec<String>=sqlx::query_scalar(
            "SELECT table_name||':'||column_name||':'||data_type||':'||is_nullable
            FROM information_schema.columns WHERE table_schema='public'
            AND table_name IN ('admins','audit_logs','gym_settings','login_buckets','login_sessions','members')
            ORDER BY table_name,ordinal_position").fetch_all(&mut *tx).await?;
        let expected: Vec<_> = include_str!("../migrations/legacy-columns.txt")
            .lines()
            .map(str::to_owned)
            .collect();
        if columns != expected {
            bail!("Legacy columns differ from revision 0001; refusing adoption.");
        }
        let constraints: i64=sqlx::query_scalar(
            "SELECT count(*) FROM pg_constraint WHERE connamespace='public'::regnamespace
            AND conname IN ('ck_admin_slot','ck_admin_email','uq_admin_slot','uq_admin_email','ck_single_gym','uq_member_serial')")
            .fetch_one(&mut *tx).await?;
        if constraints != 6 {
            bail!("Legacy constraints are missing; refusing adoption.");
        }
        println!(
            "Adopting verified legacy revision 0001; business records and hashes are unchanged."
        );
    } else {
        let existing: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'",
        )
        .fetch_one(&mut *tx)
        .await?;
        if existing != 0 {
            bail!("Database is not empty and has no known migration marker; refusing changes.");
        }
        sqlx::raw_sql(INITIAL_SQL).execute(&mut *tx).await?;
    }
    sqlx::raw_sql(
        "CREATE TABLE replab_schema(version smallint PRIMARY KEY CHECK(version=1));
        INSERT INTO replab_schema VALUES(1);
        REVOKE CREATE ON SCHEMA public FROM PUBLIC;
        GRANT USAGE ON SCHEMA public TO replab_app;
        GRANT SELECT ON replab_schema TO replab_app;
        GRANT SELECT,INSERT,UPDATE ON admins TO replab_app;
        GRANT SELECT,INSERT,DELETE ON login_sessions TO replab_app;
        GRANT SELECT,INSERT,UPDATE,DELETE ON login_buckets TO replab_app;
        GRANT SELECT,UPDATE ON gym_settings TO replab_app;
        GRANT SELECT,INSERT ON members,audit_logs TO replab_app;
        GRANT USAGE,SELECT ON SEQUENCE member_number_seq TO replab_app;",
    )
    .execute(&mut *tx)
    .await?;
    single_admin(&mut tx).await?;
    enrollment(&mut tx).await?;
    tx.commit().await?;
    println!("Schema 3 ready. Existing passwords and business records are preserved.");
    Ok(())
}

async fn enrollment(tx: &mut sqlx::Transaction<'_, sqlx::Postgres>) -> anyhow::Result<()> {
    sqlx::raw_sql(include_str!("../migrations/0003_enrollment.sql"))
        .execute(&mut **tx)
        .await?;
    Ok(())
}

async fn single_admin(tx: &mut sqlx::Transaction<'_, sqlx::Postgres>) -> anyhow::Result<()> {
    sqlx::query("SELECT pg_advisory_xact_lock(73421001)")
        .execute(&mut **tx)
        .await?;
    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM admins")
        .fetch_one(&mut **tx)
        .await?;
    if count > 1 {
        bail!(
            "More than one admin exists; migration refused. Choose an account explicitly; no accounts were deleted."
        );
    }
    sqlx::raw_sql(include_str!("../migrations/0002_single_admin.sql"))
        .execute(&mut **tx)
        .await?;
    Ok(())
}
