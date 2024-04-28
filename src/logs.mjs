// Configurations and context
let config = {};
let ctx = {};
const handlers = {};

// Exported functions to manage handlers
export function addHandler(handler, name) {
  handlers[name] = handler;
}

export function removeHandler(name) {
  delete handlers[name];
}

export function setConfig(context, configuration) {
  ctx = context;
  config = configuration;
}

// Logging functions by severity
export function debug(...args) {
  log('debug', ...args);
}

export function info(...args) {
  log('info', ...args);
}

export function warning(...args) {
  log('warn', ...args);
}

export function error(...args) {
  log('error', ...args);
}

// General log function
function log(method, level, metadata, message) {
  const logFunction = console[method];
  const levelPriority = config.get('level_priority')(level);
  const minLevel = config.get('min_level');

  if (levelPriority >= minLevel) {
    processLogEntry(ctx, logFunction, level, message, metadata);
  }

  Object.values(handlers).forEach(handler => {
    if (levelPriority >= handler.get('min_level')) {
      processLogEntry(handler.get('ctx'), handler.get('handler'), level, message, metadata, handler.get('formatter'));
    }
  });
}

// Helper to process each log entry
function processLogEntry(context, logFunction, level, message, metadata, formatter = config.get('formatter')) {
  const formattedMessage = formatter ? formatter(context, { level, message, metadata }) : message;
  logFunction(formattedMessage);
}

// Test logging functions for unit tests
const testLogs = {};

export function testHandler(name) {
  testLogs[name] = [];
  return function (message) {
    testLogs[name].push(message);
  };
}

export function getTestLogs(name) {
  return testLogs[name];
}
