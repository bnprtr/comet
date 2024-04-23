# comet

[![Package Version](https://img.shields.io/hexpm/v/comet)](https://hex.pm/packages/comet)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/comet/)

```sh
gleam add comet
```
```gleam
import comet.{Debug, Info, Warn, Error as Err, String, Int}

pub fn main() {
  let log = comet.builder()
  |> comet.timestamp
  |> comet.attributes([String("service", "comet")])
  |> comet.log_level(Info)
  |> comet.logger

  log(Info, "application starting...", [String("fn", "main"), Int("process", 1)])
}
```

outputs the log
```
{"level":"info","timestamp":"2024-04-23T06:33:59.101Z","service":"comet","fn":"main","process":1,"msg":"application starting..."}
```

Additionally, level specific log functions can be created:

```gleam
  let assert comet.LevelLoggerSet(trace, debug, info, warn, err) =
    comet.builder()
    |> comet.timestamp
    |> comet.attributes([comet.String("service", "comet")])
    |> comet.log_level(Info)
    |> comet.logger
    |> comet.levels
  debug("log settings", [String("min_log_level", "info")])
  info("✨ application starting...", [String("fn", "main"), Int("process", 1)])
```

Further documentation can be found at <https://hexdocs.pm/comet>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
gleam shell # Run an Erlang shell
```
