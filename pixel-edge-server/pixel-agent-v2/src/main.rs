//! Pixel agent v2: gateway, router, reflexive/neocortex (Phase 2).
//! Binds 127.0.0.1:18789 by default. PORT env sets the port. BIND_HOST env (or `--bind <host>`)
//! binds elsewhere on purpose, e.g. `BIND_HOST=0.0.0.0`; a non-loopback bind prints a warning,
//! because /chat is then reachable off-device (Wi-Fi, cellular, Tailscale).
//! REFLEXIVE_URL defaults to http://127.0.0.1:9090 (Jarvis on device).

use axum::{routing::get, routing::post, Json, Router};
use serde::{Deserialize, Serialize};
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use tower_http::cors::CorsLayer;

#[derive(Debug, Deserialize)]
struct ChatRequest {
    message: String,
}

#[derive(Debug, Serialize)]
struct ChatResponse {
    reply: String,
}

/// OpenAI-compatible request/response for /v1/chat/completions (Jarvis, Ollama, etc.)
#[derive(Debug, Serialize)]
struct ChatCompletionRequest {
    model: String,
    messages: Vec<ChatMessage>,
    #[serde(skip_serializing_if = "Option::is_none")]
    max_tokens: Option<u32>,
}

#[derive(Debug, Serialize, Deserialize)]
struct ChatMessage {
    role: String,
    content: String,
}

#[derive(Debug, Deserialize)]
struct ChatCompletionResponse {
    choices: Option<Vec<Choice>>,
}

#[derive(Debug, Deserialize)]
struct Choice {
    message: Option<ChatMessage>,
}

fn reflexive_url() -> String {
    std::env::var("REFLEXIVE_URL").unwrap_or_else(|_| "http://127.0.0.1:9090".to_string())
}

fn reflexive_model() -> String {
    std::env::var("REFLEXIVE_MODEL").unwrap_or_else(|_| "gemma-3b".to_string())
}

async fn call_reflexive(user_message: &str) -> Result<String, String> {
    let base = reflexive_url().trim_end_matches('/').to_string();
    let url = format!("{}/v1/chat/completions", base);
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(60))
        .build()
        .map_err(|e| e.to_string())?;
    let body = ChatCompletionRequest {
        model: reflexive_model(),
        messages: vec![
            ChatMessage {
                role: "user".to_string(),
                content: user_message.to_string(),
            },
        ],
        max_tokens: Some(1024),
    };
    let res = client
        .post(&url)
        .json(&body)
        .send()
        .await
        .map_err(|e| format!("Jarvis unreachable (is the app running?): {}", e))?;
    let status = res.status();
    let text = res.text().await.unwrap_or_default();
    if !status.is_success() {
        let msg = if status.as_u16() == 503 && text.contains("Model not loaded") {
            "Jarvis: model not loaded yet. Open the app, wait for the model to load, then try again."
        } else {
            text.as_str()
        };
        return Err(format!("Jarvis returned {}: {}", status, msg));
    }
    let data: ChatCompletionResponse = serde_json::from_str(&text)
        .map_err(|e| format!("Invalid Jarvis response: {}", e))?;
    let content = data
        .choices
        .and_then(|c| c.into_iter().next())
        .and_then(|c| c.message)
        .map(|m| m.content)
        .unwrap_or_default()
        .trim()
        .to_string();
    Ok(if content.is_empty() {
        "[No response from model]".to_string()
    } else {
        content
    })
}

async fn chat(Json(body): Json<ChatRequest>) -> Json<ChatResponse> {
    let reply = match call_reflexive(&body.message).await {
        Ok(r) => r,
        Err(ref e) => {
            if let Ok(r) = call_hf_fallback(&body.message).await {
                r
            } else {
                format!("[Error: {}]", e)
            }
        }
    };
    Json(ChatResponse { reply })
}

/// Hugging Face Inference API fallback when Jarvis is down (free tier; set HF_TOKEN).
async fn call_hf_fallback(user_message: &str) -> Result<String, String> {
    let token = std::env::var("HF_TOKEN").map_err(|_| "HF_TOKEN not set")?;
    let model = std::env::var("HF_MODEL").unwrap_or_else(|_| "google/gemma-2-2b-it".to_string());
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(90))
        .build()
        .map_err(|e| e.to_string())?;
    let url = format!("https://api-inference.huggingface.co/models/{}", model);
    let body = serde_json::json!({
        "inputs": user_message,
        "parameters": { "max_new_tokens": 512, "return_full_text": false }
    });
    let res = client
        .post(&url)
        .bearer_auth(&token)
        .json(&body)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    let status = res.status();
    let text = res.text().await.unwrap_or_default();
    if !status.is_success() {
        return Err(format!("HF API {}: {}", status, text));
    }
    let arr: Vec<serde_json::Value> = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let out = arr
        .first()
        .and_then(|o| o.get("generated_text"))
        .and_then(|t| t.as_str())
        .unwrap_or("")
        .trim()
        .to_string();
    Ok(if out.is_empty() {
        "[No response from HF]".to_string()
    } else {
        out
    })
}

const DEFAULT_PORT: u16 = 18789;

/// Resolve the listen address. Precedence for the host: `--bind <host>` / `--bind=<host>`,
/// then BIND_HOST, then 127.0.0.1. Port: PORT, else 18789. Errors on an unparsable host
/// instead of silently falling back to a wider bind.
fn resolve_bind(args: &[String], bind_env: Option<String>, port_env: Option<String>) -> Result<SocketAddr, String> {
    let mut flag: Option<String> = None;
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        if a == "--bind" {
            flag = Some(args.get(i + 1).cloned().ok_or("--bind needs a host")?);
            i += 1;
        } else if let Some(v) = a.strip_prefix("--bind=") {
            flag = Some(v.to_string());
        }
        i += 1;
    }
    let host = flag
        .or(bind_env)
        .map(|h| h.trim().trim_matches(|c| c == '[' || c == ']').to_string())
        .filter(|h| !h.is_empty());
    let ip: IpAddr = match host.as_deref() {
        None => IpAddr::V4(Ipv4Addr::LOCALHOST),
        Some("localhost") => IpAddr::V4(Ipv4Addr::LOCALHOST),
        Some(h) => h.parse().map_err(|_| format!("invalid bind host {:?}: use an IP address", h))?,
    };
    let port = port_env
        .and_then(|s| s.trim().parse::<u16>().ok())
        .unwrap_or(DEFAULT_PORT);
    Ok(SocketAddr::new(ip, port))
}

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/", get(|| async { "pixel-agent-v2 ok" }))
        .route("/health", get(|| async { "ok" }))
        .route("/chat", post(chat))
        .layer(CorsLayer::permissive());

    let args: Vec<String> = std::env::args().skip(1).collect();
    let addr = match resolve_bind(&args, std::env::var("BIND_HOST").ok(), std::env::var("PORT").ok()) {
        Ok(a) => a,
        Err(e) => {
            eprintln!("error: {}", e);
            std::process::exit(2);
        }
    };
    if !addr.ip().is_loopback() {
        eprintln!(
            "WARNING: binding {}: /chat is reachable off-device (Wi-Fi, cellular, Tailscale). \
             adb forward only needs 127.0.0.1.",
            addr
        );
    }
    println!("Gateway listening on http://{}", addr);

    axum::serve(tokio::net::TcpListener::bind(addr).await.unwrap(), app).await.unwrap();
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn default_is_loopback_18789() {
        let a = resolve_bind(&[], None, None).unwrap();
        assert_eq!(a, "127.0.0.1:18789".parse().unwrap());
        assert!(a.ip().is_loopback());
    }

    #[test]
    fn port_env_still_works() {
        let a = resolve_bind(&[], None, Some("9999".into())).unwrap();
        assert_eq!(a, "127.0.0.1:9999".parse().unwrap());
        let a = resolve_bind(&[], None, Some("nope".into())).unwrap();
        assert_eq!(a.port(), DEFAULT_PORT);
    }

    #[test]
    fn bind_host_env_binds_elsewhere() {
        let a = resolve_bind(&[], Some("0.0.0.0".into()), None).unwrap();
        assert_eq!(a, "0.0.0.0:18789".parse().unwrap());
        assert!(!a.ip().is_loopback());
        let a = resolve_bind(&[], Some("[::1]".into()), None).unwrap();
        assert!(a.ip().is_loopback());
        let a = resolve_bind(&[], Some("localhost".into()), None).unwrap();
        assert!(a.ip().is_loopback());
        let a = resolve_bind(&[], Some("   ".into()), None).unwrap();
        assert!(a.ip().is_loopback());
    }

    #[test]
    fn flag_beats_env() {
        let a = resolve_bind(&args(&["--bind", "0.0.0.0"]), Some("127.0.0.1".into()), None).unwrap();
        assert_eq!(a.ip().to_string(), "0.0.0.0");
        let a = resolve_bind(&args(&["--bind=127.0.0.1"]), Some("0.0.0.0".into()), None).unwrap();
        assert!(a.ip().is_loopback());
    }

    #[test]
    fn bad_host_is_an_error_not_a_wider_bind() {
        assert!(resolve_bind(&[], Some("not-an-ip".into()), None).is_err());
        assert!(resolve_bind(&args(&["--bind"]), None, None).is_err());
    }
}
