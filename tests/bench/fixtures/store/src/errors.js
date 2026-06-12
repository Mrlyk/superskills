/**
 * Application error with a stable machine-readable code.
 * @param {string} code stable error code, e.g. E_TYPE, E_RANGE
 * @param {string} message human-readable description
 */
export class AppError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'AppError';
    this.code = code;
  }
}
