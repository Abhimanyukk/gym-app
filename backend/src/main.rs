use anyhow::Context;
use clap::{Parser, Subcommand};
use replab_server::{
    AppState, api,
    config::{self, Config},
    db,
    models::AdminInput,
    services,
};
use std::{
    io::{self, Write},
    net::IpAddr,
    path::PathBuf,
    time::Duration,
};

#[derive(Parser)]
#[command(version, about = "RepLab native Rust gym server")]
struct Cli {
    /// Explicit file; no automatic .env discovery or embedded credentials.
    #[arg(long, global = true)]
    env_file: Option<PathBuf>,
    #[command(subcommand)]
    command: Command,
}
#[derive(Subcommand)]
enum Command {
    /// Run HTTPS; --http is development-only and refuses non-loopback binding.
    Serve {
        #[arg(long)]
        http: bool,
    },
    /// Explicit, non-destructive schema migration using the owner credentials.
    Migrate,
    /// Interactive initial administrator; refuses if one already exists.
    CreateAdmin,
    /// Generate separate private runtime/owner configuration; never overwrite.
    Configure {
        #[arg(long, default_value = "/etc/replab")]
        directory: PathBuf,
        #[arg(long, default_value = "127.0.0.1")]
        bind_ip: IpAddr,
    },
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Install before SQLx can initialize a TLS client for host PostgreSQL.
    rustls::crypto::ring::default_provider()
        .install_default()
        .map_err(|_| anyhow::anyhow!("TLS provider initialization failed"))?;
    tracing_subscriber::fmt()
        .json()
        .with_env_filter("replab_server=info")
        .with_current_span(false)
        .with_span_list(false)
        .init();
    let cli = Cli::parse();
    if let Some(path) = cli.env_file {
        dotenvy::from_path_override(path).context("Cannot load configuration file")?;
    }
    if let Command::Configure { directory, bind_ip } = cli.command {
        return config::configure(&directory, bind_ip);
    }
    let pool = config::database_pool().await?;
    if matches!(cli.command, Command::Migrate) {
        // Do not print SQLx error text, which can include submitted values.
        return db::migrate(&pool).await.map_err(|_|anyhow::anyhow!("Migration failed; schema/role/configuration needs operator review. No partial migration was committed."));
    }
    let config = Config::from_env(matches!(cli.command, Command::Serve { http: true }))?;
    let state = AppState::new(pool, config).await?;
    match cli.command {
        Command::CreateAdmin => {
            fn prompt(label: &str) -> anyhow::Result<String> {
                print!("{label}");
                io::stdout().flush()?;
                let mut value = String::new();
                io::stdin().read_line(&mut value)?;
                Ok(value.trim().to_owned())
            }
            let name = prompt("Initial admin's full name: ")?;
            let email = prompt("Initial admin's email: ")?;
            let password = rpassword::prompt_password("Password (15-128 characters): ")?;
            let confirmation = rpassword::prompt_password("Confirm password: ")?;
            anyhow::ensure!(
                password == confirmation,
                "Passwords do not match. Nothing was created."
            );
            services::create_admin(&state,AdminInput{name,email,password},None).await
                .map_err(|e|anyhow::anyhow!("Initial admin was not created (HTTP {}). Check fields and initialization state.",e.status))?;
            println!("Initial admin created. Sign in through /api/v1/auth/login.");
        }
        Command::Serve { http } => {
            let app = api::router(state.clone())?;
            tracing::info!(event="starting",bind=%state.config.bind,tls=!http);
            if http {
                let listener = tokio::net::TcpListener::bind(state.config.bind).await?;
                axum::serve(
                    listener,
                    app.into_make_service_with_connect_info::<std::net::SocketAddr>(),
                )
                .with_graceful_shutdown(shutdown())
                .await?;
            } else {
                let tls = axum_server::tls_rustls::RustlsConfig::from_pem_file(
                    &state.config.cert,
                    &state.config.key,
                )
                .await
                .context("Cannot read HTTPS certificate/key")?;
                let handle = axum_server::Handle::new();
                let stop = handle.clone();
                tokio::spawn(async move {
                    shutdown().await;
                    stop.graceful_shutdown(Some(Duration::from_secs(15)));
                });
                axum_server::bind_rustls(state.config.bind, tls)
                    .handle(handle)
                    .serve(app.into_make_service_with_connect_info::<std::net::SocketAddr>())
                    .await?;
            }
            state.pool.close().await;
        }
        _ => unreachable!(),
    }
    Ok(())
}

async fn shutdown() {
    #[cfg(unix)]
    {
        let mut terminate =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
                .expect("SIGTERM handler");
        tokio::select! {_=tokio::signal::ctrl_c()=>{},_=terminate.recv()=>{}}
    }
    #[cfg(not(unix))]
    {
        let _ = tokio::signal::ctrl_c().await;
    }
}
