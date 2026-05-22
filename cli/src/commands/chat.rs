use clap::Args;

use crate::client::Client;
use crate::output;

#[derive(Args)]
pub struct ChatArgs {
    /// Agent ID or @callname
    pub agent: String,

    /// Initial message (if empty, enters interactive mode)
    pub message: Vec<String>,
}

pub fn run(client: &Client, args: &ChatArgs) {
    if args.message.is_empty() {
        interactive(client, &args.agent);
    } else {
        // One-shot mode — just invoke
        let invoke_args = crate::commands::invoke::InvokeArgs {
            agent: args.agent.clone(),
            message: args.message.clone(),
            format: "text".to_string(),
        };
        crate::commands::invoke::run(client, &invoke_args);
    }
}

fn interactive(client: &Client, agent: &str) {
    println!("Chat with {agent} (Ctrl+D to exit)\n");

    loop {
        eprint!("> ");
        let mut input = String::new();
        match std::io::stdin().read_line(&mut input) {
            Ok(0) => break, // EOF
            Ok(_) => {
                let msg = input.trim();
                if msg.is_empty() {
                    continue;
                }
                let invoke_args = crate::commands::invoke::InvokeArgs {
                    agent: agent.to_string(),
                    message: vec![msg.to_string()],
                    format: "text".to_string(),
                };
                crate::commands::invoke::run(client, &invoke_args);
                println!();
            }
            Err(e) => {
                output::print_error(&e.to_string());
                break;
            }
        }
    }
}
