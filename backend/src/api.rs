use crate::{
    AppState, enrollment,
    error::{ApiError, Result},
    models::*,
    plans, services,
};
use axum::{
    Json, Router,
    extract::{
        ConnectInfo, DefaultBodyLimit, Extension, FromRequest, MatchedPath, Path, Query, Request,
        State,
        rejection::{PathRejection, QueryRejection},
    },
    http::{HeaderMap, HeaderValue, StatusCode},
    middleware::{self, Next},
    response::{Html, IntoResponse, Response},
    routing::{get, post},
};
use serde::de::DeserializeOwned;
use serde_json::{Value, json};
use std::{net::SocketAddr, sync::Arc, time::Instant};
use tower_http::{catch_panic::CatchPanicLayer, cors::CorsLayer};
use uuid::Uuid;

pub fn router(state: Arc<AppState>) -> anyhow::Result<Router> {
    let origins: Vec<HeaderValue> = state
        .config
        .origins
        .iter()
        .map(|s| s.parse())
        .collect::<std::result::Result<_, _>>()?;
    let cors = CorsLayer::new()
        .allow_origin(origins)
        .allow_methods([
            axum::http::Method::GET,
            axum::http::Method::POST,
            axum::http::Method::PUT,
        ])
        .allow_headers([
            axum::http::header::AUTHORIZATION,
            axum::http::header::CONTENT_TYPE,
        ])
        .expose_headers([axum::http::HeaderName::from_static("x-request-id")]);
    Ok(Router::new()
        .route("/health/live", get(live))
        .route("/health/ready", get(ready))
        .route(
            "/docs",
            get(|| async { Html(include_str!("../docs/index.html")) }),
        )
        .route("/api/v1/auth/login", post(login))
        .route("/api/v1/auth/me", get(me))
        .route("/api/v1/auth/resume", post(resume))
        .route("/api/v1/auth/logout", post(logout))
        .route("/api/v1/auth/change-password", post(change_password))
        .route("/api/v1/admins", get(admins).post(add_admin))
        .route("/api/v1/settings", get(settings).put(update_settings))
        .route("/api/v1/members", get(members).post(add_member))
        .route("/api/v1/enrollment-options", get(enrollment_options))
        .route(
            "/api/v1/plans",
            get(plan_catalog)
                .put(update_plans)
                .layer(DefaultBodyLimit::max(128 * 1024)),
        )
        .route(
            "/api/v1/members/enroll",
            post(enroll_member).layer(DefaultBodyLimit::max(3 * 1024 * 1024)),
        )
        .route("/api/v1/enrollments/{request_id}", get(enrollment_lookup))
        .route("/api/v1/members/{member_id}", get(member))
        .route("/api/v1/dashboard/summary", get(dashboard))
        .fallback(|| async {
            ApiError::new(StatusCode::NOT_FOUND, "not_found", "Route not found.")
        })
        .layer(DefaultBodyLimit::max(16 * 1024))
        .layer(CatchPanicLayer::custom(|_| {
            ApiError::internal().into_response()
        }))
        .layer(cors)
        .layer(middleware::from_fn_with_state(
            state.clone(),
            request_middleware,
        ))
        .with_state(state))
}

#[derive(Clone)]
struct ClientIp(String);

async fn request_middleware(
    State(state): State<Arc<AppState>>,
    mut request: Request,
    next: Next,
) -> Response {
    let id = Uuid::new_v4().to_string();
    let started = Instant::now();
    let method = request.method().to_string();
    let route = request
        .extensions()
        .get::<MatchedPath>()
        .map(|p| p.as_str().to_owned())
        .unwrap_or_else(|| "unmatched".into());
    // HTTP/2 carries :authority in the URI, not necessarily a Host header.
    // An explicitly malformed Host must still fail closed, not use the fallback.
    let authority = match request.headers().get("host") {
        Some(host) => host
            .to_str()
            .ok()
            .and_then(|h| h.parse::<axum::http::uri::Authority>().ok()),
        None => request.uri().authority().cloned(),
    };
    let host = authority.map(|h| h.host().to_lowercase());
    let permit = state.requests.try_acquire();
    let mut response = if !host.is_some_and(|h| {
        state
            .config
            .hosts
            .iter()
            .any(|allowed| allowed.eq_ignore_ascii_case(&h))
    }) {
        ApiError::new(
            StatusCode::BAD_REQUEST,
            "invalid_host",
            "Host is not allowed.",
        )
        .into_response()
    } else if permit.is_err() {
        ApiError::new(
            StatusCode::SERVICE_UNAVAILABLE,
            "server_busy",
            "Server busy. Please try again.",
        )
        .into_response()
    } else {
        let client = request
            .extensions()
            .get::<ConnectInfo<SocketAddr>>()
            .map(|c| c.0.ip().to_string())
            .unwrap_or_else(|| "unknown".into());
        // Never trust client-supplied X-Forwarded-For headers.
        request.extensions_mut().insert(ClientIp(client));
        next.run(request).await
    };
    let headers = response.headers_mut();
    headers.insert("x-request-id", id.parse().unwrap());
    headers.insert("cache-control", HeaderValue::from_static("no-store"));
    headers.insert(
        "x-content-type-options",
        HeaderValue::from_static("nosniff"),
    );
    tracing::info!(request_id=%id,method=%method,route=%route,status=response.status().as_u16(),duration_ms=started.elapsed().as_millis() as u64);
    response
}

// Serde rejection text can contain submitted values. Return only a safe message.
struct SafeJson<T>(T);
impl<S, T> FromRequest<S> for SafeJson<T>
where
    S: Send + Sync,
    T: DeserializeOwned,
{
    type Rejection = ApiError;
    async fn from_request(request: Request, state: &S) -> Result<Self> {
        Json::<T>::from_request(request, state)
            .await
            .map(|Json(value)| Self(value))
            .map_err(|error| {
                if error.status() == StatusCode::PAYLOAD_TOO_LARGE {
                    ApiError::new(
                        StatusCode::PAYLOAD_TOO_LARGE,
                        "request_too_large",
                        "Request body exceeds the limit for this endpoint.",
                    )
                } else {
                    ApiError::validation()
                }
            })
    }
}

async fn live() -> Json<Value> {
    Json(json!({"status":"ok","service":"replab","version":env!("CARGO_PKG_VERSION")}))
}
async fn ready(State(state): State<Arc<AppState>>) -> Result<Json<Value>> {
    let versions: Vec<i16> = sqlx::query_scalar("SELECT version FROM replab_schema")
        .fetch_all(&state.pool)
        .await?;
    if versions != vec![4] {
        return Err(ApiError::new(
            StatusCode::SERVICE_UNAVAILABLE,
            "schema_not_ready",
            "Run the database migration.",
        ));
    }
    Ok(Json(json!({"status":"ready","database":"ok","schema":"4"})))
}
async fn login(
    State(state): State<Arc<AppState>>,
    Extension(client): Extension<ClientIp>,
    SafeJson(input): SafeJson<LoginInput>,
) -> Result<Json<Value>> {
    Ok(Json(services::login(&state, input, &client.0).await?))
}
async fn me(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Result<Json<Admin>> {
    Ok(Json(services::authenticate(&state, &headers).await?.admin))
}
async fn resume(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Result<Json<Value>> {
    Ok(Json(
        services::resume(&state, services::authenticate(&state, &headers).await?).await?,
    ))
}
async fn logout(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Result<StatusCode> {
    services::logout(&state, services::authenticate(&state, &headers).await?).await?;
    Ok(StatusCode::NO_CONTENT)
}
async fn change_password(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    SafeJson(input): SafeJson<PasswordInput>,
) -> Result<StatusCode> {
    services::change_password(
        &state,
        services::authenticate(&state, &headers).await?,
        input,
    )
    .await?;
    Ok(StatusCode::NO_CONTENT)
}
async fn admins(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<Vec<Admin>>> {
    services::authenticate(&state, &headers).await?;
    Ok(Json(
        sqlx::query_as("SELECT id,name,email,created_at FROM admins ORDER BY slot")
            .fetch_all(&state.pool)
            .await?,
    ))
}
async fn add_admin(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    SafeJson(input): SafeJson<AdminInput>,
) -> Result<(StatusCode, Json<Admin>)> {
    let auth = services::authenticate(&state, &headers).await?;
    Ok((
        StatusCode::CREATED,
        Json(services::create_admin(&state, input, Some(auth.admin.id)).await?),
    ))
}
async fn settings(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<Settings>> {
    services::authenticate(&state, &headers).await?;
    Ok(Json(services::settings(&state).await?))
}
async fn update_settings(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    SafeJson(input): SafeJson<SettingsInput>,
) -> Result<Json<Settings>> {
    let auth = services::authenticate(&state, &headers).await?;
    Ok(Json(
        services::update_settings(&state, auth.admin.id, input).await?,
    ))
}
async fn members(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    query: std::result::Result<Query<MemberQuery>, QueryRejection>,
) -> Result<Json<Value>> {
    services::authenticate(&state, &headers).await?;
    let Query(query) = query.map_err(|_| ApiError::validation())?;
    Ok(Json(services::members(&state, query).await?))
}
async fn add_member(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    SafeJson(input): SafeJson<MemberInput>,
) -> Result<(StatusCode, Json<Member>)> {
    let auth = services::authenticate(&state, &headers).await?;
    Ok((
        StatusCode::CREATED,
        Json(services::create_member(&state, auth.admin.id, input).await?),
    ))
}
async fn member(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    path: std::result::Result<Path<Uuid>, PathRejection>,
) -> Result<Json<Member>> {
    services::authenticate(&state, &headers).await?;
    let Path(id) = path.map_err(|_| ApiError::validation())?;
    Ok(Json(services::member(&state, id).await?))
}
async fn enrollment_options(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<Value>> {
    services::authenticate(&state, &headers).await?;
    Ok(Json(plans::load(&state).await?.response(true)?))
}
async fn plan_catalog(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<Value>> {
    services::authenticate(&state, &headers).await?;
    Ok(Json(plans::load(&state).await?.response(false)?))
}
async fn update_plans(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    SafeJson(input): SafeJson<plans::Catalog>,
) -> Result<Json<Value>> {
    let auth = services::authenticate(&state, &headers).await?;
    Ok(Json(
        plans::save(&state, auth.admin.id, input)
            .await?
            .response(false)?,
    ))
}
async fn enroll_member(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    SafeJson(input): SafeJson<enrollment::EnrollmentInput>,
) -> Result<(StatusCode, Json<Member>)> {
    let auth = services::authenticate(&state, &headers).await?;
    Ok((
        StatusCode::CREATED,
        Json(enrollment::create(&state, auth.admin.id, input).await?),
    ))
}
async fn enrollment_lookup(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    path: std::result::Result<Path<Uuid>, PathRejection>,
) -> Result<Json<Member>> {
    services::authenticate(&state, &headers).await?;
    let Path(id) = path.map_err(|_| ApiError::validation())?;
    Ok(Json(enrollment::lookup(&state, id).await?))
}
async fn dashboard(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Result<Json<Value>> {
    services::authenticate(&state, &headers).await?;
    let (total, active): (i64, i64) =
        sqlx::query_as("SELECT count(*),count(*) FILTER(WHERE is_active) FROM members")
            .fetch_one(&state.pool)
            .await?;
    Ok(Json(
        json!({"total_members":total,"active_member_records":active,"timezone":"Asia/Kolkata",
        "present_today":null,"active_plans":null,"revenue_today":null,"attendance_connected":false,"billing_available":false}),
    ))
}
