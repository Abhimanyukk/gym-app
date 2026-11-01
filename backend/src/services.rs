use crate::{
    AppState,
    error::{ApiError, Result},
    models::*,
    security,
};
use axum::http::{HeaderMap, StatusCode};
use chrono::{Duration, Utc};
use serde_json::{Value, json};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

const MEMBER_SELECT: &str = "SELECT members.*,
    'M-' || lpad(serial::text, greatest(4,length(serial::text)), '0') AS number FROM members";

pub struct Auth {
    pub admin: Admin,
    pub token_hash: String,
}

pub async fn authenticate(state: &AppState, headers: &HeaderMap) -> Result<Auth> {
    let token = headers
        .get("authorization")
        .and_then(|s| s.to_str().ok())
        .and_then(|s| s.split_once(' '))
        .filter(|(scheme, token)| {
            scheme.eq_ignore_ascii_case("bearer") && (20..=128).contains(&token.len())
        })
        .map(|(_, token)| token)
        .ok_or_else(ApiError::unauthorized)?;
    let token_hash = security::digest(token);
    let admin = sqlx::query_as::<_, Admin>(
        "SELECT a.id,a.name,a.email,a.created_at FROM admins a JOIN login_sessions s ON s.admin_id=a.id
        WHERE s.token_hash=$1 AND s.expires_at>now()")
        .bind(&token_hash).fetch_optional(&state.pool).await?.ok_or_else(ApiError::unauthorized)?;
    Ok(Auth { admin, token_hash })
}

pub async fn audit(
    tx: &mut Transaction<'_, Postgres>,
    actor: Option<Uuid>,
    action: &str,
    target: Option<Uuid>,
    details: Value,
) -> Result<()> {
    sqlx::query(
        "INSERT INTO audit_logs(id,actor_id,action,target_id,details) VALUES($1,$2,$3,$4,$5)",
    )
    .bind(Uuid::new_v4())
    .bind(actor)
    .bind(action)
    .bind(target)
    .bind(details)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

async fn take_login_attempt(state: &AppState, client: &str) -> Result<()> {
    let mut limits = [
        (security::digest("single-admin"), 10),
        (security::digest(&format!("ip:{client}")), 30),
    ];
    limits.sort_by(|a, b| a.0.cmp(&b.0));
    let mut tx = state.pool.begin().await?;
    sqlx::query("DELETE FROM login_buckets WHERE started_at<now()-interval '1 day'")
        .execute(&mut *tx)
        .await?;
    let timestamp = Utc::now();
    let mut retry = 0;
    for (key, limit) in limits {
        let (attempts, started): (i32, chrono::DateTime<Utc>) = sqlx::query_as(
            "INSERT INTO login_buckets(key,attempts,started_at) VALUES($1,1,$2)
            ON CONFLICT(key) DO UPDATE SET
            attempts=CASE WHEN login_buckets.started_at<=$2-interval '15 minutes' THEN 1 ELSE login_buckets.attempts+1 END,
            started_at=CASE WHEN login_buckets.started_at<=$2-interval '15 minutes' THEN $2 ELSE login_buckets.started_at END
            RETURNING attempts,started_at")
            .bind(key).bind(timestamp).fetch_one(&mut *tx).await?;
        if attempts > limit {
            retry = retry.max(
                (started + Duration::minutes(15) - timestamp)
                    .num_seconds()
                    .max(1),
            );
        }
    }
    // Failed authentication must not roll back the persistent limiter.
    tx.commit().await?;
    if retry > 0 {
        let mut error = ApiError::new(
            StatusCode::TOO_MANY_REQUESTS,
            "login_rate_limited",
            "Too many login attempts. Try again later.",
        );
        error.retry_after = Some(retry);
        return Err(error);
    }
    Ok(())
}

pub async fn login(state: &AppState, input: LoginInput, client: &str) -> Result<Value> {
    let password = security::password(&input.password, false)?;
    take_login_attempt(state, client).await?;
    let mut tx = state.pool.begin().await?;
    let row: Option<(Uuid, String)> =
        sqlx::query_as("SELECT id,password_hash FROM admins WHERE slot=1 FOR UPDATE")
            .fetch_optional(&mut *tx)
            .await?;
    let encoded = row
        .as_ref()
        .map(|(_, hash)| hash.clone())
        .unwrap_or_else(|| state.dummy_hash.clone());
    let valid = security::verify(password, encoded, state.hashes.clone()).await?;
    if !valid || row.is_none() {
        return Err(ApiError::new(
            StatusCode::UNAUTHORIZED,
            "invalid_credentials",
            "Server password is incorrect.",
        ));
    }
    let id = row.unwrap().0;
    let admin =
        sqlx::query_as::<_, Admin>("SELECT id,name,email,created_at FROM admins WHERE id=$1")
            .bind(id)
            .fetch_one(&mut *tx)
            .await?;
    let token = security::random_token();
    let expires = Utc::now() + Duration::days(90);
    sqlx::query("DELETE FROM login_sessions WHERE expires_at<=now()")
        .execute(&mut *tx)
        .await?;
    sqlx::query("INSERT INTO login_sessions(token_hash,admin_id,expires_at) VALUES($1,$2,$3)")
        .bind(security::digest(&token))
        .bind(id)
        .bind(expires)
        .execute(&mut *tx)
        .await?;
    audit(&mut tx, Some(id), "auth.login", Some(id), json!({})).await?;
    tx.commit().await?;
    Ok(json!({"access_token":token,"token_type":"bearer","expires_at":expires,"admin":admin}))
}

pub async fn create_admin(
    state: &AppState,
    input: AdminInput,
    actor: Option<Uuid>,
) -> Result<Admin> {
    let name = text(&input.name, 100, true)?;
    let email = email(&input.email, false)?;
    let password = security::password(&input.password, true)?;
    let mut tx = state.pool.begin().await?;
    sqlx::query("SELECT pg_advisory_xact_lock(73421001)")
        .execute(&mut *tx)
        .await?;
    let rows: Vec<(i16, String)> = sqlx::query_as("SELECT slot,email FROM admins ORDER BY slot")
        .fetch_all(&mut *tx)
        .await?;
    if actor.is_none() && !rows.is_empty() {
        return Err(ApiError::new(
            StatusCode::CONFLICT,
            "already_initialized",
            "An initial admin already exists.",
        ));
    }
    if rows.iter().any(|(_, e)| *e == email) {
        return Err(ApiError::new(
            StatusCode::CONFLICT,
            "duplicate_admin",
            "An admin with this email already exists.",
        ));
    }
    let slot = (1i16..=1)
        .find(|s| !rows.iter().any(|(used, _)| used == s))
        .ok_or_else(|| {
            ApiError::new(
                StatusCode::CONFLICT,
                "admin_limit",
                "Only one server administrator is allowed.",
            )
        })?;
    let hash = security::hash(password, state.hashes.clone()).await?;
    let admin = sqlx::query_as::<_, Admin>(
        "INSERT INTO admins(id,slot,name,email,password_hash)
        VALUES($1,$2,$3,$4,$5) RETURNING id,name,email,created_at",
    )
    .bind(Uuid::new_v4())
    .bind(slot)
    .bind(name)
    .bind(email)
    .bind(hash)
    .fetch_one(&mut *tx)
    .await?;
    audit(
        &mut tx,
        actor,
        if actor.is_some() {
            "admin.create"
        } else {
            "admin.bootstrap"
        },
        Some(admin.id),
        json!({}),
    )
    .await?;
    tx.commit().await?;
    Ok(admin)
}

pub async fn logout(state: &AppState, auth: Auth) -> Result<()> {
    let mut tx = state.pool.begin().await?;
    sqlx::query("DELETE FROM login_sessions WHERE token_hash=$1")
        .bind(auth.token_hash)
        .execute(&mut *tx)
        .await?;
    audit(
        &mut tx,
        Some(auth.admin.id),
        "auth.logout",
        Some(auth.admin.id),
        json!({}),
    )
    .await?;
    tx.commit().await?;
    Ok(())
}

/// A revocable, random device session, not the password. Renew its idle lifetime
/// after a verified resume. No key rotation means a lost response cannot strand
/// the device; password changes and sign-out invalidate it immediately.
pub async fn resume(state: &AppState, auth: Auth) -> Result<Value> {
    let mut tx = state.pool.begin().await?;
    // Same lock order as password changes: do not resurrect a revoked session.
    sqlx::query("SELECT id FROM admins WHERE id=$1 FOR UPDATE")
        .bind(auth.admin.id)
        .execute(&mut *tx)
        .await?;
    let expires: Option<chrono::DateTime<Utc>> = sqlx::query_scalar(
        "UPDATE login_sessions SET expires_at=now()+interval '90 days'
         WHERE token_hash=$1 AND expires_at>now() RETURNING expires_at",
    )
    .bind(&auth.token_hash)
    .fetch_optional(&mut *tx)
    .await?;
    let expires = expires.ok_or_else(ApiError::unauthorized)?;
    audit(
        &mut tx,
        Some(auth.admin.id),
        "auth.resume",
        Some(auth.admin.id),
        json!({}),
    )
    .await?;
    tx.commit().await?;
    Ok(json!({"expires_at":expires,"admin":auth.admin}))
}

pub async fn change_password(state: &AppState, auth: Auth, input: PasswordInput) -> Result<()> {
    let current = security::password(&input.current_password, false)?;
    let new = security::password(&input.new_password, true)?;
    let mut tx = state.pool.begin().await?;
    let hash: String =
        sqlx::query_scalar("SELECT password_hash FROM admins WHERE id=$1 FOR UPDATE")
            .bind(auth.admin.id)
            .fetch_one(&mut *tx)
            .await?;
    if !security::verify(current, hash.clone(), state.hashes.clone()).await? {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "wrong_password",
            "Current password is incorrect.",
        ));
    }
    if security::verify(new.clone(), hash, state.hashes.clone()).await? {
        return Err(ApiError::new(
            StatusCode::UNPROCESSABLE_ENTITY,
            "same_password",
            "Choose a different password.",
        ));
    }
    let encoded = security::hash(new, state.hashes.clone()).await?;
    sqlx::query("UPDATE admins SET password_hash=$1 WHERE id=$2")
        .bind(encoded)
        .bind(auth.admin.id)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM login_sessions WHERE admin_id=$1")
        .bind(auth.admin.id)
        .execute(&mut *tx)
        .await?;
    audit(
        &mut tx,
        Some(auth.admin.id),
        "auth.password_change",
        Some(auth.admin.id),
        json!({}),
    )
    .await?;
    tx.commit().await?;
    Ok(())
}

pub async fn settings(state: &AppState) -> Result<Settings> {
    Ok(sqlx::query_as("SELECT gym_name,phone,address,updated_at,'Asia/Kolkata'::text AS timezone,1 AS max_admins FROM gym_settings WHERE id=1")
        .fetch_one(&state.pool).await?)
}

pub async fn update_settings(
    state: &AppState,
    actor: Uuid,
    input: SettingsInput,
) -> Result<Settings> {
    let name = text(&input.gym_name, 100, true)?;
    let phone = phone(&input.phone, true)?;
    let address = text(&input.address, 500, false)?;
    let mut tx = state.pool.begin().await?;
    let settings=sqlx::query_as("UPDATE gym_settings SET gym_name=$1,phone=$2,address=$3,updated_at=now() WHERE id=1
        RETURNING gym_name,phone,address,updated_at,'Asia/Kolkata'::text AS timezone,1 AS max_admins")
        .bind(name).bind(phone).bind(address).fetch_one(&mut *tx).await?;
    audit(
        &mut tx,
        Some(actor),
        "settings.update",
        None,
        json!({"fields":["gym_name","phone","address"]}),
    )
    .await?;
    tx.commit().await?;
    Ok(settings)
}

pub async fn create_member(state: &AppState, actor: Uuid, input: MemberInput) -> Result<Member> {
    let data = input.validate()?;
    let mut tx = state.pool.begin().await?;
    let id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO members(id,name,phone,email,address,emergency_phone,notes,joined,is_active)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)",
    )
    .bind(id)
    .bind(data.name)
    .bind(data.phone)
    .bind(data.email)
    .bind(data.address)
    .bind(data.emergency_phone)
    .bind(data.notes)
    .bind(data.joined)
    .bind(data.is_active)
    .execute(&mut *tx)
    .await?;
    let member = sqlx::query_as(&format!("{MEMBER_SELECT} WHERE id=$1"))
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
    audit(&mut tx, Some(actor), "member.create", Some(id), json!({})).await?;
    tx.commit().await?;
    Ok(member)
}

pub async fn member(state: &AppState, id: Uuid) -> Result<Member> {
    sqlx::query_as(&format!("{MEMBER_SELECT} WHERE id=$1"))
        .bind(id)
        .fetch_optional(&state.pool)
        .await?
        .ok_or_else(|| {
            ApiError::new(
                StatusCode::NOT_FOUND,
                "member_not_found",
                "Member not found.",
            )
        })
}

pub async fn members(state: &AppState, query: MemberQuery) -> Result<Value> {
    let q = text(&query.q, 100, false)?;
    if !(1..=100).contains(&query.limit) || query.offset < 0 {
        return Err(ApiError::validation());
    }
    let literal = q
        .replace('\\', "\\\\")
        .replace('%', "\\%")
        .replace('_', "\\_");
    let pattern = format!("%{literal}%");
    let serial = q
        .strip_prefix("M-")
        .or_else(|| q.strip_prefix("m-"))
        .filter(|s| !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit()))
        .and_then(|s| s.parse::<i32>().ok());
    let clause = "WHERE ($1::boolean IS NULL OR is_active=$1) AND
        ($2::text='' OR name ILIKE $3 ESCAPE '\\' OR phone ILIKE $3 ESCAPE '\\' OR serial=$4)";
    let mut tx = state.pool.begin().await?;
    sqlx::query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        .execute(&mut *tx)
        .await?;
    let total: i64 = sqlx::query_scalar(&format!("SELECT count(*) FROM members {clause}"))
        .bind(query.active)
        .bind(&q)
        .bind(&pattern)
        .bind(serial)
        .fetch_one(&mut *tx)
        .await?;
    let items: Vec<Member> = sqlx::query_as(&format!(
        "{MEMBER_SELECT} {clause} ORDER BY serial LIMIT $5 OFFSET $6"
    ))
    .bind(query.active)
    .bind(&q)
    .bind(pattern)
    .bind(serial)
    .bind(query.limit)
    .bind(query.offset)
    .fetch_all(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(json!({"items":items,"total":total,"limit":query.limit,"offset":query.offset}))
}
