use crate::{
    error::{ApiError, Result},
    models::today,
};
use chrono::{DateTime, Datelike, Days, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sqlx::{FromRow, PgPool, Postgres, Transaction};

const DAILY_LIMIT: i64 = 14;
const RECEIPT_LIMIT: i64 = 20;

#[derive(Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReportQuery {
    pub from: Option<NaiveDate>,
    pub to: Option<NaiveDate>,
    #[serde(default)]
    pub daily_offset: i64,
    #[serde(default)]
    pub receipt_offset: i64,
}

impl ReportQuery {
    fn validate(&self, day: NaiveDate) -> Result<()> {
        let earliest = NaiveDate::from_ymd_opt(2000, 1, 1).unwrap();
        let to = self.to.unwrap_or(day);
        if to < earliest
            || to > day
            || self.from.is_some_and(|from| from < earliest || from > to)
            || !(0..=1_000_000).contains(&self.daily_offset)
            || !(0..=1_000_000).contains(&self.receipt_offset)
        {
            return Err(ApiError::validation());
        }
        Ok(())
    }
}

#[derive(Serialize, FromRow)]
pub(crate) struct Totals {
    pub(crate) total_paise: i64,
    cash_paise: i64,
    upi_paise: i64,
    base_paise: i64,
    training_paise: i64,
    insurance_paise: i64,
    receipt_count: i64,
}

pub(crate) async fn totals(
    tx: &mut Transaction<'_, Postgres>,
    from: NaiveDate,
    to: NaiveDate,
) -> Result<Totals> {
    Ok(sqlx::query_as(
        "SELECT COALESCE(SUM(total_paise),0)::bigint AS total_paise,
            COALESCE(SUM(total_paise) FILTER (WHERE payment_method='cash'),0)::bigint AS cash_paise,
            COALESCE(SUM(total_paise) FILTER (WHERE payment_method='upi'),0)::bigint AS upi_paise,
            COALESCE(SUM(base_paise),0)::bigint AS base_paise,
            COALESCE(SUM(training_paise),0)::bigint AS training_paise,
            COALESCE(SUM(insurance_paise),0)::bigint AS insurance_paise,
            COUNT(*) AS receipt_count
         FROM member_enrollments
         WHERE received_at >= ($1::date::timestamp AT TIME ZONE 'Asia/Kolkata')
           AND received_at < (($2::date + 1)::timestamp AT TIME ZONE 'Asia/Kolkata')",
    )
    .bind(from)
    .bind(to)
    .fetch_one(&mut **tx)
    .await?)
}

#[derive(Serialize, FromRow)]
struct Daily {
    date: NaiveDate,
    total_paise: i64,
    cash_paise: i64,
    upi_paise: i64,
    receipt_count: i64,
}

#[derive(Serialize, FromRow)]
struct PlanTotal {
    code: String,
    name: String,
    total_paise: i64,
    receipt_count: i64,
}

#[derive(Serialize, FromRow)]
struct Receipt {
    invoice_number: String,
    member_id: uuid::Uuid,
    member_number: String,
    member_name: String,
    plan_name: String,
    months: i32,
    total_paise: i64,
    payment_method: String,
    payment_reference: String,
    received_at: DateTime<Utc>,
}

pub async fn load(pool: &PgPool, query: ReportQuery) -> Result<Value> {
    let day = today();
    query.validate(day)?;
    let yesterday = day.checked_sub_days(Days::new(1)).unwrap();
    let month = day.with_day(1).unwrap();
    let mut tx = pool.begin().await?;
    // Keep totals, history and receipts on the same snapshot while enrollment
    // continues. This report never writes or recomputes historical prices.
    sqlx::query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
        .execute(&mut *tx)
        .await?;
    let first: Option<NaiveDate> = sqlx::query_scalar(
        "SELECT (MIN(received_at) AT TIME ZONE 'Asia/Kolkata')::date
         FROM member_enrollments
         WHERE received_at < (($1::date + 1)::timestamp AT TIME ZONE 'Asia/Kolkata')",
    )
    .bind(day)
    .fetch_one(&mut *tx)
    .await?;
    let to = query.to.unwrap_or(day);
    let from = query.from.unwrap_or(first.unwrap_or(to).min(to));
    let selected = totals(&mut tx, from, to).await?;
    let highlights = json!({
        "today": totals(&mut tx, day, day).await?,
        "yesterday": totals(&mut tx, yesterday, yesterday).await?,
        "month": totals(&mut tx, month, day).await?,
        "all_time": totals(&mut tx, first.unwrap_or(day), day).await?
    });
    let daily: Vec<Daily> = sqlx::query_as(
        "WITH days AS (
            SELECT day::date AS date
            FROM generate_series($1::date::timestamp, $2::date::timestamp, interval '1 day') day
            ORDER BY day DESC LIMIT $3 OFFSET $4
         )
         SELECT days.date, COALESCE(SUM(e.total_paise),0)::bigint AS total_paise,
            COALESCE(SUM(e.total_paise) FILTER (WHERE e.payment_method='cash'),0)::bigint AS cash_paise,
            COALESCE(SUM(e.total_paise) FILTER (WHERE e.payment_method='upi'),0)::bigint AS upi_paise,
            COUNT(e.id) AS receipt_count
         FROM days LEFT JOIN member_enrollments e
            ON e.received_at >= (days.date::timestamp AT TIME ZONE 'Asia/Kolkata')
           AND e.received_at < ((days.date + 1)::timestamp AT TIME ZONE 'Asia/Kolkata')
         GROUP BY days.date ORDER BY days.date DESC",
    )
    .bind(from)
    .bind(to)
    .bind(DAILY_LIMIT)
    .bind(query.daily_offset)
    .fetch_all(&mut *tx)
    .await?;
    let plans: Vec<PlanTotal> = sqlx::query_as(
        "SELECT details->>'plan_code' AS code, details->>'plan_name' AS name,
            SUM(total_paise)::bigint AS total_paise, COUNT(*) AS receipt_count
         FROM member_enrollments
         WHERE received_at >= ($1::date::timestamp AT TIME ZONE 'Asia/Kolkata')
           AND received_at < (($2::date + 1)::timestamp AT TIME ZONE 'Asia/Kolkata')
         GROUP BY details->>'plan_code', details->>'plan_name'
         ORDER BY total_paise DESC, code, name",
    )
    .bind(from)
    .bind(to)
    .fetch_all(&mut *tx)
    .await?;
    let receipts: Vec<Receipt> = sqlx::query_as(
        "SELECT 'RL-' || lpad(e.invoice_serial::text, greatest(6,length(e.invoice_serial::text)), '0') AS invoice_number,
            m.id AS member_id, 'M-' || lpad(m.serial::text, greatest(4,length(m.serial::text)), '0') AS member_number,
            m.name AS member_name,
            e.details->>'plan_name' AS plan_name, (e.details->>'months')::integer AS months,
            e.total_paise, e.payment_method, e.payment_reference, e.received_at
         FROM member_enrollments e JOIN members m ON m.id=e.member_id
         WHERE e.received_at >= ($1::date::timestamp AT TIME ZONE 'Asia/Kolkata')
           AND e.received_at < (($2::date + 1)::timestamp AT TIME ZONE 'Asia/Kolkata')
         ORDER BY e.received_at DESC, e.invoice_serial DESC LIMIT $3 OFFSET $4",
    )
    .bind(from)
    .bind(to)
    .bind(RECEIPT_LIMIT)
    .bind(query.receipt_offset)
    .fetch_all(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(json!({
        "currency":"INR", "timezone":"Asia/Kolkata", "today":day,
        "from":from, "to":to, "generated_at":Utc::now(),
        "highlights":highlights, "totals":selected,
        "daily":{"items":daily,"total":(to-from).num_days()+1,
            "limit":DAILY_LIMIT,"offset":query.daily_offset},
        "plans":plans,
        "receipts":{"items":receipts,"total":selected.receipt_count,
            "limit":RECEIPT_LIMIT,"offset":query.receipt_offset}
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_invalid_dates_and_pagination() {
        let day = NaiveDate::from_ymd_opt(2026, 11, 9).unwrap();
        for query in [
            ReportQuery {
                from: Some(day + Days::new(1)),
                ..Default::default()
            },
            ReportQuery {
                to: Some(day + Days::new(1)),
                ..Default::default()
            },
            ReportQuery {
                daily_offset: -1,
                ..Default::default()
            },
            ReportQuery {
                receipt_offset: 1_000_001,
                ..Default::default()
            },
            ReportQuery {
                from: Some(NaiveDate::from_ymd_opt(1999, 12, 31).unwrap()),
                ..Default::default()
            },
        ] {
            assert!(query.validate(day).is_err());
        }
        assert!(ReportQuery::default().validate(day).is_ok());
        assert!(
            ReportQuery {
                from: Some(day),
                to: Some(day),
                ..Default::default()
            }
            .validate(day)
            .is_ok()
        );
    }
}
