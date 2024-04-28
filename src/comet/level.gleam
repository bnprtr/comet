import gleam_community/ansi

pub fn level_priority(level: Level) -> Int {
  case level {
    Debug -> 1
    Info -> 2
    Warning -> 3
    Error -> 4
  }
}

pub type Level {
  Debug
  Info
  Warning
  Error
}

pub fn level_text(level: Level) -> String {
  case level {
    Debug -> "debug"
    Info -> "info"
    Warning -> "warn"
    Error -> "error"
  }
}

pub fn level_text_ansi(level: Level) -> String {
  case level {
    Debug -> ansi.green("debug")
    Info -> ansi.blue("info")
    Warning -> ansi.yellow("warn")
    Error -> ansi.red("error")
  }
}
