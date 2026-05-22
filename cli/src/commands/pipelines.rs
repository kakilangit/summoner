use clap::Args;
use serde::{Deserialize, Serialize};

use crate::client::Client;
use crate::output;

#[derive(Args)]
pub struct PipelinesArgs {
    #[command(subcommand)]
    pub command: PipelinesCommand,
}

#[derive(clap::Subcommand)]
pub enum PipelinesCommand {
    /// List pipelines
    List {
        #[arg(long, short, default_value = "table")]
        format: String,
    },
    /// Show pipeline runs
    Runs {
        /// Pipeline ID
        id: String,
    },
}

#[derive(Deserialize, Serialize)]
struct PipelineListResponse {
    items: Vec<Pipeline>,
}

#[derive(Deserialize, Serialize)]
struct Pipeline {
    id: String,
    name: String,
    mode: Option<String>,
    description: Option<String>,
}

pub fn run(client: &Client, args: &PipelinesArgs) {
    match &args.command {
        PipelinesCommand::List { format } => list(client, format),
        PipelinesCommand::Runs { id } => runs(client, id),
    }
}

fn list(client: &Client, format: &str) {
    match client.get::<PipelineListResponse>("/api/v1/pipelines") {
        Ok(resp) => {
            if format == "json" {
                let val = serde_json::to_value(&resp.items).unwrap_or_default();
                output::print_json(&val);
            } else {
                let rows: Vec<Vec<String>> = resp
                    .items
                    .iter()
                    .map(|p| {
                        vec![
                            p.id.clone(),
                            p.name.clone(),
                            p.mode.clone().unwrap_or_default(),
                            p.description.clone().unwrap_or_default(),
                        ]
                    })
                    .collect();
                output::print_table(&["ID", "NAME", "MODE", "DESCRIPTION"], &rows);
            }
        }
        Err(e) => output::print_error(&e.to_string()),
    }
}

fn runs(client: &Client, id: &str) {
    let path = format!("/api/v1/pipelines/{id}/runs");
    match client.get::<serde_json::Value>(&path) {
        Ok(val) => output::print_json(&val),
        Err(e) => output::print_error(&e.to_string()),
    }
}
