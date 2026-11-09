use crate::{
    AppState,
    enrollment::{PAYEE_NAME, UPI_ID},
    error::{ApiError, Result},
    models::text,
    services,
};
use axum::http::StatusCode;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sqlx::{Postgres, Transaction};
use std::collections::{BTreeMap, HashSet};
use uuid::Uuid;

pub const MAX_MONTHS: u32 = 120;
pub const MAX_PRICE_PAISE: i64 = 1_000_000_000;

#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Plan {
    pub code: String,
    pub name: String,
    pub description: String,
    pub active: bool,
    pub prices_paise: BTreeMap<u32, i64>,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Catalog {
    pub revision: i64,
    pub plans: Vec<Plan>,
    pub training_monthly_paise: i64,
    pub insurance_monthly_paise: i64,
}

impl Catalog {
    fn validate(mut self) -> Result<Self> {
        if self.revision < 1
            || self.plans.len() > 64
            || !(0..=MAX_PRICE_PAISE).contains(&self.training_monthly_paise)
            || !(0..=MAX_PRICE_PAISE).contains(&self.insurance_monthly_paise)
        {
            return Err(ApiError::validation());
        }
        let mut codes = HashSet::new();
        let mut names = HashSet::new();
        for plan in &mut self.plans {
            plan.name = text(&plan.name, 100, true)?;
            plan.description = text(&plan.description, 300, false)?;
            if plan.code.is_empty()
                || plan.code.len() > 64
                || !plan
                    .code
                    .bytes()
                    .all(|ch| ch.is_ascii_alphanumeric() || ch == b'-' || ch == b'_')
                || !codes.insert(plan.code.clone())
                || !names.insert(plan.name.to_lowercase())
                || plan.prices_paise.is_empty()
                || plan.prices_paise.len() > 24
                || plan.prices_paise.iter().any(|(months, price)| {
                    !(1..=MAX_MONTHS).contains(months) || !(1..=MAX_PRICE_PAISE).contains(price)
                })
            {
                return Err(ApiError::validation());
            }
        }
        Ok(self)
    }

    pub(crate) fn from_row(revision: i64, mut data: Value) -> Result<Self> {
        data["revision"] = json!(revision);
        let catalog: Self = serde_json::from_value(data).map_err(|_| ApiError::internal())?;
        catalog.validate().map_err(|_| ApiError::internal())
    }

    fn data(&self) -> Result<Value> {
        let mut data = serde_json::to_value(self).map_err(|_| ApiError::internal())?;
        data.as_object_mut().unwrap().remove("revision");
        Ok(data)
    }

    pub fn response(&self, active_only: bool) -> Result<Value> {
        let mut catalog = self.clone();
        if active_only {
            catalog.plans.retain(|plan| plan.active);
        }
        let mut data = serde_json::to_value(catalog).map_err(|_| ApiError::internal())?;
        data["upi_id"] = json!(UPI_ID);
        data["payee_name"] = json!(PAYEE_NAME);
        Ok(data)
    }
}

pub async fn load(state: &AppState) -> Result<Catalog> {
    let (revision, data): (i64, Value) =
        sqlx::query_as("SELECT revision,data FROM plan_catalog WHERE id=1")
            .fetch_one(&state.pool)
            .await?;
    Catalog::from_row(revision, data)
}

pub async fn for_enrollment(tx: &mut Transaction<'_, Postgres>) -> Result<Catalog> {
    // Freeze prices through the receipt commit while allowing other enrollments.
    let (revision, data): (i64, Value) =
        sqlx::query_as("SELECT revision,data FROM plan_catalog WHERE id=1 FOR SHARE")
            .fetch_one(&mut **tx)
            .await?;
    Catalog::from_row(revision, data)
}

pub async fn save(state: &AppState, actor: Uuid, input: Catalog) -> Result<Catalog> {
    let mut input = input.validate()?;
    let mut tx = state.pool.begin().await?;
    let (revision, data): (i64, Value) =
        sqlx::query_as("SELECT revision,data FROM plan_catalog WHERE id=1 FOR UPDATE")
            .fetch_one(&mut *tx)
            .await?;
    if revision != input.revision {
        return Err(ApiError::new(
            StatusCode::CONFLICT,
            "plan_catalog_changed",
            "Plans were changed elsewhere. Reload the catalogue before saving.",
        ));
    }
    let previous = Catalog::from_row(revision, data)?;
    if previous
        .plans
        .iter()
        .any(|old| !input.plans.iter().any(|plan| plan.code == old.code))
    {
        return Err(ApiError::new(
            StatusCode::UNPROCESSABLE_ENTITY,
            "plan_archive_required",
            "Archive existing plans instead of removing their identities.",
        ));
    }
    input.revision = revision.checked_add(1).ok_or_else(ApiError::internal)?;
    sqlx::query("UPDATE plan_catalog SET revision=$1,data=$2,updated_at=now() WHERE id=1")
        .bind(input.revision)
        .bind(input.data()?)
        .execute(&mut *tx)
        .await?;
    services::audit(
        &mut tx,
        Some(actor),
        "plans.update",
        None,
        json!({"previous_revision":revision,"revision":input.revision,
            "before":previous.data()?,"after":input.data()?}),
    )
    .await?;
    tx.commit().await?;
    Ok(input)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catalogue_validates_exact_prices_durations_and_identities() {
        let catalog: Catalog = serde_json::from_value(json!({
            "revision":1,"plans":[{"code":"custom","name":" Custom Plan ","description":"",
            "active":true,"prices_paise":{"2":123456}}],
            "training_monthly_paise":0,"insurance_monthly_paise":2050
        }))
        .unwrap();
        assert_eq!(
            catalog.clone().validate().unwrap().plans[0].name,
            "Custom Plan"
        );
        for (months, price) in [(0, 100), (121, 100), (2, 0), (2, MAX_PRICE_PAISE + 1)] {
            let mut invalid = catalog.clone();
            invalid.plans[0].prices_paise = BTreeMap::from([(months, price)]);
            assert!(invalid.validate().is_err());
        }
        let mut invalid = catalog.clone();
        invalid.plans.push(invalid.plans[0].clone());
        assert!(invalid.validate().is_err());
        let mut invalid = catalog;
        invalid.training_monthly_paise = -1;
        assert!(invalid.validate().is_err());
    }
}
