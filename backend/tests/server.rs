use axum::{
    Router,
    body::{Body, to_bytes},
    extract::ConnectInfo,
    http::{Request, StatusCode},
};
use replab_server::{AppState, api, config::Config, db, models::AdminInput, services};
use serde_json::{Value, json};
use sqlx::{
    PgPool,
    postgres::{PgConnectOptions, PgPoolOptions},
};
use std::env;
use tower::ServiceExt;

async fn pool(user: &str, password: &str) -> PgPool {
    PgPoolOptions::new()
        .max_connections(5)
        .connect_with(
            PgConnectOptions::new()
                .host(&env::var("POSTGRES_HOST").unwrap_or_else(|_| "db".into()))
                .database("replab_test")
                .username(user)
                .password(password),
        )
        .await
        .expect("isolated PostgreSQL must be running")
}

async fn call(
    app: &Router,
    method: &str,
    path: &str,
    token: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut builder = Request::builder()
        .method(method)
        .uri(path)
        .header("host", "localhost");
    if let Some(token) = token {
        builder = builder.header("authorization", format!("Bearer {token}"));
    }
    let mut request = if let Some(body) = body {
        builder
            .header("content-type", "application/json")
            .body(Body::from(body.to_string()))
            .unwrap()
    } else {
        builder.body(Body::empty()).unwrap()
    };
    request.extensions_mut().insert(ConnectInfo(
        "192.168.1.20:12345"
            .parse::<std::net::SocketAddr>()
            .unwrap(),
    ));
    let response = app.clone().oneshot(request).await.unwrap();
    assert!(response.headers().contains_key("x-request-id"));
    assert_eq!(response.headers()["cache-control"], "no-store");
    let status = response.status();
    let bytes = to_bytes(response.into_body(), 1_048_576).await.unwrap();
    let value = if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes).expect("JSON API response")
    };
    (status, value)
}

async fn sign_in(app: &Router, password: &str) -> String {
    let (status, body) = call(
        app,
        "POST",
        "/api/v1/auth/login",
        None,
        Some(json!({"password":password})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body["access_token"].as_str().unwrap().to_owned()
}

#[tokio::test]
async fn postgres_api_contract_security_and_legacy_adoption() {
    assert_eq!(Config::from_env(true).unwrap().bind.port(), 8443);
    assert!(Config::from_env(false).unwrap().bind.ip().is_unspecified());
    assert!(Config::from_env(true).unwrap().bind.ip().is_loopback());
    // No fixture reset/migration may ever touch the deployment DB.
    assert_eq!(
        env::var("POSTGRES_DB").as_deref(),
        Ok("replab_test"),
        "Tests require the isolated replab_test DB."
    );
    let owner = pool("replab_owner", &env::var("TEST_OWNER_PASSWORD").unwrap()).await;
    let superuser = pool("postgres", &env::var("TEST_ADMIN_PASSWORD").unwrap()).await;
    let runtime = pool("replab_app", &env::var("POSTGRES_PASSWORD").unwrap()).await;
    let config = Config {
        bind: "127.0.0.1:8443".parse().unwrap(),
        hosts: vec!["localhost".into(), "lovin.local".into()],
        origins: vec!["http://localhost:8080".into()],
        cert: "unused".into(),
        key: "unused".into(),
        http: true,
    };
    let state = AppState::new(runtime.clone(), config).await.unwrap();
    let app = api::router(state.clone()).unwrap();
    for (authority, expected) in [
        ("localhost:8443", StatusCode::OK),
        ("lovin.local:8443", StatusCode::OK),
        ("LOVIN.local:8443", StatusCode::OK),
        ("untrusted.example:8443", StatusCode::BAD_REQUEST),
    ] {
        let request = Request::builder()
            .version(axum::http::Version::HTTP_2)
            .uri(format!("https://{authority}/health/live"))
            .body(Body::empty())
            .unwrap();
        assert_eq!(
            app.clone().oneshot(request).await.unwrap().status(),
            expected
        );
    }
    assert_eq!(
        call(&app, "GET", "/health/live", None, None).await.0,
        StatusCode::OK
    );
    assert_eq!(
        call(&app, "GET", "/health/ready", None, None).await.0,
        StatusCode::SERVICE_UNAVAILABLE
    );
    db::migrate(&owner).await.unwrap();
    db::migrate(&owner).await.unwrap();
    assert_eq!(
        call(&app, "GET", "/health/ready", None, None).await.1["schema"],
        "4"
    );
    for sql in [
        "CREATE TABLE should_not_exist(id integer)",
        "DELETE FROM audit_logs",
        "UPDATE audit_logs SET action='tampered'",
        "DELETE FROM admins",
        "DELETE FROM plan_catalog",
    ] {
        assert!(sqlx::query(sql).execute(&runtime).await.is_err(), "{sql}");
    }
    let password = "a long test password 123";
    services::create_admin(
        &state,
        AdminInput {
            name: "Test Owner".into(),
            email: " OWNER@example.com ".into(),
            password: password.into(),
        },
        None,
    )
    .await
    .unwrap();
    assert!(
        services::create_admin(
            &state,
            AdminInput {
                name: "Again".into(),
                email: "again@example.com".into(),
                password: password.into()
            },
            None
        )
        .await
        .is_err()
    );
    for path in [
        "/api/v1/auth/me",
        "/api/v1/admins",
        "/api/v1/settings",
        "/api/v1/plans",
        "/api/v1/members",
        "/api/v1/dashboard/summary",
    ] {
        assert_eq!(
            call(&app, "GET", path, None, None).await.0,
            StatusCode::UNAUTHORIZED
        );
    }
    let token = sign_in(&app, password).await;
    let hash: String = sqlx::query_scalar("SELECT password_hash FROM admins LIMIT 1")
        .fetch_one(&owner)
        .await
        .unwrap();
    assert!(hash.starts_with("$argon2id$v=19$m=65536,t=3,p=4$"));
    let stored: String = sqlx::query_scalar("SELECT token_hash FROM login_sessions LIMIT 1")
        .fetch_one(&owner)
        .await
        .unwrap();
    assert_ne!(stored, token);
    let wrong = call(
        &app,
        "POST",
        "/api/v1/auth/login",
        None,
        Some(json!({"email":"owner@example.com","password":"wrong"})),
    )
    .await;
    let unknown = call(
        &app,
        "POST",
        "/api/v1/auth/login",
        None,
        Some(json!({"email":"unknown@example.com","password":"wrong"})),
    )
    .await;
    assert_eq!(wrong, unknown);
    assert_eq!(wrong.0, StatusCode::UNAUTHORIZED);

    let mut tasks = Vec::new();
    for i in 0..4 {
        let app = app.clone();
        let token = token.clone();
        tasks.push(tokio::spawn(async move {
            call(&app,"POST","/api/v1/admins",Some(&token),Some(json!({
                "name":format!("Admin {i}"),"email":format!("admin{i}@example.com"),"password":"a long test password 123"
            }))).await.0
        }));
    }
    let mut created = 0;
    let mut rejected = 0;
    for task in tasks {
        match task.await.unwrap() {
            StatusCode::CREATED => created += 1,
            StatusCode::CONFLICT => rejected += 1,
            other => panic!("unexpected status {other}"),
        }
    }
    assert_eq!((created, rejected), (0, 4));
    let duplicate = call(
        &app,
        "POST",
        "/api/v1/admins",
        Some(&token),
        Some(json!({"name":"Duplicate","email":"OWNER@example.com","password":password})),
    )
    .await;
    assert_eq!(duplicate.1["error"]["code"], "duplicate_admin");
    assert!(
        !call(&app, "GET", "/api/v1/admins", Some(&token), None)
            .await
            .1
            .to_string()
            .contains("password")
    );
    assert!(sqlx::query("INSERT INTO admins(id,slot,name,email,password_hash) VALUES($1,2,'Blocked','second@example.com','invalid')")
        .bind(uuid::Uuid::new_v4()).execute(&owner).await.is_err());

    let settings = call(
        &app,
        "PUT",
        "/api/v1/settings",
        Some(&token),
        Some(json!({"gym_name":"Test Gym","phone":"+91 9876543210","address":"Test address"})),
    )
    .await;
    assert_eq!(settings.0, StatusCode::OK);
    assert_eq!(settings.1["timezone"], "Asia/Kolkata");
    assert_eq!(settings.1["max_admins"], 1);
    let resumed = call(&app, "POST", "/api/v1/auth/resume", Some(&token), None).await;
    assert_eq!(resumed.0, StatusCode::OK, "{}", resumed.1);
    assert_eq!(resumed.1["admin"]["email"], "owner@example.com");
    let expires: chrono::DateTime<chrono::Utc> =
        sqlx::query_scalar("SELECT expires_at FROM login_sessions WHERE token_hash=$1")
            .bind(replab_server::security::digest(&token))
            .fetch_one(&owner)
            .await
            .unwrap();
    assert!(expires > chrono::Utc::now() + chrono::Duration::days(89));
    let mut member_id = String::new();
    for (name, active) in [("Alice Test", true), ("Bob Test", false)] {
        let result = call(
            &app,
            "POST",
            "/api/v1/members",
            Some(&token),
            Some(json!({"name":name,"phone":"+91 9876543210","is_active":active})),
        )
        .await;
        assert_eq!(result.0, StatusCode::CREATED, "{}", result.1);
        member_id = result.1["id"].as_str().unwrap().to_owned();
        assert_eq!(
            call(
                &app,
                "GET",
                &format!("/api/v1/members/{member_id}"),
                Some(&token),
                None
            )
            .await
            .1["name"],
            name
        );
    }
    for (query, total) in [
        ("q=alice", 1),
        ("q=M-0002", 1),
        ("q=%25", 0),
        ("q=M-%EF%BC%91%EF%BC%92", 0),
        ("q=M-9999999999999999999999999999999", 0),
        ("active=true", 1),
    ] {
        assert_eq!(
            call(
                &app,
                "GET",
                &format!("/api/v1/members?{query}"),
                Some(&token),
                None
            )
            .await
            .1["total"],
            total
        );
    }
    assert_eq!(
        call(
            &app,
            "GET",
            "/api/v1/members?limit=1&offset=1",
            Some(&token),
            None
        )
        .await
        .1["items"][0]["number"],
        "M-0002"
    );
    assert_eq!(
        call(&app, "GET", "/api/v1/members?limit=101", Some(&token), None)
            .await
            .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(
        call(
            &app,
            "GET",
            "/api/v1/members/not-a-uuid",
            Some(&token),
            None
        )
        .await
        .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    let dashboard = call(&app, "GET", "/api/v1/dashboard/summary", Some(&token), None)
        .await
        .1;
    assert_eq!(dashboard["total_members"], 2);
    assert_eq!(dashboard["active_member_records"], 1);
    assert!(dashboard["present_today"].is_null());
    assert!(dashboard["revenue_today"].is_null());

    let invalid = call(
        &app,
        "POST",
        "/api/v1/admins",
        Some(&token),
        Some(json!({"name":"","email":"bad","password":"TOP-SECRET","other":"TOP-SECRET"})),
    )
    .await;
    assert_eq!(invalid.0, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(!invalid.1.to_string().contains("TOP-SECRET"));
    sqlx::query("REVOKE INSERT ON audit_logs FROM replab_app")
        .execute(&owner)
        .await
        .unwrap();
    let failed = call(
        &app,
        "POST",
        "/api/v1/members",
        Some(&token),
        Some(json!({"name":"Rollback","phone":"+91 9876543210"})),
    )
    .await;
    sqlx::query("GRANT INSERT ON audit_logs TO replab_app")
        .execute(&owner)
        .await
        .unwrap();
    assert_eq!(failed.0, StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(
        call(&app, "GET", "/api/v1/members", Some(&token), None)
            .await
            .1["total"],
        2
    );
    let oversized = call(
        &app,
        "POST",
        "/api/v1/auth/login",
        None,
        Some(json!({"email":"owner@example.com","password":"x".repeat(20_000)})),
    )
    .await;
    assert_eq!(oversized.0, StatusCode::PAYLOAD_TOO_LARGE);
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/health/live")
                .header("host", "untrusted.example")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);

    let other = sign_in(&app, password).await;
    let changed = "another long test password";
    assert_eq!(
        call(
            &app,
            "POST",
            "/api/v1/auth/change-password",
            Some(&token),
            Some(json!({"current_password":"wrong","new_password":changed}))
        )
        .await
        .0,
        StatusCode::BAD_REQUEST
    );
    assert_eq!(
        call(
            &app,
            "POST",
            "/api/v1/auth/change-password",
            Some(&token),
            Some(json!({"current_password":password,"new_password":password}))
        )
        .await
        .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(
        call(
            &app,
            "POST",
            "/api/v1/auth/change-password",
            Some(&token),
            Some(json!({"current_password":password,"new_password":changed}))
        )
        .await
        .0,
        StatusCode::NO_CONTENT
    );
    for token in [&token, &other] {
        assert_eq!(
            call(&app, "GET", "/api/v1/auth/me", Some(token), None)
                .await
                .0,
            StatusCode::UNAUTHORIZED
        );
        assert_eq!(
            call(&app, "POST", "/api/v1/auth/resume", Some(token), None)
                .await
                .0,
            StatusCode::UNAUTHORIZED
        );
    }
    let new = sign_in(&app, changed).await;
    assert_eq!(
        call(&app, "POST", "/api/v1/auth/logout", Some(&new), None)
            .await
            .0,
        StatusCode::NO_CONTENT
    );
    assert_eq!(
        call(&app, "GET", "/api/v1/auth/me", Some(&new), None)
            .await
            .0,
        StatusCode::UNAUTHORIZED
    );
    let new = sign_in(&app, changed).await;
    sqlx::query("UPDATE login_sessions SET expires_at=now()-interval '1 second'")
        .execute(&owner)
        .await
        .unwrap();
    assert_eq!(
        call(&app, "GET", "/api/v1/auth/me", Some(&new), None)
            .await
            .0,
        StatusCode::UNAUTHORIZED
    );

    sqlx::query("DELETE FROM login_buckets")
        .execute(&superuser)
        .await
        .unwrap();
    for _ in 0..10 {
        assert_eq!(
            call(
                &app,
                "POST",
                "/api/v1/auth/login",
                None,
                Some(json!({"email":"owner@example.com","password":"wrong"}))
            )
            .await
            .0,
            StatusCode::UNAUTHORIZED
        );
    }
    assert_eq!(
        call(
            &app,
            "POST",
            "/api/v1/auth/login",
            None,
            Some(json!({"email":"owner@example.com","password":changed}))
        )
        .await
        .0,
        StatusCode::TOO_MANY_REQUESTS
    );
    // Restart-like replacement of state must not lose the database limiter.
    let new_state = AppState::new(runtime.clone(), state.config.clone())
        .await
        .unwrap();
    let restarted = api::router(new_state).unwrap();
    assert_eq!(
        call(
            &restarted,
            "POST",
            "/api/v1/auth/login",
            None,
            Some(json!({"email":"owner@example.com","password":changed}))
        )
        .await
        .0,
        StatusCode::TOO_MANY_REQUESTS
    );
    sqlx::query("UPDATE login_buckets SET started_at=now()-interval '16 minutes'")
        .execute(&superuser)
        .await
        .unwrap();
    let token = sign_in(&restarted, changed).await;
    assert_eq!(
        call(
            &restarted,
            "GET",
            &format!("/api/v1/members/{member_id}"),
            Some(&token),
            None
        )
        .await
        .0,
        StatusCode::OK
    );

    // Simulate the old marker on exactly the same business schema, then adopt it.
    // Only the isolated superuser may remove the test marker; production has no reset command.
    sqlx::raw_sql("DROP TABLE plan_catalog; DROP TABLE member_enrollments; DROP TABLE replab_schema; CREATE TABLE alembic_version(version_num varchar(32) PRIMARY KEY);
        ALTER TABLE alembic_version OWNER TO replab_owner;
        INSERT INTO alembic_version VALUES('unexpected');").execute(&superuser).await.unwrap();
    assert!(db::migrate(&owner).await.is_err());
    sqlx::query("UPDATE alembic_version SET version_num='0001'")
        .execute(&superuser)
        .await
        .unwrap();
    db::migrate(&owner).await.unwrap();
    assert_eq!(
        call(&restarted, "GET", "/api/v1/members", Some(&token), None)
            .await
            .1["total"],
        2
    );
    assert_eq!(
        call(&restarted, "GET", "/api/v1/settings", Some(&token), None)
            .await
            .1["gym_name"],
        "Test Gym"
    );
    // A schema-1 installation with multiple admins is refused atomically.
    // Only this isolated test superuser may add/remove the synthetic account.
    sqlx::raw_sql(
        "DROP TABLE plan_catalog; DROP TABLE member_enrollments;
        ALTER TABLE admins DROP CONSTRAINT ck_admin_slot;
        ALTER TABLE admins ADD CONSTRAINT ck_admin_slot CHECK(slot BETWEEN 1 AND 3);
        UPDATE replab_schema SET version=1;",
    )
    .execute(&superuser)
    .await
    .unwrap();
    sqlx::query("INSERT INTO admins(id,slot,name,email,password_hash) VALUES($1,2,'Extra fixture','extra@example.com','fixture')")
        .bind(uuid::Uuid::new_v4()).execute(&superuser).await.unwrap();
    assert!(db::migrate(&owner).await.is_err());
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM admins")
            .fetch_one(&owner)
            .await
            .unwrap(),
        2
    );
    assert_eq!(
        sqlx::query_scalar::<_, i16>("SELECT version FROM replab_schema")
            .fetch_one(&owner)
            .await
            .unwrap(),
        1
    );
    sqlx::query("DELETE FROM admins WHERE slot=2")
        .execute(&superuser)
        .await
        .unwrap();
    db::migrate(&owner).await.unwrap();
    enrollment_contract(&restarted, &owner, &runtime, &token).await;
    println!(
        "PostgreSQL API, permissions, validation, audit rollback, session/rate persistence and legacy adoption passed."
    );
}

async fn enrollment_contract(app: &Router, owner: &PgPool, runtime: &PgPool, token: &str) {
    use base64::{Engine, engine::general_purpose::STANDARD};
    let options = call(app, "GET", "/api/v1/enrollment-options", Some(token), None).await;
    assert_eq!(options.0, StatusCode::OK);
    assert_eq!(options.1["upi_id"], "8943521009@yescred");
    assert_eq!(options.1["plans"][1]["prices_paise"]["12"], 1800000);
    assert_eq!(
        call(app, "GET", "/api/v1/enrollment-options", None, None)
            .await
            .0,
        StatusCode::UNAUTHORIZED
    );
    use rand::RngCore;
    let mut pixels = vec![0; 256 * 256 * 3];
    rand::thread_rng().fill_bytes(&mut pixels);
    let image = image::RgbImage::from_raw(256, 256, pixels).unwrap();
    let mut bytes = std::io::Cursor::new(Vec::new());
    image::DynamicImage::ImageRgb8(image)
        .write_to(&mut bytes, image::ImageFormat::Png)
        .unwrap();
    let id = uuid::Uuid::new_v4();
    let body = json!({
        "request_id":id,"member":{"name":"Enrolled member","phone":"+91 9876543210",
            "address":"Synthetic address","emergency_phone":"+91 9876543211"},
        "photo_base64":STANDARD.encode(bytes.into_inner()),"plan_code":"gold","months":3,
        "starts_on":replab_server::models::today(),"training_months":1,"insurance_months":2,
        "payment_method":"upi","payment_reference":"SYNTHETIC-UPI-REF","payment_confirmed":true,
        "catalog_revision":options.1["revision"]
    });
    for (field, value) in [
        ("photo_base64", json!("not-an-image")),
        ("months", json!(2)),
        ("training_months", json!(4)),
        ("insurance_months", json!(4)),
        ("payment_method", json!("card")),
        ("payment_confirmed", json!(false)),
    ] {
        let mut invalid = body.clone();
        invalid[field] = value;
        assert_eq!(
            call(
                app,
                "POST",
                "/api/v1/members/enroll",
                Some(token),
                Some(invalid)
            )
            .await
            .0,
            StatusCode::UNPROCESSABLE_ENTITY,
            "{field}"
        );
    }
    for field in ["address", "emergency_phone"] {
        let mut invalid = body.clone();
        invalid["member"][field] = json!("");
        assert_eq!(
            call(
                app,
                "POST",
                "/api/v1/members/enroll",
                Some(token),
                Some(invalid)
            )
            .await
            .0,
            StatusCode::UNPROCESSABLE_ENTITY
        );
    }
    let mut tampered = body.clone();
    tampered["total_paise"] = json!(1);
    assert_eq!(
        call(
            app,
            "POST",
            "/api/v1/members/enroll",
            Some(token),
            Some(tampered)
        )
        .await
        .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    let before: i64 = sqlx::query_scalar("SELECT count(*) FROM members")
        .fetch_one(owner)
        .await
        .unwrap();
    sqlx::query("REVOKE INSERT ON audit_logs FROM replab_app")
        .execute(owner)
        .await
        .unwrap();
    let failed = call(
        app,
        "POST",
        "/api/v1/members/enroll",
        Some(token),
        Some(body.clone()),
    )
    .await;
    sqlx::query("GRANT INSERT ON audit_logs TO replab_app")
        .execute(owner)
        .await
        .unwrap();
    assert_eq!(failed.0, StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM members")
            .fetch_one(owner)
            .await
            .unwrap(),
        before
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM member_enrollments")
            .fetch_one(owner)
            .await
            .unwrap(),
        0
    );
    let (a, b) = tokio::join!(
        call(
            app,
            "POST",
            "/api/v1/members/enroll",
            Some(token),
            Some(body.clone())
        ),
        call(
            app,
            "POST",
            "/api/v1/members/enroll",
            Some(token),
            Some(body.clone())
        )
    );
    assert_eq!(a.0, StatusCode::CREATED, "{}", a.1);
    assert_eq!(b.0, StatusCode::CREATED, "{}", b.1);
    assert_eq!(a.1["id"], b.1["id"]);
    assert_eq!(a.1["enrollment"]["total_paise"], 1010000);
    assert_eq!(a.1["enrollment"]["payment_verification"], "staff_confirmed");
    assert!(
        a.1["enrollment"]["invoice_number"]
            .as_str()
            .unwrap()
            .starts_with("RL-")
    );
    let photo = STANDARD
        .decode(a.1["photo_base64"].as_str().unwrap())
        .unwrap();
    assert_eq!(&photo[..2], &[255, 216]); // Re-encoded JPEG, not submitted PNG/metadata.
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM members")
            .fetch_one(owner)
            .await
            .unwrap(),
        before + 1
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM member_enrollments")
            .fetch_one(owner)
            .await
            .unwrap(),
        1
    );
    let lookup = call(
        app,
        "GET",
        &format!("/api/v1/enrollments/{id}"),
        Some(token),
        None,
    )
    .await;
    assert_eq!(lookup.1["id"], a.1["id"]);
    let mut changed = body.clone();
    changed["member"]["name"] = json!("Different member");
    assert_eq!(
        call(
            app,
            "POST",
            "/api/v1/members/enroll",
            Some(token),
            Some(changed)
        )
        .await
        .0,
        StatusCode::CONFLICT
    );
    for sql in [
        "UPDATE member_enrollments SET total_paise=1",
        "DELETE FROM member_enrollments",
    ] {
        assert!(sqlx::query(sql).execute(runtime).await.is_err());
    }
    plans_contract(app, owner, token, &body, &a.1).await;
}

async fn plans_contract(
    app: &Router,
    owner: &PgPool,
    token: &str,
    enrollment: &Value,
    original_member: &Value,
) {
    let catalog = call(app, "GET", "/api/v1/plans", Some(token), None).await;
    assert_eq!(catalog.0, StatusCode::OK);
    assert_eq!(catalog.1["revision"], 1);
    let mut draft = catalog.1.clone();
    draft.as_object_mut().unwrap().remove("upi_id");
    draft.as_object_mut().unwrap().remove("payee_name");
    assert_eq!(
        call(app, "PUT", "/api/v1/plans", None, Some(draft.clone()))
            .await
            .0,
        StatusCode::UNAUTHORIZED,
    );
    for (prices, name) in [
        (json!({"0":100}), "Invalid duration"),
        (json!({"121":100}), "Invalid duration"),
        (json!({"2":0}), "Zero base price"),
        (json!({"2":-1}), "Negative price"),
        (json!({"2":123.45}), "Floating-point price"),
        (json!({"2":1000000001_i64}), "Excessive price"),
        (json!({}), "Missing prices"),
    ] {
        let mut invalid = draft.clone();
        invalid["plans"][0]["prices_paise"] = prices;
        let result = call(app, "PUT", "/api/v1/plans", Some(token), Some(invalid)).await;
        assert_eq!(
            result.0,
            StatusCode::UNPROCESSABLE_ENTITY,
            "{name}: {}",
            result.1
        );
    }
    let mut invalid = draft.clone();
    invalid["plans"][1]["name"] = invalid["plans"][0]["name"].clone();
    assert_eq!(
        call(app, "PUT", "/api/v1/plans", Some(token), Some(invalid))
            .await
            .0,
        StatusCode::UNPROCESSABLE_ENTITY,
    );
    let mut invalid = draft.clone();
    invalid["plans"].as_array_mut().unwrap().remove(1);
    assert_eq!(
        call(app, "PUT", "/api/v1/plans", Some(token), Some(invalid))
            .await
            .1["error"]["code"],
        "plan_archive_required",
    );
    draft["plans"][0]["name"] = json!("Strength Flex");
    draft["plans"][0]["prices_paise"]["1"] = json!(135050);
    draft["plans"][1]["active"] = json!(false);
    draft["plans"].as_array_mut().unwrap().push(json!({
        "code":"weekend","name":"Weekend Plan","description":"Custom two-month access",
        "active":true,"prices_paise":{"2":250025}
    }));
    draft["training_monthly_paise"] = json!(400075);
    draft["insurance_monthly_paise"] = json!(25010);
    let mut concurrent = draft.clone();
    concurrent["plans"][0]["description"] = json!("Concurrent edit");
    let (a, b) = tokio::join!(
        call(app, "PUT", "/api/v1/plans", Some(token), Some(draft)),
        call(app, "PUT", "/api/v1/plans", Some(token), Some(concurrent)),
    );
    assert!(
        (a.0 == StatusCode::OK && b.0 == StatusCode::CONFLICT)
            || (b.0 == StatusCode::OK && a.0 == StatusCode::CONFLICT)
    );
    let saved = if a.0 == StatusCode::OK { a.1 } else { b.1 };
    assert_eq!(saved["revision"], 2);
    let options = call(app, "GET", "/api/v1/enrollment-options", Some(token), None)
        .await
        .1;
    assert_eq!(options["plans"].as_array().unwrap().len(), 2);
    assert_eq!(options["plans"][1]["code"], "weekend");
    assert_eq!(options["training_monthly_paise"], 400075);

    let mut next = saved.clone();
    next.as_object_mut().unwrap().remove("upi_id");
    next.as_object_mut().unwrap().remove("payee_name");
    next["training_monthly_paise"] = json!(1);
    sqlx::query("REVOKE INSERT ON audit_logs FROM replab_app")
        .execute(owner)
        .await
        .unwrap();
    let failed = call(app, "PUT", "/api/v1/plans", Some(token), Some(next)).await;
    sqlx::query("GRANT INSERT ON audit_logs TO replab_app")
        .execute(owner)
        .await
        .unwrap();
    assert_eq!(failed.0, StatusCode::SERVICE_UNAVAILABLE);
    db::migrate(owner).await.unwrap();
    assert_eq!(
        call(app, "GET", "/api/v1/plans", Some(token), None).await.1,
        saved
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM audit_logs WHERE action='plans.update'")
            .fetch_one(owner)
            .await
            .unwrap(),
        1,
    );

    let id = original_member["id"].as_str().unwrap();
    let historical = call(
        app,
        "GET",
        &format!("/api/v1/members/{id}"),
        Some(token),
        None,
    )
    .await
    .1;
    assert_eq!(historical["enrollment"], original_member["enrollment"]);
    let retried = call(
        app,
        "POST",
        "/api/v1/members/enroll",
        Some(token),
        Some(enrollment.clone()),
    )
    .await;
    assert_eq!(retried.0, StatusCode::CREATED);
    assert_eq!(retried.1["enrollment"], original_member["enrollment"]);

    let mut fresh = enrollment.clone();
    fresh["request_id"] = json!(uuid::Uuid::new_v4());
    fresh["member"]["name"] = json!("Custom plan member");
    fresh["plan_code"] = json!("weekend");
    fresh["months"] = json!(2);
    let before: i64 = sqlx::query_scalar("SELECT count(*) FROM members")
        .fetch_one(owner)
        .await
        .unwrap();
    let stale = call(
        app,
        "POST",
        "/api/v1/members/enroll",
        Some(token),
        Some(fresh.clone()),
    )
    .await;
    assert_eq!(stale.1["error"]["code"], "plan_catalog_changed");
    fresh["catalog_revision"] = saved["revision"].clone();
    let mut missing_revision = fresh.clone();
    missing_revision
        .as_object_mut()
        .unwrap()
        .remove("catalog_revision");
    assert_eq!(
        call(
            app,
            "POST",
            "/api/v1/members/enroll",
            Some(token),
            Some(missing_revision)
        )
        .await
        .1["error"]["code"],
        "app_update_required",
    );
    let mut archived = fresh.clone();
    archived["plan_code"] = json!("gold");
    assert_eq!(
        call(
            app,
            "POST",
            "/api/v1/members/enroll",
            Some(token),
            Some(archived)
        )
        .await
        .1["error"]["code"],
        "plan_unavailable",
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM members")
            .fetch_one(owner)
            .await
            .unwrap(),
        before,
    );
    let registered = call(
        app,
        "POST",
        "/api/v1/members/enroll",
        Some(token),
        Some(fresh),
    )
    .await;
    assert_eq!(registered.0, StatusCode::CREATED, "{}", registered.1);
    assert_eq!(registered.1["enrollment"]["plan_name"], "Weekend Plan");
    assert_eq!(registered.1["enrollment"]["total_paise"], 700120);

    // Simulate a populated schema-3 Pi upgrade; receipts are not rewritten.
    sqlx::raw_sql("DROP TABLE plan_catalog; UPDATE replab_schema SET version=3;")
        .execute(owner)
        .await
        .unwrap();
    db::migrate(owner).await.unwrap();
    db::migrate(owner).await.unwrap();
    assert_eq!(
        call(app, "GET", "/health/ready", None, None).await.1["schema"],
        "4"
    );
    assert_eq!(
        call(
            app,
            "GET",
            &format!("/api/v1/members/{id}"),
            Some(token),
            None
        )
        .await
        .1["enrollment"],
        original_member["enrollment"],
    );
    let custom_id = registered.1["id"].as_str().unwrap();
    assert_eq!(
        call(
            app,
            "GET",
            &format!("/api/v1/members/{custom_id}"),
            Some(token),
            None
        )
        .await
        .1["enrollment"],
        registered.1["enrollment"],
    );
}
