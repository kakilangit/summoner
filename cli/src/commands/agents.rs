use clap::Args;
use serde::{Deserialize, Serialize};

use crate::client::Client;
use crate::output;

#[derive(Args)]
pub struct AgentsArgs {
    #[command(subcommand)]
    pub command: AgentsCommand,
}

#[derive(clap::Subcommand)]
pub enum AgentsCommand {
    /// List all agents in the workspace
    List {
        /// Filter by type: local, remote, or all
        #[arg(long, default_value = "all")]
        r#type: String,

        /// Output format: table or json
        #[arg(long, short, default_value = "table")]
        format: String,
    },
    /// Show agent details
    Show {
        /// Agent ID or @callname
        id: String,

        /// Output format: table or json
        #[arg(long, short, default_value = "table")]
        format: String,
    },
}

#[derive(Deserialize, Serialize)]
struct AgentListResponse {
    items: Vec<Agent>,
}

#[derive(Deserialize, Serialize)]
struct Agent {
    id: String,
    name: String,
    callname: Option<String>,
    r#type: Option<String>,
    status: Option<String>,
    description: Option<String>,
}

pub fn run(client: &Client, args: &AgentsArgs) {
    match &args.command {
        AgentsCommand::List { r#type, format } => list(client, r#type, format),
        AgentsCommand::Show { id, format } => show(client, id, format),
    }
}

fn list(client: &Client, type_filter: &str, format: &str) {
    let mut path = "/api/v1/agents".to_string();
    if type_filter != "all" {
        path = format!("{path}?type={type_filter}");
    }

    match client.get::<AgentListResponse>(&path) {
        Ok(resp) => {
            if format == "json" {
                let val = serde_json::to_value(&resp.items).unwrap_or_default();
                output::print_json(&val);
            } else {
                let rows: Vec<Vec<String>> = resp
                    .items
                    .iter()
                    .map(|a| {
                        vec![
                            a.id.clone(),
                            a.name.clone(),
                            a.callname.clone().unwrap_or_default(),
                            a.r#type.clone().unwrap_or_default(),
                            a.status.clone().unwrap_or_default(),
                        ]
                    })
                    .collect();
                output::print_table(&["ID", "NAME", "CALLNAME", "TYPE", "STATUS"], &rows);
            }
        }
        Err(e) => output::print_error(&e.to_string()),
    }
}

fn show(client: &Client, id: &str, format: &str) {
    let path = format!("/api/v1/agents/{id}");
    match client.get::<serde_json::Value>(&path) {
        Ok(agent) => {
            if format == "json" {
                output::print_json(&agent);
            } else {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&agent).unwrap_or_default()
                );
            }
        }
        Err(e) => output::print_error(&e.to_string()),
    }
}
