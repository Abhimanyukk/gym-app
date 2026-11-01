use crate::error::{ApiError, Result};
use argon2::{
    Algorithm, Argon2, Params, PasswordHash, PasswordHasher, PasswordVerifier, Version,
    password_hash::SaltString,
};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use rand::{RngCore, rngs::OsRng};
use sha2::{Digest, Sha256};
use std::sync::Arc;
use tokio::sync::Semaphore;
use unicode_normalization::UnicodeNormalization;

pub fn random_token() -> String {
    let mut bytes = [0u8; 32];
    OsRng.fill_bytes(&mut bytes);
    URL_SAFE_NO_PAD.encode(bytes)
}

pub fn digest(value: &str) -> String {
    format!("{:x}", Sha256::digest(value.as_bytes()))
}

pub fn password(value: &str, new: bool) -> Result<String> {
    if !(1..=128).contains(&value.chars().count()) {
        return Err(ApiError::validation());
    }
    let normalized: String = value.nfc().collect();
    if new && (normalized.chars().count() < 15 || normalized.trim().is_empty()) {
        return Err(ApiError::validation());
    }
    Ok(normalized)
}

fn argon() -> Argon2<'static> {
    // Matches pwdlib's previous Argon2id cost; existing hashes remain usable.
    Argon2::new(
        Algorithm::Argon2id,
        Version::V0x13,
        Params::new(65_536, 3, 4, None).unwrap(),
    )
}

pub async fn hash(value: String, slots: Arc<Semaphore>) -> Result<String> {
    let permit = slots
        .acquire_owned()
        .await
        .map_err(|_| ApiError::internal())?;
    tokio::task::spawn_blocking(move || {
        let _permit = permit;
        let salt = SaltString::generate(&mut OsRng);
        argon()
            .hash_password(value.as_bytes(), &salt)
            .map(|hash| hash.to_string())
            .map_err(|_| ApiError::internal())
    })
    .await
    .map_err(|_| ApiError::internal())?
}

pub async fn verify(value: String, encoded: String, slots: Arc<Semaphore>) -> Result<bool> {
    let permit = slots
        .acquire_owned()
        .await
        .map_err(|_| ApiError::internal())?;
    tokio::task::spawn_blocking(move || {
        let _permit = permit;
        let hash = PasswordHash::new(&encoded).map_err(|_| ApiError::internal())?;
        // Refuse corrupted/unreasonably expensive stored parameters before allocating.
        let params = Params::try_from(&hash).map_err(|_| ApiError::internal())?;
        if params.m_cost() > 65_536 || params.t_cost() > 3 || params.p_cost() > 4 {
            return Err(ApiError::internal());
        }
        Ok(argon().verify_password(value.as_bytes(), &hash).is_ok())
    })
    .await
    .map_err(|_| ApiError::internal())?
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn passwords_and_tokens() {
        let slots = Arc::new(Semaphore::new(2));
        let value = password("a long password café", true).unwrap();
        let encoded = hash(value.clone(), slots.clone())
            .await
            .unwrap_or_else(|_| panic!("hash failed"));
        assert!(encoded.starts_with("$argon2id$"));
        assert!(
            verify(
                password("a long password cafe\u{301}", false).unwrap(),
                encoded.clone(),
                slots.clone()
            )
            .await
            .unwrap_or(false)
        );
        assert!(!verify("wrong".into(), encoded, slots).await.unwrap_or(true));
        assert!(password("short", true).is_err());
        assert_ne!(random_token(), random_token());
        assert_eq!(
            digest("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }
}
