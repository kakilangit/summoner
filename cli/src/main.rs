mod client;
mod commands;
mod config;
mod output;

use clap::Parser;

use client::Client;
use config::Config;

#[derive(Parser)]
#[command(
    name = "summoner",
    version,
    about = "CLI for the Summoner AI agent platform"
)]
struct Cli {
    /// Config profile to use
    #[arg(long, short, global = true)]
    profile: Option<String>,

    #[command(subcommand)]
    command: Command,
}

#[derive(clap::Subcommand)]
enum Command {
    /// Manage agents
    Agents(commands::agents::AgentsArgs),

    /// Invoke an agent (one-shot)
    Invoke(commands::invoke::InvokeArgs),

    /// Chat with an agent (interactive or one-shot)
    Chat(commands::chat::ChatArgs),

    /// Manage pipelines
    Pipelines(commands::pipelines::PipelinesArgs),

    /// Manage swarms
    Swarms(commands::swarms::SwarmsArgs),

    /// Generate shell completions
    Completion {
        /// Shell to generate completions for
        shell: clap_complete::Shell,
    },
}

fn main() {
    let cli = Cli::parse();
    let config = Config::load();
    let profile = config.resolve_profile(cli.profile.as_deref());
    let client = Client::new(profile);

    match &cli.command {
        Command::Agents(args) => commands::agents::run(&client, args),
        Command::Invoke(args) => commands::invoke::run(&client, args),
        Command::Chat(args) => commands::chat::run(&client, args),
        Command::Pipelines(args) => commands::pipelines::run(&client, args),
        Command::Swarms(args) => commands::swarms::run(&client, args),
        Command::Completion { shell } => {
            clap_complete::generate(
                *shell,
                &mut <Cli as clap::CommandFactory>::command(),
                "summoner",
                &mut std::io::stdout(),
            );
        }
    }
}
