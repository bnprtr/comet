// Level ---------------------------------------------------------------------------
pub fn level_priority(level: Level) -> Int {
  case level {
    Debug -> 1
    Info -> 2
    Warning -> 3
    Error -> 4
    Panic -> 5
  }
}

pub type Level {
  Debug
  Info
  Warning
  Error
  Panic
}

pub fn level_text(level: Level) -> String {
  case level {
    Debug -> "debug"
    Info -> "info"
    Warning -> "warn"
    Error -> "error"
    Panic -> "panic"
  }
}
