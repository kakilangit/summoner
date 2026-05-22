use std::path::PathBuf;

use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize)]
pub struct Config {
    pub default: Option<Profile>,
    #[serde(default)]
    pub profiles: std::collections::HashMap<String, Profile>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct Profile {
    pub url: String,
    pub token: Option<String>,
    pub workspace_id: Option<String>,
}

impl Config {
    pub fn load() -> Self {
        let path = config_path();
        if path.exists() {
            let content = std::fs::read_to_string(&path).unwrap_or_default();
            toml::from_str(&content).unwrap_or_else(|_| Config::default_config())
        } else {
            Config::default_config()
        }
    }

    pub fn resolve_profile(&self, profile_name: Option<&str>) -> Profile {
        let env_profile = std::env::var("SUMMONER_PROFILE").ok();
        let name = profile_name.or(env_profile.as_deref());

        let mut profile = match name {
            Some(n) => self
                .profiles
                .get(n)
                .cloned()
                .unwrap_or_else(|| self.default_profile()),
            None => self.default_profile(),
        };

        // Env vars override config
        if let Ok(url) = std::env::var("SUMMONER_URL") {
            profile.url = url;
        }
        if let Ok(token) = std::env::var("SUMMONER_TOKEN") {
            profile.token = Some(token);
        }
        if let Ok(ws) = std::env::var("SUMMONER_WORKSPACE") {
            profile.workspace_id = Some(ws);
        }

        profile
    }

    fn default_profile(&self) -> Profile {
        self.default.clone().unwrap_or(Profile {
            url: "http://localhost:4000".to_string(),
            token: None,
            workspace_id: None,
        })
    }

    fn default_config() -> Self {
        Config {
            default: Some(Profile {
                url: "http://localhost:4000".to_string(),
                token: None,
                workspace_id: None,
            }),
            profiles: std::collections::HashMap::new(),
        }
    }
}

fn config_path() -> PathBuf {
    directories::ProjectDirs::from("dev", "summoner", "summoner-cli").map_or_else(
        || dirs_fallback().join("config.toml"),
        |dirs| dirs.config_dir().join("config.toml"),
    )
}

fn dirs_fallback() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".config").join("summoner")
}
