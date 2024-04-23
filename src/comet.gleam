//// Create a gleaming trail of application logs. 

import birl
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

pub type Level {
  Trace
  Debug
  Info
  Warn
  Error
  Panic
}

pub type Attribute {
  String(key: String, value: String)
  Int(key: String, value: Int)
  Float(key: String, value: Float)
  Bool(key: String, value: Bool)
  Fn(fn() -> Attribute)
}

pub type Output =
  fn(String, Level) -> Nil

pub type Formatter =
  fn(Level, String, List(Attribute)) -> String

pub type LevelTextFn =
  fn(Level) -> String

pub opaque type Context {
  Context(formatter: Formatter, output: Output, level_text: LevelTextFn)
}

type Logger =
  fn(Level, String, List(Attribute)) -> Nil

pub type Entry {
  Entry(
    ctx: Context,
    level: Level,
    message: String,
    attributes: List(Attribute),
  )
}

fn init() -> Context {
  Context(
    formatter: json_formatter,
    output: write_output,
    level_text: get_level_text,
  )
}

pub fn formatter(next: Handler, formatter: Formatter) -> Handler {
  fn(entry: Entry) -> Option(Entry) {
    let ctx = Context(..entry.ctx, formatter: formatter)
    next(Entry(..entry, ctx: ctx))
  }
}

pub fn output(next: Handler, output: Output) -> Handler {
  fn(entry: Entry) -> Option(Entry) {
    let ctx = Context(..entry.ctx, output: output)
    next(Entry(..entry, ctx: ctx))
  }
}

pub fn level_text(next: Handler, func: LevelTextFn) -> Handler {
  fn(entry: Entry) -> Option(Entry) {
    let ctx = Context(..entry.ctx, level_text: func)
    next(Entry(..entry, ctx: ctx))
  }
}

pub fn log_level(next: Handler, level: Level) -> Handler {
  fn(entry: Entry) -> Option(Entry) {
    case level_priority(entry.level) >= level_priority(level) {
      True -> next(entry)
      False -> None
    }
  }
}

pub fn timestamp(next: Handler) -> Handler {
  fn(entry: Entry) -> Option(Entry) {
    let timestamp =
      birl.utc_now()
      |> birl.to_iso8601
    next(
      Entry(
        ..entry,
        attributes: list.prepend(
          entry.attributes,
          String("timestamp", timestamp),
        ),
      ),
    )
  }
}

type Handler =
  fn(Entry) -> Option(Entry)

pub fn builder() -> Handler {
  fn(entry: Entry) -> Option(Entry) { Some(entry) }
}

pub fn logger(next: Handler) -> Logger {
  fn(level: Level, msg: String, attributes: List(Attribute)) -> Nil {
    Entry(ctx: init(), level: level, message: msg, attributes: attributes)
    |> next
    |> log
  }
}

fn log(entry: Option(Entry)) -> Nil {
  case entry {
    Some(e) -> {
      e.ctx.formatter(e.level, e.message, e.attributes)
      |> e.ctx.output(e.level)
    }
    None -> Nil
  }
}

pub fn get_level_text(level: Level) -> String {
  case level {
    Trace -> "trace"
    Debug -> "debug"
    Info -> "info"
    Warn -> "warn"
    Error -> "error"
    Panic -> "panic"
  }
}

pub fn level_priority(level: Level) -> Int {
  case level {
    Trace -> 0
    Debug -> 1
    Info -> 2
    Warn -> 3
    Error -> 4
    Panic -> 5
  }
}

pub fn json_formatter(
  level: Level,
  msg: String,
  attributes: List(Attribute),
) -> String {
  list.map(
    list.concat([
      [String("level", get_level_text(level))],
      attributes,
      [String("msg", msg)],
    ]),
    attribute_to_json,
  )
  |> json.object
  |> json.to_string
}

fn attribute_to_json(attr: Attribute) -> #(String, json.Json) {
  case attr {
    String(key, value) -> #(key, json.string(value))
    Int(key, value) -> #(key, json.int(value))
    Float(key, value) -> #(key, json.float(value))
    Bool(key, value) -> #(key, json.bool(value))
    Fn(func) -> attribute_to_json(func())
  }
}

pub fn write_output(entry: String, level: Level) {
  case level {
    Trace -> do_println_trace(entry)
    Debug -> do_println_debug(entry)
    Info -> do_println_info(entry)
    Warn -> do_println_warn(entry)
    Error -> do_println_error(entry)
    Panic -> do_println_error(entry)
  }
}

@external(erlang, "gleam_stdlib", "println")
@external(javascript, "../gleam_stdlib.mjs", "console_trace")
fn do_println_trace(string string: String) -> Nil

@external(erlang, "gleam_stdlib", "println")
@external(javascript, "../gleam_stdlib.mjs", "console_debug")
fn do_println_debug(string string: String) -> Nil

@external(erlang, "gleam_stdlib", "println")
@external(javascript, "../gleam_stdlib.mjs", "console_info")
fn do_println_info(string string: String) -> Nil

@external(erlang, "gleam_stdlib", "println_error")
@external(javascript, "../gleam_stdlib.mjs", "console_warn")
fn do_println_warn(string string: String) -> Nil

@external(erlang, "gleam_stdlib", "println_error")
@external(javascript, "../gleam_stdlib.mjs", "console_error")
fn do_println_error(string string: String) -> Nil
