use clap::Args;
use serde::{Deserialize, Serialize};

use crate::client::Client;
use crate::output;

#[derive(Args)]
pub struct SwarmsArgs {
    #[command(subcommand)]
    pub command: SwarmsCommand,
}

#[derive(clap::Subcommand)]
pub enum SwarmsCommand {
    /// List swarms
    List {
        #[arg(long, short, default_value = "table")]
        format: String,
    },
}

#[derive(Deserialize, Serialize)]
struct SwarmListResponse {
    items: Vec<Swarm>,
}

#[derive(Deserialize, Serialize)]
struct Swarm {
    id: String,
    name: String,
    mode: Option<String>,
}

pub fn run(client: &Client, args: &SwarmsArgs) {
    match &args.command {
        SwarmsCommand::List { format } => list(client, format),
    }
}

fn list(client: &Client, format: &str) {
    match client.get::<SwarmListResponse>("/api/v1/swarms") {
        Ok(resp) => {
            if format == "json" {
                let val = serde_json::to_value(&resp.items).unwrap_or_default();
                output::print_json(&val);
            } else {
                let rows: Vec<Vec<String>> = resp
                    .items
                    .iter()
                    .map(|s| {
                        vec![
                            s.id.clone(),
                            s.name.clone(),
                            s.mode.clone().unwrap_or_default(),
                        ]
                    })
                    .collect();
                output::print_table(&["ID", "NAME", "MODE"], &rows);
            }
        }
        Err(e) => output::print_error(&e.to_string()),
    }
}
