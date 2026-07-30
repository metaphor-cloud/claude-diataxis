//! cargo xtask stub for diataxis. Drop into xtask/src/main.rs (or merge into
//! an existing xtask) so `cargo xtask docs` and `cargo xtask docs-check` work.

use std::process::{exit, Command};

fn run_diataxis(args: &[&str]) -> i32 {
    let status = Command::new("diataxis/bin/diataxis")
        .args(args)
        .status()
        .expect("failed to run diataxis/bin/diataxis; is the harness vendored?");
    status.code().unwrap_or(1)
}

fn main() {
    let task = std::env::args().nth(1).unwrap_or_default();
    let code = match task.as_str() {
        "docs" => run_diataxis(&["generate"]),
        "docs-plan" => run_diataxis(&["plan"]),
        "docs-check" => run_diataxis(&["check"]),
        "docs-audit" => run_diataxis(&["audit"]),
        "docs-cost" => run_diataxis(&["cost"]),
        other => {
            eprintln!("unknown task '{other}'. Tasks: docs, docs-plan, docs-check, docs-audit, docs-cost");
            2
        }
    };
    exit(code);
}
