use crate::{
    AppState,
    error::{ApiError, Result},
    models::{Member, MemberInput, phone, text, today},
    security, services,
};
use axum::http::StatusCode;
use base64::{Engine, engine::general_purpose::STANDARD};
use chrono::{Days, Months, NaiveDate};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::io::Cursor;
use uuid::Uuid;

pub const UPI_ID: &str = "8943521009@yescred";
pub const PAYEE_NAME: &str = "RepLab Fitness";

pub fn options() -> Value {
    json!({
        "plans": [
            {"code":"silver","name":"Silver Plan","description":"Strength & Fitness",
             "prices_paise":{"1":120000,"3":320000,"6":600000,"12":1200000}},
            {"code":"gold","name":"Gold Plan","description":"Silver + Cardio Access",
             "prices_paise":{"1":170000,"3":470000,"6":900000,"12":1800000}}
        ],
        "training_monthly_paise":500000,"insurance_monthly_paise":20000,
        "upi_id":UPI_ID,"payee_name":PAYEE_NAME
    })
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct EnrollmentInput {
    pub request_id: Uuid,
    pub member: MemberInput,
    pub photo_base64: String,
    pub plan_code: String,
    pub months: u32,
    pub starts_on: NaiveDate,
    pub training_months: u32,
    pub insurance_months: u32,
    pub payment_method: String,
    #[serde(default)]
    pub payment_reference: String,
    pub payment_confirmed: bool,
}

fn plan_price(code: &str, months: u32) -> Result<i64> {
    Ok(match (code, months) {
        ("silver", 1) => 120000,
        ("silver", 3) => 320000,
        ("silver", 6) => 600000,
        ("silver", 12) => 1200000,
        ("gold", 1) => 170000,
        ("gold", 3) => 470000,
        ("gold", 6) => 900000,
        ("gold", 12) => 1800000,
        _ => return Err(ApiError::validation()),
    })
}

pub fn end_date(start: NaiveDate, months: u32) -> Result<NaiveDate> {
    start
        .checked_add_months(Months::new(months))
        .and_then(|date| date.checked_sub_days(Days::new(1)))
        .ok_or_else(ApiError::validation)
}

fn details(input: &EnrollmentInput) -> Result<Value> {
    let base = plan_price(&input.plan_code, input.months)?;
    if input.training_months > input.months
        || input.insurance_months > input.months
        || input.starts_on < today()
        || input.starts_on > today() + Days::new(366)
        || !input.payment_confirmed
        || !["cash", "upi"].contains(&input.payment_method.as_str())
    {
        return Err(ApiError::validation());
    }
    let training = i64::from(input.training_months) * 500000;
    let insurance = i64::from(input.insurance_months) * 20000;
    Ok(json!({
        "plan_code":input.plan_code,
        "plan_name": if input.plan_code=="silver" {"Silver Plan"} else {"Gold Plan"},
        "months":input.months,"starts_on":input.starts_on,
        "ends_on":end_date(input.starts_on,input.months)?,
        "training_months":input.training_months,"insurance_months":input.insurance_months,
        "training_ends_on":if input.training_months>0 {Some(end_date(input.starts_on,input.training_months)?)} else {None},
        "insurance_ends_on":if input.insurance_months>0 {Some(end_date(input.starts_on,input.insurance_months)?)} else {None},
        "base_paise":base,"training_paise":training,"insurance_paise":insurance,
        "total_paise":base+training+insurance,
        "payment_method":input.payment_method,"payment_reference":input.payment_reference,
        "payment_verification":"staff_confirmed",
        "upi_id":if input.payment_method=="upi" {Some(UPI_ID)} else {None},
        "payee_name":PAYEE_NAME
    }))
}

async fn photo(state: &AppState, encoded: String) -> Result<Vec<u8>> {
    if encoded.len() > 2_800_000 {
        return Err(ApiError::validation());
    }
    let bytes = STANDARD
        .decode(encoded)
        .map_err(|_| ApiError::validation())?;
    if bytes.is_empty() || bytes.len() > 2_097_152 {
        return Err(ApiError::validation());
    }
    // Bound image work alongside Argon2; discard EXIF/location metadata by re-encoding.
    let permit = state
        .hashes
        .clone()
        .acquire_owned()
        .await
        .map_err(|_| ApiError::internal())?;
    tokio::task::spawn_blocking(move || {
        let _permit = permit;
        let mut reader = image::ImageReader::new(Cursor::new(bytes))
            .with_guessed_format()
            .map_err(|_| ApiError::validation())?;
        let mut limits = image::Limits::default();
        limits.max_image_width = Some(1024);
        limits.max_image_height = Some(1024);
        limits.max_alloc = Some(8 * 1024 * 1024);
        reader.limits(limits);
        let image = reader.decode().map_err(|_| ApiError::validation())?;
        let image = image.thumbnail(512, 512).to_rgb8();
        let mut output = Vec::new();
        image::codecs::jpeg::JpegEncoder::new_with_quality(&mut output, 85)
            .encode_image(&image)
            .map_err(|_| ApiError::validation())?;
        if output.len() > 524288 {
            return Err(ApiError::validation());
        }
        Ok(output)
    })
    .await
    .map_err(|_| ApiError::internal())?
}

pub async fn create(state: &AppState, actor: Uuid, input: EnrollmentInput) -> Result<Member> {
    // Hash the exact submitted request, including photo and staff confirmation.
    let fingerprint =
        security::digest(&serde_json::to_string(&input).map_err(|_| ApiError::validation())?);
    let mut tx = state.pool.begin().await?;
    // A single enrollment ID cannot race into two members/receipts.
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))")
        .bind(input.request_id.to_string())
        .execute(&mut *tx)
        .await?;
    if let Some((id, saved_hash)) = sqlx::query_as::<_, (Uuid, String)>(
        "SELECT member_id,request_hash FROM member_enrollments WHERE id=$1",
    )
    .bind(input.request_id)
    .fetch_optional(&mut *tx)
    .await?
    {
        if saved_hash != fingerprint {
            return Err(ApiError::new(
                StatusCode::CONFLICT,
                "enrollment_conflict",
                "This registration was already saved with different details. Check the member record.",
            ));
        }
        tx.commit().await?;
        return services::member(state, id).await;
    }
    let mut snapshot = details(&input)?;
    let reference = text(&input.payment_reference, 100, false)?;
    snapshot["payment_reference"] = json!(reference);
    let data = input.member.validate()?;
    text(&data.address, 500, true)?;
    phone(&data.emergency_phone, false)?;
    if !data.is_active || input.starts_on < data.joined {
        return Err(ApiError::validation());
    }
    let photo = photo(state, input.photo_base64).await?;
    let id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO members(id,name,phone,email,address,emergency_phone,notes,joined,is_active)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,true)",
    )
    .bind(id)
    .bind(data.name)
    .bind(data.phone)
    .bind(data.email)
    .bind(data.address)
    .bind(data.emergency_phone)
    .bind(data.notes)
    .bind(data.joined)
    .execute(&mut *tx)
    .await?;
    let (serial, received): (i64, chrono::DateTime<chrono::Utc>) = sqlx::query_as(
        "INSERT INTO member_enrollments(id,member_id,request_hash,photo,details,base_paise,training_paise,
         insurance_paise,total_paise,payment_method,payment_reference,confirmed_by)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING invoice_serial,received_at")
        .bind(input.request_id).bind(id).bind(fingerprint).bind(photo).bind(&snapshot)
        .bind(snapshot["base_paise"].as_i64().unwrap())
        .bind(snapshot["training_paise"].as_i64().unwrap())
        .bind(snapshot["insurance_paise"].as_i64().unwrap())
        .bind(snapshot["total_paise"].as_i64().unwrap())
        .bind(input.payment_method).bind(reference).bind(actor)
        .fetch_one(&mut *tx).await?;
    services::audit(
        &mut tx,
        Some(actor),
        "member.enroll",
        Some(id),
        json!({"enrollment_id":input.request_id,"invoice_serial":serial,
            "total_paise":snapshot["total_paise"],"received_at":received}),
    )
    .await?;
    tx.commit().await?;
    services::member(state, id).await
}

pub async fn decorate(state: &AppState, mut member: Member) -> Result<Member> {
    type ReceiptRow = (Value, Vec<u8>, i64, chrono::DateTime<chrono::Utc>, Uuid);
    let row: Option<ReceiptRow> = sqlx::query_as(
        "SELECT details,photo,invoice_serial,received_at,confirmed_by
            FROM member_enrollments WHERE member_id=$1",
    )
    .bind(member.id)
    .fetch_optional(&state.pool)
    .await?;
    if let Some((mut details, photo, serial, received, actor)) = row {
        details["invoice_number"] = json!(format!("RL-{serial:06}"));
        details["received_at"] = json!(received);
        details["confirmed_by"] = json!(actor);
        member.enrollment = Some(details);
        member.photo_base64 = Some(STANDARD.encode(photo));
    }
    Ok(member)
}

pub async fn lookup(state: &AppState, request_id: Uuid) -> Result<Member> {
    let id: Uuid = sqlx::query_scalar("SELECT member_id FROM member_enrollments WHERE id=$1")
        .bind(request_id)
        .fetch_optional(&state.pool)
        .await?
        .ok_or_else(|| {
            ApiError::new(
                StatusCode::NOT_FOUND,
                "enrollment_not_found",
                "Registration not found.",
            )
        })?;
    services::member(state, id).await
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn prices_and_inclusive_dates() {
        assert_eq!(plan_price("silver", 3).unwrap(), 320000);
        assert_eq!(plan_price("gold", 12).unwrap(), 1800000);
        assert!(plan_price("gold", 2).is_err());
        for (start, months, end) in [
            ("2026-11-02", 1, "2026-12-01"),
            ("2026-01-31", 1, "2026-02-27"),
            ("2024-02-29", 12, "2025-02-27"),
        ] {
            assert_eq!(
                end_date(start.parse().unwrap(), months).unwrap(),
                end.parse::<NaiveDate>().unwrap()
            );
        }
    }
}
