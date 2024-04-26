# comet

[![Package Version](https://img.shields.io/hexpm/v/comet)](https://hex.pm/packages/comet)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/comet/)

✨Create a gleaming trail of application logs✨

## Status
In Progress:
- Logging interface: Proposed
- Erlang logging operational
- Javascript logging operational

Not Started:
- Log Filters
- Log Handlers
- Improved output formatting
- JSON output
- Field customization
- Documentation

## Usage

```sh
gleam add comet
```
```gleam
import comet.{attribute}

type LogAttribute {
  Service(String)
  Latency(Float)
  StatusCode(Int)
  Success(Bool)
  Err(String)
}

pub fn main() {
  // intitialize the underlying logger settings
  comet.new()
  |> comet.level(Info)
  |> comet.configure()

  let log = comet.log()
    |> attribute(Service("comet"))

  log
  |> debug("did this work? hi mom")

  log
  |> attribute(Latency(24.2))
  |> attribute(StatusCode(200))
  |> attribute(Success(True))
  |> info("access log")

  log
  |> attribute(Latency(102.2))
  |> attribute(StatusCode(400))
  |> attribute(Err("input not accepted"))
  |> attribute(Success(False))
  |> warning("access log")

  log
  |> attribute(Latency(402.0))
  |> attribute(StatusCode(500))
  |> attribute(Err("database connection error"))
  |> attribute(Success(False))
  |> error("access log")
}
```

outputs the log
```
level: debug | [Service("comet")] | did this work? hi mom
level: info | [Success(True), StatusCode(200), Latency(24.2), Service("comet")] | access log
level: warn | [Success(False), Err("input not accepted"), StatusCode(400), Latency(102.2), Service("comet")] | access log
level: error | [Success(False), Err("database connection error"), StatusCode(500), Latency(402.0), Service("comet")] | access log
```

Further documentation can be found at <https://hexdocs.pm/comet>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
gleam shell # Run an Erlang shell
```
