use crate::error::{ApiError, Result};
use chrono::{DateTime, FixedOffset, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Serialize, FromRow, Clone)]
pub struct Admin {
    pub id: Uuid,
    pub name: String,
    pub email: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LoginInput {
    pub email: String,
    pub password: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AdminInput {
    pub name: String,
    pub email: String,
    pub password: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PasswordInput {
    pub current_password: String,
    pub new_password: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SettingsInput {
    pub gym_name: String,
    #[serde(default)]
    pub phone: String,
    #[serde(default)]
    pub address: String,
}

#[derive(Serialize, FromRow)]
pub struct Settings {
    pub gym_name: String,
    pub phone: String,
    pub address: String,
    pub updated_at: DateTime<Utc>,
    pub timezone: String,
    pub max_admins: i32,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MemberInput {
    pub name: String,
    pub phone: String,
    #[serde(default)]
    pub email: String,
    #[serde(default)]
    pub address: String,
    #[serde(default)]
    pub emergency_phone: String,
    #[serde(default)]
    pub notes: String,
    #[serde(default = "today")]
    pub joined: NaiveDate,
    #[serde(default = "yes")]
    pub is_active: bool,
}

#[derive(Serialize, FromRow)]
pub struct Member {
    pub id: Uuid,
    pub number: String,
    pub name: String,
    pub phone: String,
    pub email: String,
    pub address: String,
    pub emergency_phone: String,
    pub notes: String,
    pub joined: NaiveDate,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MemberQuery {
    #[serde(default)]
    pub q: String,
    pub active: Option<bool>,
    #[serde(default = "fifty")]
    pub limit: i64,
    #[serde(default)]
    pub offset: i64,
}

fn fifty() -> i64 {
    50
}
fn yes() -> bool {
    true
}
pub fn today() -> NaiveDate {
    // Asia/Kolkata has a fixed +05:30 offset; persist all timestamps in UTC.
    Utc::now()
        .with_timezone(&FixedOffset::east_opt(19_800).unwrap())
        .date_naive()
}

pub fn text(value: &str, max: usize, required: bool) -> Result<String> {
    let value = value.trim();
    if value.chars().count() > max || (required && value.is_empty()) || value.contains('\0') {
        return Err(ApiError::validation());
    }
    Ok(value.to_owned())
}

pub fn email(value: &str, optional: bool) -> Result<String> {
    let value = text(value, 254, !optional)?.to_lowercase();
    if optional && value.is_empty() {
        return Ok(value);
    }
    let parts: Vec<_> = value.split('@').collect();
    if value.chars().any(char::is_whitespace)
        || parts.len() != 2
        || parts[0].is_empty()
        || !parts[1].contains('.')
        || parts[1].starts_with('.')
        || parts[1].ends_with('.')
    {
        return Err(ApiError::validation());
    }
    Ok(value)
}

pub fn phone(value: &str, optional: bool) -> Result<String> {
    let value = text(value, 24, !optional)?;
    if optional && value.is_empty() {
        return Ok(value);
    }
    let number = value.strip_prefix('+').unwrap_or(&value);
    let digits = number.bytes().filter(u8::is_ascii_digit).count();
    if !(7..=15).contains(&digits)
        || !number
            .chars()
            .all(|c| c.is_ascii_digit() || " ()-".contains(c))
    {
        return Err(ApiError::validation());
    }
    Ok(value)
}

impl MemberInput {
    pub fn validate(mut self) -> Result<Self> {
        self.name = text(&self.name, 100, true)?;
        self.phone = phone(&self.phone, false)?;
        self.email = email(&self.email, true)?;
        self.address = text(&self.address, 500, false)?;
        self.emergency_phone = phone(&self.emergency_phone, true)?;
        self.notes = text(&self.notes, 2000, false)?;
        if self.joined > today() {
            return Err(ApiError::validation());
        }
        Ok(self)
    }
}
