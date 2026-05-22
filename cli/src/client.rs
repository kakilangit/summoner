use crate::config::Profile;
use serde::de::DeserializeOwned;
use ureq::Agent;

pub struct Client {
    agent: Agent,
    profile: Profile,
}

#[derive(Debug)]
pub enum ClientError {
    Http(String),
    Json(String),
}

impl std::fmt::Display for ClientError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ClientError::Http(msg) => write!(f, "HTTP error: {msg}"),
            ClientError::Json(msg) => write!(f, "JSON error: {msg}"),
        }
    }
}

impl Client {
    pub fn new(profile: Profile) -> Self {
        let agent = Agent::config_builder()
            .timeout_global(Some(std::time::Duration::from_mins(5)))
            .build()
            .new_agent();
        Client { agent, profile }
    }

    pub fn base_url(&self) -> &str {
        &self.profile.url
    }

    fn auth_header(&self) -> Option<String> {
        self.profile.token.as_ref().map(|t| format!("Bearer {t}"))
    }

    pub fn get<T: DeserializeOwned>(&self, path: &str) -> Result<T, ClientError> {
        let url = format!("{}{path}", self.base_url());
        let mut req = self.agent.get(&url);
        if let Some(auth) = self.auth_header() {
            req = req.header("Authorization", &auth);
        }

        let mut resp = req.call().map_err(|e| ClientError::Http(e.to_string()))?;

        resp.body_mut()
            .read_json::<T>()
            .map_err(|e| ClientError::Json(e.to_string()))
    }

    pub fn post<T: DeserializeOwned>(
        &self,
        path: &str,
        body: &serde_json::Value,
    ) -> Result<T, ClientError> {
        let url = format!("{}{path}", self.base_url());
        let mut req = self.agent.post(&url);
        if let Some(auth) = self.auth_header() {
            req = req.header("Authorization", &auth);
        }

        let mut resp = req
            .send_json(body)
            .map_err(|e| ClientError::Http(e.to_string()))?;

        resp.body_mut()
            .read_json::<T>()
            .map_err(|e| ClientError::Json(e.to_string()))
    }
}
