# comet

[![Package Version](https://img.shields.io/hexpm/v/comet)](https://hex.pm/packages/comet)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/comet/)

✨Create a gleaming trail of application logs✨

The API of this library is still unstable. Be aware that it will change before stabilizing.

## Usage

```sh
gleam add comet
```
```gleam
import comet.{attribute, debug, info, warning, error}
import comet/level.{Debug}
  
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
  |> comet.level(Debug)
  |> comet.configure

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
level=debug time=2024-04-28T06:58:37.879Z attributes=[Service("comet")] msg=did this work? hi mom
level=info time=2024-04-28T06:58:37.883Z attributes=[Service("comet"), Latency(24.2), StatusCode(200), Success(True)] msg=access log
level=warn time=2024-04-28T06:58:37.883Z attributes=[Success(False), AnError("input not accepted"), StatusCode(400), Latency(102.2), Service("comet")] msg=access log
level=error time=2024-04-28T06:58:37.884Z attributes=[Success(False), AnError("database connection error"), StatusCode(500), Latency(402.1), Service("comet")] msg=access log
```

## JSON Formatted Logs
```gleam
import comet.{info}
import gleam/json

// Note: It's recommended to create a single Attribute Type for your application that contains
// all necessary records for attributes, otherwise it will be impossible to serialize
// fields for structured logging.
type LogAttribute {
  Service(String)
  Success(Bool)
}

fn attribute_serializer(a: Attribute) -> #(String, json.Json) {
  case a {
    Service(value) -> #("service", json.string(value))
    Latency(value) -> #("latency", json.float(value))
    StatusCode(value) -> #("statusCode", json.int(value))
    Success(value) -> #("success", json.bool(value))
    AnError(value) -> #("error", json.string(value))
  }
}

fn main() {
  comet.new()
  |> comet.with_formatter(comet.json_formatter(attribute_serializer))
  |> configure

  comet.log()
  |> attributes([Service("comet"), Success(True)])
  |> info("Halley's Comet returns in 2061")
}
```

will output the logs:
```json
{"msg":"Halley's Comet returns in 2061","time":"2024-04-28T07:04:01.600Z","level":"info","service":"comet","success":true}
```
Further documentation can be found at <https://hexdocs.pm/comet>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
gleam shell # Run an Erlang shell
```
