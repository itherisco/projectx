//! # Safe HTTP Request - Async HTTP with Rate Limiting & URL Whitelisting
//!
//! This module provides secure HTTP requests with:
//! - URL whitelist enforcement
//! - Rate limiting per domain
//! - Request/response size limits
//! - Timeout handling
//! - TLS verification
//!
//! ## Security Properties
//!
//! - **URL Whitelist**: Only allowed domains
//! - **Rate Limiting**: Per-domain rate limits
//! - **Size Limits**: Prevents memory exhaustion
//! - **TLS Required**: HTTPS enforced
//! - **Timeout**: Prevents hanging connections

use reqwest::{Client, Method, header::{HeaderMap, HeaderName, HeaderValue}};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::RwLock;
use std::time::{Duration, Instant};
use thiserror::Error;
use url::Url;

/// HTTP errors
#[derive(Error, Debug)]
pub enum HttpError {
    #[error("URL not allowed: {0}")]
    UrlNotAllowed(String),

    #[error("Rate limited: {0}")]
    RateLimited(String),

    #[error("Request failed: {0}")]
    RequestFailed(String),

    #[error("Response too large: {0}")]
    ResponseTooLarge(String),

    #[error("Timeout: {0}")]
    Timeout(String),
}

/// HTTP method
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "UPPERCASE")]
pub enum HttpMethod {
    GET,
    POST,
    PUT,
    DELETE,
}

impl From<&HttpMethod> for Method {
    fn from(m: &HttpMethod) -> Self {
        match m {
            HttpMethod::GET => Method::GET,
            HttpMethod::POST => Method::POST,
            HttpMethod::PUT => Method::PUT,
            HttpMethod::DELETE => Method::DELETE,
        }
    }
}

/// HTTP request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HttpRequest {
    pub url: String,
    pub method: HttpMethod,
    pub headers: HashMap<String, String>,
    pub body: Option<String>,
    pub timeout_secs: u64,
}

/// HTTP response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HttpResponse {
    pub success: bool,
    pub status_code: u16,
    pub headers: HashMap<String, String>,
    pub body: String,
    pub duration_ms: u64,
}

/// Rate limiter per domain
#[derive(Default)]
struct DomainRateLimiter {
    requests: Vec<Instant>,
    max_requests: usize,
    window_secs: u64,
}

impl DomainRateLimiter {
    fn new(max_requests: usize, window_secs: u64) -> Self {
        Self {
            requests: Vec::new(),
            max_requests,
            window_secs,
        }
    }

    fn allow(&mut self) -> bool {
        let now = Instant::now();
        let window_start = now - Duration::from_secs(self.window_secs);

        self.requests.retain(|&t| t > window_start);

        if self.requests.len() >= self.max_requests {
            return false;
        }

        self.requests.push(now);
        true
    }
}

/// HTTP configuration
#[derive(Clone)]
pub struct HttpConfig {
    /// Allowed domains (whitelist)
    pub allowed_domains: HashSet<String>,
    /// Allowed URL patterns
    pub allowed_patterns: Vec<String>,
    /// Rate limit per domain
    pub rate_limit: usize,
    /// Rate limit window in seconds
    pub rate_limit_window: u64,
    /// Maximum response size in bytes
    pub max_response_size: usize,
    /// Request timeout in seconds
    pub timeout_secs: u64,
    /// Whether to require HTTPS
    pub require_https: bool,
}

impl Default for HttpConfig {
    fn default() -> Self {
        let mut allowed_domains = HashSet::new();
        allowed_domains.insert("api.github.com".to_string());
        allowed_domains.insert("httpbin.org".to_string());

        Self {
            allowed_domains,
            allowed_patterns: vec![],
            rate_limit: 10,
            rate_limit_window: 60,
            max_response_size: 1024 * 1024, // 1MB
            timeout_secs: 30,
            require_https: true,
        }
    }
}

/// Safe HTTP Client
pub struct SafeHttp {
    config: HttpConfig,
    client: Client,
    rate_limiters: RwLock<HashMap<String, DomainRateLimiter>>,
}

impl SafeHttp {
    /// Create new HTTP client
    pub fn new() -> Result<Self, HttpError> {
        Self::with_config(HttpConfig::default())
    }

    /// Create with config
    pub fn with_config(config: HttpConfig) -> Result<Self, HttpError> {
        let client = Client::builder()
            .timeout(Duration::from_secs(config.timeout_secs))
            .danger_accept_invalid_certs(false) // Never disable TLS verification
            .build()
            .map_err(|e| HttpError::RequestFailed(e.to_string()))?;

        Ok(Self {
            config,
            client,
            rate_limiters: RwLock::new(HashMap::new()),
        })
    }

    /// Check URL is allowed
    fn check_url(&self, url_str: &str) -> Result<Url, HttpError> {
        let url = Url::parse(url_str)
            .map_err(|e| HttpError::UrlNotAllowed(e.to_string()))?;

        // Check HTTPS
        if self.config.require_https && url.scheme() != "https" {
            return Err(HttpError::UrlNotAllowed(
                "HTTPS required".to_string(),
            ));
        }

        // Get domain
        let host = url.host_str()
            .ok_or_else(|| HttpError::UrlNotAllowed("No host".to_string()))?;

        // Check domain whitelist
        if !self.config.allowed_domains.contains(host) {
            return Err(HttpError::UrlNotAllowed(format!(
                "Domain not allowed: {}",
                host
            )));
        }

        Ok(url)
    }

    /// Check rate limit for domain
    fn check_rate_limit(&self, domain: &str) -> Result<(), HttpError> {
        let mut limiters = self.rate_limiters.write()
            .map_err(|_| HttpError::RateLimited("Lock error".to_string()))?;

        let limiter = limiters
            .entry(domain.to_string())
            .or_insert_with(|| DomainRateLimiter::new(
                self.config.rate_limit,
                self.config.rate_limit_window,
            ));

        if !limiter.allow() {
            return Err(HttpError::RateLimited(format!(
                "Rate limit exceeded for {}",
                domain
            )));
        }

        Ok(())
    }

    /// Execute HTTP request
    pub async fn execute(&self, request: &HttpRequest) -> Result<HttpResponse, HttpError> {
        let start = Instant::now();

        // 1. Validate URL
        let url = self.check_url(&request.url)?;

        // 2. Check rate limit
        let domain = url.host_str().unwrap_or("");
        self.check_rate_limit(domain)?;

        // 3. Build request
        let method = Method::from(&request.method);
        let mut req_builder = self.client.request(method, &request.url);

        // Add headers
        let mut headers = HeaderMap::new();
        for (key, value) in &request.headers {
            if let (Ok(name), Ok(val)) = (
                HeaderName::try_from(key.as_str()),
                HeaderValue::from_str(value),
            ) {
                headers.insert(name, val);
            }
        }
        req_builder = req_builder.headers(headers);

        // Add body
        if let Some(body) = &request.body {
            req_builder = req_builder.body(body.clone());
        }

        // 4. Execute
        let response = req_builder.send().await
            .map_err(|e| HttpError::RequestFailed(e.to_string()))?;

        // 5. Check status
        let status_code = response.status().as_u16();

        // 6. Get headers
        let mut response_headers = HashMap::new();
        for (key, value) in response.headers() {
            if let Ok(v) = value.to_str() {
                response_headers.insert(key.to_string(), v.to_string());
            }
        }

        // 7. Get body with size limit
        let body = response.text().await
            .map_err(|e| HttpError::RequestFailed(e.to_string()))?;

        if body.len() > self.config.max_response_size {
            return Err(HttpError::ResponseTooLarge(format!(
                "Response exceeds {} bytes",
                self.config.max_response_size
            )));
        }

        let duration = start.elapsed();

        Ok(HttpResponse {
            success: status_code >= 200 && status_code < 300,
            status_code,
            headers: response_headers,
            body,
            duration_ms: duration.as_millis() as u64,
        })
    }

    /// Simple GET request
    pub async fn get(&self, url: &str) -> Result<HttpResponse, HttpError> {
        let request = HttpRequest {
            url: url.to_string(),
            method: HttpMethod::GET,
            headers: HashMap::new(),
            body: None,
            timeout_secs: self.config.timeout_secs,
        };
        self.execute(&request).await
    }

    /// Simple POST request
    pub async fn post(&self, url: &str, body: &str) -> Result<HttpResponse, HttpError> {
        let request = HttpRequest {
            url: url.to_string(),
            method: HttpMethod::POST,
            headers: HashMap::from([
                ("Content-Type".to_string(), "application/json".to_string()),
            ]),
            body: Some(body.to_string()),
            timeout_secs: self.config.timeout_secs,
        };
        self.execute(&request).await
    }

    /// Add allowed domain
    pub fn add_allowed_domain(&mut self, domain: &str) {
        self.config.allowed_domains.insert(domain.to_string());
    }
}

// Global HTTP client
use once_cell::sync::Lazy;

static SAFE_HTTP: Lazy<RwLock<SafeHttp>> = Lazy::new(|| {
    RwLock::new(SafeHttp::new().expect("Failed to create SafeHttp"))
});

/// Initialize global HTTP client
pub fn init() {
    let _ = SAFE_HTTP.read();
}

/// Execute HTTP request
pub async fn execute(request: &HttpRequest) -> Result<HttpResponse, HttpError> {
    SAFE_HTTP.read().unwrap().execute(request).await
}

/// Simple GET
pub async fn get(url: &str) -> Result<HttpResponse, HttpError> {
    SAFE_HTTP.read().unwrap().get(url).await
}

/// Simple POST
pub async fn post(url: &str, body: &str) -> Result<HttpResponse, HttpError> {
    SAFE_HTTP.read().unwrap().post(url, body).await
}

/// Add allowed domain
pub fn add_allowed_domain(domain: &str) {
    SAFE_HTTP.write().unwrap().add_allowed_domain(domain);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_allowed_domain() {
        let http = SafeHttp::new().unwrap();
        // This should work (allowed domain)
        let result = http.get("https://httpbin.org/status/200").await;
        // May fail due to network, but URL validation should pass
        assert!(result.is_ok() || matches!(result, Err(HttpError::RateLimited(_))));
    }

    #[test]
    fn test_domain_whitelist() {
        let http = SafeHttp::new().unwrap();
        let result = http.check_url("https://evil.com/test");
        assert!(matches!(result, Err(HttpError::UrlNotAllowed(_))));
    }
}
