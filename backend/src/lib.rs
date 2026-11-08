pub mod api;
pub mod config;
pub mod db;
pub mod enrollment;
pub mod error;
pub mod models;
pub mod plans;
pub mod security;
pub mod services;

use config::Config;
use sqlx::PgPool;
use std::sync::Arc;
use tokio::sync::Semaphore;

pub struct AppState {
    pub pool: PgPool,
    pub config: Config,
    pub hashes: Arc<Semaphore>,
    pub requests: Semaphore,
    pub dummy_hash: String,
}

impl AppState {
    pub async fn new(pool: PgPool, config: Config) -> anyhow::Result<Arc<Self>> {
        // Bound Argon2 memory to at most two 64-MiB operations, off async workers.
        let hashes = Arc::new(Semaphore::new(2));
        let dummy_hash = security::hash(security::random_token(), hashes.clone())
            .await
            .map_err(|_| anyhow::anyhow!("Password initialization failed"))?;
        Ok(Arc::new(Self {
            pool,
            config,
            hashes,
            requests: Semaphore::new(32),
            dummy_hash,
        }))
    }
}
