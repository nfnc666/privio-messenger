/** An error carrying an HTTP status and a stable machine-readable code. */
export class ApiError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'ApiError';
  }

  static badRequest(code: string, message: string) {
    return new ApiError(400, code, message);
  }
  static unauthorized(code = 'unauthorized', message = 'Authentication required') {
    return new ApiError(401, code, message);
  }
  static forbidden(code = 'forbidden', message = 'Not permitted') {
    return new ApiError(403, code, message);
  }
  static notFound(code = 'not_found', message = 'Not found') {
    return new ApiError(404, code, message);
  }
  static conflict(code: string, message: string) {
    return new ApiError(409, code, message);
  }
  static payloadTooLarge(code: string, message: string) {
    return new ApiError(413, code, message);
  }
}
