//! Pixel agent v2: gateway, router, reflexive/neocortex (Phase 2).
//! Run with default gateway on 0.0.0.0:18789 (or PORT env).
//! REFLEXIVE_URL defaults to http://127.0.0.1:9090 (Jarvis on device).

use axum::{routing::get, routing::post, Json, Router};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
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

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/", get(|| async { "pixel-agent-v2 ok" }))
        .route("/health", get(|| async { "ok" }))
        .route("/chat", post(chat))
        .layer(CorsLayer::permissive());

    let port = std::env::var("PORT")
        .ok()
        .and_then(|s| s.parse::<u16>().ok())
        .unwrap_or(18789);
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    println!("Gateway listening on http://{}", addr);

    axum::serve(tokio::net::TcpListener::bind(addr).await.unwrap(), app).await.unwrap();
}
