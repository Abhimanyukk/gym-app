use crate::security::random_token;
use anyhow::{Context, bail};
use sqlx::{
    ConnectOptions, PgPool,
    postgres::{PgConnectOptions, PgPoolOptions},
};
use std::{
    env,
    net::{IpAddr, Ipv4Addr, SocketAddr},
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
        // A socket on all interfaces survives DHCP/Wi-Fi changes. Ignore legacy
        // API_BIND_IP values; development HTTP must still stay on loopback.
        // dover-gain-efficient: IPv4; add dual-stack listening if IPv6-only LANs are required.
        let ip = if http {
            Ipv4Addr::LOCALHOST
        } else {
            Ipv4Addr::UNSPECIFIED
        };
        let hosts = list("ALLOWED_HOSTS", "localhost,127.0.0.1,replab.local");
        let origins = list("CORS_ORIGINS", "");
        if hosts.is_empty() || hosts.iter().chain(&origins).any(|s| s.contains('*')) {
            bail!("Hosts and origins must be explicit; wildcards are not permitted.");
        }
        Ok(Self {
            bind: SocketAddr::new(ip.into(), API_PORT),
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

pub fn configure(directory: &Path, hostname: &str) -> anyhow::Result<()> {
    let hostname = server_name(hostname)?;
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
            "{common}POSTGRES_USER=replab_app\nPOSTGRES_PASSWORD={app_password}\n\
        ALLOWED_HOSTS=localhost,127.0.0.1,{hostname}\nCORS_ORIGINS=\n\
        TLS_CERT_PATH=/etc/replab/server.crt\nTLS_KEY_PATH=/etc/replab/server.key\n"
        ),
    )?;
    println!("Created owner.env and runtime.env. Keep both private; never commit them.");
    Ok(())
}

pub fn server_name(value: &str) -> anyhow::Result<String> {
    if let Ok(ip) = value.parse::<IpAddr>() {
        if matches!(ip, IpAddr::V4(v) if v.is_loopback() || v.is_private()) {
            return Ok(value.to_owned());
        }
    } else if !value.is_empty()
        && !value.bytes().all(|ch| ch.is_ascii_digit() || ch == b'.')
        && value.len() <= 253
        && value.split('.').all(|label| {
            !label.is_empty()
                && label.len() <= 63
                && label.as_bytes()[0].is_ascii_alphanumeric()
                && label.as_bytes()[label.len() - 1].is_ascii_alphanumeric()
                && label
                    .bytes()
                    .all(|ch| ch.is_ascii_alphanumeric() || ch == b'-')
        })
    {
        return Ok(value.to_ascii_lowercase());
    }
    bail!("Use a hostname without scheme/port/path, or a private IPv4 address.");
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn https_ignores_network_address_and_http_stays_local() {
        assert_eq!(
            Config::from_env(false).unwrap().bind,
            "0.0.0.0:8443".parse().unwrap()
        );
        assert_eq!(
            Config::from_env(true).unwrap().bind,
            "127.0.0.1:8443".parse().unwrap()
        );
    }

    #[test]
    fn stable_server_names_are_validated() {
        for name in [
            "lovin.local",
            "replab.local",
            "gym.example.com",
            "127.0.0.1",
            "172.20.10.3",
        ] {
            assert_eq!(server_name(name).unwrap(), name);
        }
        assert_eq!(server_name("LOVIN.local").unwrap(), "lovin.local");
        for name in [
            "",
            "https://lovin.local",
            "lovin.local:8443",
            "a,b",
            "*.local",
            "-lovin.local",
            "lovin..local",
            "0.0.0.0",
            "8.8.8.8",
            "::1",
            "999.999.999.999",
        ] {
            assert!(server_name(name).is_err(), "{name}");
        }
    }
}
