import comet
import gleam/dynamic
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/json
import gleam/list
import gleam/otp/actor
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

type LogMessage {
  Entry(String)
  Retrieve(Subject(List(String)))
}

fn log_aggregator(
  msg: LogMessage,
  logs: List(String),
) -> actor.Next(LogMessage, List(String)) {
  case msg {
    Entry(entry) -> actor.continue(list.append(logs, [entry]))
    Retrieve(subject) -> {
      process.send(subject, logs)
      actor.continue(logs)
    }
  }
}

pub fn log_test() {
  let assert Ok(output) = actor.start([], log_aggregator)
  let log =
    comet.builder()
    |> comet.output(fn(msg: String, level: comet.Level) -> Nil {
      comet.write_output(msg, level)
      process.send(output, Entry(msg))
      Nil
    })
    |> comet.logger
  log(comet.Trace, "Trace", [comet.String("region", "us-west4")])
  log(comet.Debug, "Debug", [comet.Bool("gleam_rocks", True)])
  log(comet.Info, "Info", [comet.Int("num_pets", 18)])
  log(comet.Warn, "Warn", [comet.Float("chance_of_success", 33.3333333)])
  log(comet.Error, "Error", [
    comet.Fn(fn() -> comet.Attribute { comet.String("lang", "gleam") }),
  ])

  should.equal(process.call(output, Retrieve, 10), [
    "{\"level\":\"trace\",\"region\":\"us-west4\",\"msg\":\"Trace\"}",
    "{\"level\":\"debug\",\"gleam_rocks\":true,\"msg\":\"Debug\"}",
    "{\"level\":\"info\",\"num_pets\":18,\"msg\":\"Info\"}",
    "{\"level\":\"warn\",\"chance_of_success\":33.3333333,\"msg\":\"Warn\"}",
    "{\"level\":\"error\",\"lang\":\"gleam\",\"msg\":\"Error\"}",
  ])
}

pub fn log_level_test() {
  let assert Ok(output) = actor.start([], log_aggregator)
  let log =
    comet.builder()
    |> comet.output(fn(msg: String, level: comet.Level) -> Nil {
      comet.write_output(msg, level)
      process.send(output, Entry(msg))
      Nil
    })
    |> comet.log_level(comet.Warn)
    |> comet.logger
  log(comet.Trace, "Trace", [comet.String("region", "us-west4")])
  log(comet.Debug, "Debug", [comet.Bool("gleam_rocks", True)])
  log(comet.Info, "Info", [comet.Int("num_pets", 18)])
  log(comet.Warn, "Warn", [comet.Float("chance_of_success", 33.3333333)])
  log(comet.Error, "Error", [
    comet.Fn(fn() -> comet.Attribute { comet.String("lang", "gleam") }),
  ])

  should.equal(process.call(output, Retrieve, 10), [
    "{\"level\":\"warn\",\"chance_of_success\":33.3333333,\"msg\":\"Warn\"}",
    "{\"level\":\"error\",\"lang\":\"gleam\",\"msg\":\"Error\"}",
  ])
}

type LogEntry {
  LogEntry(level: String, msg: String, timestamp: String)
}

pub fn timestamp_log_test() {
  let assert Ok(output) = actor.start([], log_aggregator)
  let log =
    comet.builder()
    |> comet.output(fn(msg: String, _: comet.Level) -> Nil {
      io.debug(msg)
      process.send(output, Entry(msg))
      Nil
    })
    |> comet.timestamp
    |> comet.logger
  log(comet.Trace, "Trace", [])

  let logs = process.call(output, Retrieve, 10)

  let log_decoder =
    dynamic.decode3(
      LogEntry,
      dynamic.field("level", dynamic.string),
      dynamic.field("msg", dynamic.string),
      dynamic.field("timestamp", dynamic.string),
    )
  case logs {
    [raw] -> {
      let assert Ok(entry) = json.decode(raw, log_decoder)
      should.not_equal(entry.timestamp, "")
      should.equal(entry, LogEntry("trace", "Trace", entry.timestamp))
    }
    _ -> should.fail()
  }
}

pub fn level_log_test() {
  let assert Ok(output) = actor.start([], log_aggregator)
  let assert comet.LevelLoggerSet(trace, debug, info, warn, err) =
    comet.builder()
    |> comet.output(fn(msg: String, level: comet.Level) -> Nil {
      process.send(output, Entry(msg))
      Nil
    })
    |> comet.attributes([comet.String("service", "comet")])
    |> comet.logger
    |> comet.levels
  trace("Trace", [])
  debug("Debug", [])
  info("Info", [])
  warn("Warn", [])
  err("Error", [])

  should.equal(process.call(output, Retrieve, 10), [
    "{\"level\":\"trace\",\"service\":\"comet\",\"msg\":\"Trace\"}",
    "{\"level\":\"debug\",\"service\":\"comet\",\"msg\":\"Debug\"}",
    "{\"level\":\"info\",\"service\":\"comet\",\"msg\":\"Info\"}",
    "{\"level\":\"warn\",\"service\":\"comet\",\"msg\":\"Warn\"}",
    "{\"level\":\"error\",\"service\":\"comet\",\"msg\":\"Error\"}",
  ])
}
