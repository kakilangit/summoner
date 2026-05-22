use clap::Args;
use serde::{Deserialize, Serialize};

use crate::client::Client;
use crate::output;

#[derive(Args)]
pub struct InvokeArgs {
    /// Agent ID or @callname
    pub agent: String,

    /// Message to send to the agent
    pub message: Vec<String>,

    /// Output format: text or json
    #[arg(long, short, default_value = "text")]
    pub format: String,
}

#[derive(Deserialize, Serialize)]
struct InvokeResponse {
    invocation_id: Option<String>,
    status: Option<String>,
    messages: Option<Vec<Message>>,
}

#[derive(Deserialize, Serialize)]
struct Message {
    role: Option<String>,
    content: Option<String>,
}

pub fn run(client: &Client, args: &InvokeArgs) {
    let agent_id = &args.agent;
    let message = if args.message.is_empty() {
        // Read from stdin if no message args
        let mut input = String::new();
        std::io::Read::read_to_string(&mut std::io::stdin(), &mut input).unwrap_or_default();
        input
    } else {
        args.message.join(" ")
    };

    let path = format!("/api/v1/agents/{agent_id}/invoke");
    let body = serde_json::json!({ "message": message });

    let spinner = indicatif::ProgressBar::new_spinner();
    spinner.set_message("Invoking agent...");
    spinner.enable_steady_tick(std::time::Duration::from_millis(100));

    match client.post::<InvokeResponse>(&path, &body) {
        Ok(resp) => {
            spinner.finish_and_clear();

            if args.format == "json" {
                let val = serde_json::to_value(&resp).unwrap_or_default();
                output::print_json(&val);
            } else {
                // Print assistant messages
                if let Some(messages) = &resp.messages {
                    for msg in messages {
                        if msg.role.as_deref() == Some("assistant")
                            && let Some(content) = &msg.content
                        {
                            println!("{content}");
                        }
                    }
                } else {
                    println!(
                        "Invocation {} — status: {}",
                        resp.invocation_id.unwrap_or_default(),
                        resp.status.unwrap_or_default()
                    );
                }
            }
        }
        Err(e) => {
            spinner.finish_and_clear();
            output::print_error(&e.to_string());
        }
    }
}
