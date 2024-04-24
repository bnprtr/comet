let config = {}

export function set_config(configuration) {
  console.debug("set_config")
  console.info("fizz", configuration)
}

export function debug(metadata, message) {
  console.debug(message, metadata)
}

export function info(metadata, message) {
  console.info(message, metadata)
}

export function warn(metadata, message) {
  console.warn(message, metadata)
}

export function error(metadata, message) {
  console.error(message, metadata)
}

export function new_metadata() {
  return {} 
}

export function insert_attribute(metadata, key, value) {
  metadata[key] = value
  return metadata
}
