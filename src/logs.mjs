let config = {}

export function set_config(configuration) {
  config = configuration
}

export function debug(level, metadata, message) {
 console.debug(config.formatter(config, {level, message, metadata}))
}

export function info(level, metadata, message) {
 console.info(config.formatter(config, {level, message, metadata}))
}

export function warning(level, metadata, message) {
 console.warn(config.formatter(config, {level, message, metadata}))
}

export function error(level, metadata, message) {
 console.error(config.formatter(config, {level, message, metadata}))
}
