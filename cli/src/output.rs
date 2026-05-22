use colored::Colorize;
use serde_json::Value;

pub fn print_table(headers: &[&str], rows: &[Vec<String>]) {
    if rows.is_empty() {
        println!("{}", "No results found.".dimmed());
        return;
    }

    // Calculate column widths
    let mut widths: Vec<usize> = headers.iter().map(|h| h.len()).collect();
    for row in rows {
        for (i, cell) in row.iter().enumerate() {
            if i < widths.len() {
                widths[i] = widths[i].max(cell.len());
            }
        }
    }

    // Print header
    let header_line: Vec<String> = headers
        .iter()
        .enumerate()
        .map(|(i, h)| format!("{:width$}", h, width = widths[i]))
        .collect();
    println!("{}", header_line.join("  ").bold());

    let separator: Vec<String> = widths.iter().map(|w| "─".repeat(*w)).collect();
    println!("{}", separator.join("──").dimmed());

    // Print rows
    for row in rows {
        let line: Vec<String> = row
            .iter()
            .enumerate()
            .map(|(i, cell)| {
                let width = widths.get(i).copied().unwrap_or(cell.len());
                format!("{cell:width$}")
            })
            .collect();
        println!("{}", line.join("  "));
    }
}

pub fn print_json(value: &Value) {
    println!(
        "{}",
        serde_json::to_string_pretty(value).unwrap_or_else(|_| value.to_string())
    );
}

pub fn print_error(msg: &str) {
    eprintln!("{} {}", "error:".red().bold(), msg);
}
