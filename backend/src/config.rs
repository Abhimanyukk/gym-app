use crate::security::random_token;
use anyhow::{Context, bail};
use sqlx::{
    ConnectOptions, PgPool,
    postgres::{PgConnectOptions, PgPoolOptions},
};
use std::{
    env,
    net::{IpAddr, SocketAddr},
    path::{Path, PathBuf},
    time::Duration,
};

pub const API_PORT: u16 = 8443;

#[derive(Clone)]
pub struct Config {
    pub bind: SocketAddr,
    pub hosts: Vec<String>,
    pub origins: Vec<String>,
    pub cert: PathBuf,
    pub key: PathBuf,
    pub http: bool,
}

impl Config {
    pub fn from_env(http: bool) -> anyhow::Result<Self> {
        let ip: IpAddr = env::var("API_BIND_IP")
            .unwrap_or_else(|_| "127.0.0.1".into())
            .parse()?;
        if http && !ip.is_loopback() {
            bail!("Unencrypted HTTP is permitted only on loopback.");
        }
        if !ip.is_unspecified()
            && !ip.is_loopback()
            && !matches!(ip, IpAddr::V4(v) if v.is_private())
        {
            bail!("Use a private LAN address, not a public address.");
        }
        let hosts = list("ALLOWED_HOSTS", "localhost,127.0.0.1");
        let origins = list("CORS_ORIGINS", "");
        if hosts.is_empty() || hosts.iter().chain(&origins).any(|s| s.contains('*')) {
            bail!("Hosts and origins must be explicit; wildcards are not permitted.");
        }
        Ok(Self {
            bind: SocketAddr::new(ip, API_PORT),
            hosts,
            origins,
            http,
            cert: env::var("TLS_CERT_PATH")
                .unwrap_or_else(|_| "certs/server.crt".into())
                .into(),
            key: env::var("TLS_KEY_PATH")
                .unwrap_or_else(|_| "certs/server.key".into())
                .into(),
        })
    }
}

fn list(key: &str, default: &str) -> Vec<String> {
    env::var(key)
        .unwrap_or_else(|_| default.into())
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
        .collect()
}

pub async fn database_pool() -> anyhow::Result<PgPool> {
    // Build options directly: punctuation in passwords cannot break a URL.
    let options = PgConnectOptions::new()
        .host(&env::var("POSTGRES_HOST").unwrap_or_else(|_| "127.0.0.1".into()))
        .port(
            env::var("POSTGRES_PORT")
                .unwrap_or_else(|_| "5432".into())
                .parse()?,
        )
        .database(&env::var("POSTGRES_DB").context("Set POSTGRES_DB")?)
        .username(&env::var("POSTGRES_USER").context("Set POSTGRES_USER")?)
        .password(&env::var("POSTGRES_PASSWORD").context("Set POSTGRES_PASSWORD")?)
        .options([("timezone", "UTC")])
        .disable_statement_logging();
    PgPoolOptions::new()
        .max_connections(5)
        .acquire_timeout(Duration::from_secs(10))
        .connect_with(options)
        .await
        .map_err(|_| anyhow::anyhow!("Cannot connect to PostgreSQL; check local configuration."))
}

pub fn configure(directory: &Path, ip: IpAddr) -> anyhow::Result<()> {
    if !(ip.is_loopback() || matches!(ip, IpAddr::V4(v) if v.is_private())) {
        bail!("Use a specific loopback or private IPv4 address.");
    }
    std::fs::create_dir_all(directory)?;
    let runtime = directory.join("runtime.env");
    let owner = directory.join("owner.env");
    if runtime.exists() || owner.exists() {
        bail!("Configuration exists; refusing to overwrite it.");
    }
    let common = "POSTGRES_HOST=127.0.0.1\nPOSTGRES_PORT=5432\nPOSTGRES_DB=replab\n";
    let owner_password = random_token();
    let app_password = random_token();
    write_private(
        &owner,
        &format!("{common}POSTGRES_USER=replab_owner\nPOSTGRES_PASSWORD={owner_password}\n"),
    )?;
    write_private(
        &runtime,
        &format!(
            "{common}POSTGRES_USER=replab_app\nPOSTGRES_PASSWORD={app_password}\nAPI_BIND_IP={ip}\n\
        ALLOWED_HOSTS=localhost,127.0.0.1,{ip}\nCORS_ORIGINS=\n\
        TLS_CERT_PATH=/etc/replab/server.crt\nTLS_KEY_PATH=/etc/replab/server.key\n"
        ),
    )?;
    println!("Created owner.env and runtime.env. Keep both private; never commit them.");
    Ok(())
}

fn write_private(path: &Path, contents: &str) -> anyhow::Result<()> {
    use std::io::Write;
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options.open(path)?;
    file.write_all(contents.as_bytes())?;
    file.sync_all()?;
    Ok(())
}
