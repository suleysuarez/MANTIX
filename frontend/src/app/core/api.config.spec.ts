import { apiBaseUrl, loadRuntimeConfig } from './api.config';

describe('runtime API config', () => {
  const original = window.fetch;

  // El valor es estado de módulo: se restaura para no afectar a otros specs.
  afterEach(async () => {
    stubFetch({ apiUrl: 'http://localhost:8000' });
    await loadRuntimeConfig();
    window.fetch = original;
  });

  function stubFetch(body: unknown, ok = true): void {
    window.fetch = jasmine
      .createSpy('fetch')
      .and.resolveTo({ ok, json: () => Promise.resolve(body) } as Response);
  }

  it('uses apiUrl from config.json and trims trailing slashes', async () => {
    stubFetch({ apiUrl: ' https://api.example.com// ' });
    await loadRuntimeConfig();
    expect(apiBaseUrl()).toBe('https://api.example.com');
  });

  it('keeps the previous value when the config is missing or invalid', async () => {
    stubFetch({ apiUrl: 'https://keep.example.com' });
    await loadRuntimeConfig();

    stubFetch({}, false);
    await loadRuntimeConfig();
    stubFetch({ apiUrl: 42 });
    await loadRuntimeConfig();
    window.fetch = jasmine.createSpy('fetch').and.rejectWith(new Error('offline'));
    await loadRuntimeConfig();

    expect(apiBaseUrl()).toBe('https://keep.example.com');
  });
});
