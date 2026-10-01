import { HttpErrorResponse } from '@angular/common/http';

import { httpErrorMessage } from './http-error';

const http = (status: number) => new HttpErrorResponse({ status });

describe('httpErrorMessage', () => {
  it('reports an unreachable server for status 0', () => {
    expect(httpErrorMessage(http(0), 'x')).toContain('cannot be reached');
  });

  it('distinguishes expired sessions, missing permission and throttling', () => {
    expect(httpErrorMessage(http(401), 'x')).toContain('session has expired');
    expect(httpErrorMessage(http(403), 'x')).toContain('permission');
    expect(httpErrorMessage(http(429), 'x')).toContain('Too many requests');
  });

  it('reports server problems for 5xx', () => {
    expect(httpErrorMessage(http(503), 'x')).toContain('server had a problem');
  });

  it('falls back to the screen message for other errors', () => {
    expect(httpErrorMessage(http(409), 'duplicate')).toBe('duplicate');
    expect(httpErrorMessage(new Error('boom'), 'fallback')).toBe('fallback');
  });
});
