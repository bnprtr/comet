-module(comet_ffi).
-export([configure/1, debug/2, info/2,warn/2,error/2]).

debug(Metadata, Message) -> log(debug, Message, Metadata).
info(Metadata, Message) -> log(info, Message, Metadata).
warn(Metadata, Message) -> log(warning, Message, Metadata).
error(Metadata, Message) -> log(error, Message, Metadata).
log(Level, Message, Metadata) -> logger:log(Level, Message, Metadata).

configure(Config) ->
    ok = logger:update_primary_config(#{
        level => debug,
        filter_default => log,
        filters => [
            {domain,{fun logger_filters:domain/2, {stop, sub, [otp,sasl]}}},
            {domain,{fun logger_filters:domain/2, {stop, sub, [supervisor_report]}}}
        ],
        metadata => #{foo => "bar"}
    }),
    ok = logger:update_handler_config(default, #{
        formatter => {comet, [#{config=> Config}]}
    }),
    nil.

