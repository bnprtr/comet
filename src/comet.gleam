import birl.{type Time}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/string_builder

@external(erlang, "gleam_stdlib", "println")
@external(javascript, "../gleam_stdlib.mjs", "console_log")
fn do_println(string string: String) -> Nil

@external(erlang, "gleam_stdlib", "println_error")
@external(javascript, "../gleam_stdlib.mjs", "console_error")
fn do_println_error(string string: String) -> Nil

pub type Attribute {
  StrAttr(key: String, value: String)
  IntAttr(key: String, value: Int)
  FloatAttr(key: String, value: Float)
  BoolAttr(key: String, value: Bool)
  TimeAttr(key: String, value: Time)
  // ListAttr(key: String, value: List(Attribute))
  // DictAttr(key: String, value: Dict(String, Attribute))
}

pub type Level {
  TRACE
  DEBUG
  INFO
  WARN
  ERROR
  CRITICAL
  PANIC
}

pub fn level_text(level: Level) -> String {
  case level {
    TRACE -> "TRACE"
    DEBUG -> "DEBUG"
    INFO -> "INFO"
    WARN -> "WARN"
    ERROR -> "ERROR"
    CRITICAL -> "CRITICAL"
    PANIC -> "PANIC"
  }
}

pub fn level_priority(level: Level) -> Int {
  case level {
    TRACE -> 0
    DEBUG -> 1
    INFO -> 2
    WARN -> 3
    ERROR -> 4
    CRITICAL -> 5
    PANIC -> 6
  }
}

pub type Output =
  fn(String) -> Nil

pub type Formatter =
  fn(Level, String, List(Attribute)) -> String

pub opaque type Context {
  Context(
    outputs: List(Output),
    attributes: List(Attribute),
    formatter: Formatter,
    level: Level,
  )
}

pub const std_out = do_println

pub const std_err = do_println_error

pub fn init() -> Context {
  Context([do_println_error], [], text_formatter("level"), INFO)
}

pub fn with_level(ctx: Context, level: Level) -> Context {
  Context(..ctx, level: level)
}

pub fn with_output(ctx: Context, output: Output) -> Context {
  Context(..ctx, outputs: list.unique(list.append(ctx.outputs, [output])))
}

pub fn set_outputs(ctx: Context, outputs: List(Output)) -> Context {
  Context(..ctx, outputs: outputs)
}

pub fn with_attributes(ctx: Context, attributes: List(Attribute)) -> Context {
  Context(..ctx, attributes: list.append(ctx.attributes, attributes))
}

pub fn with_formatter(ctx: Context, formatter: Formatter) -> Context {
  Context(..ctx, formatter: formatter)
}

pub fn log(ctx: Context, level: Level, msg: String, attributes: List(Attribute)) {
  case level_priority(level) >= level_priority(ctx.level) {
    True -> {
      ctx.formatter(level, msg, list.append(ctx.attributes, attributes))
      |> output_logs(ctx)
    }
    _ -> Nil
  }
  case level {
    PANIC -> panic
    _ -> Nil
  }
}

fn output_logs(ctx: Context) -> fn(String) -> Nil {
  fn(data: String) {
    list.map(ctx.outputs, fn(output) { output(data) })
    Nil
  }
}

pub fn text_formatter(
  level_key: String,
) -> fn(Level, String, List(Attribute)) -> String {
  fn(level: Level, msg: String, attributes: List(Attribute)) -> String {
    list.map(attributes, format_text_attribute)
    |> list.append([msg])
    |> list.prepend(level_key <> "=" <> level_text(level))
    |> string.join(" ")
  }
}

fn format_text_attribute(attr: Attribute) -> String {
  case attr {
    StrAttr(key, value) -> key <> "=\"" <> value <> "\""
    IntAttr(key, value) -> key <> "=" <> int.to_string(value)
    FloatAttr(key, value) -> key <> "=" <> float.to_string(value)
    BoolAttr(key, True) -> key <> "=true"
    BoolAttr(key, False) -> key <> "=false"
    TimeAttr(key, value) -> key <> "=\"" <> birl.to_iso8601(value) <> "\""
  }
}
