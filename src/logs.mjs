let config = {}
let ctx = {}
const handlers = {}

export function add_handler(handler, name) {
  handlers[name] = handler
}

export function remove_handler(name) {
  delete (handlers[name])
}

export function set_config(context, configuration) {
  ctx = context
  config = configuration
}

export function debug(level, metadata, message) {
  log(console.debug, level, message, metadata)
}

export function info(level, metadata, message) {
  log(console.info, level, message, metadata)
}

export function warning(level, metadata, message) {
  log(console.warn, level, message, metadata)
}

export function error(level, metadata, message) {
  log(console.error, level, message, metadata)
}

function log(fn, level, message, metadata) {
  if (config.get('level_priority')(level) >= config.get('min_level')) {
    if (config.get('formatter')) {
      log_event(ctx, fn, config.get('formatter'), level, message, metadata)
    } else {
      fn(message, metadata)
    }
  }
  Object.values(handlers).forEach(handler => {
    if (config.get('level_priority')(level) >= handler.get('min_level')) {
      if (handler.get('formatter')) {
        log_event(handler.get('ctx'), handler.get('handler'), handler.get('formatter'), level, message, metadata)
      } else {
        handler.get('handler')(message)
      }
    }
  })
}

function log_event(ctx, fn, formatter, level, message, metadata) {
  fn(formatter(ctx, { level, message, metadata }))
}

const test_logs = {}
export function test_handler(name) {
  test_logs[name] = []
  return function (msg) {
    test_logs[name].push(msg)
  }
}

export function get_test_logs(name) {
  return test_logs[name]
}

