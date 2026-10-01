import { TestBed } from '@angular/core/testing';
import {
  HttpTestingController,
  provideHttpClientTesting,
} from '@angular/common/http/testing';
import { provideHttpClient } from '@angular/common/http';

import { EquipmentService } from './equipment.service';

describe('EquipmentService', () => {
  let service: EquipmentService;
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        EquipmentService,
        provideHttpClient(),
        provideHttpClientTesting(),
      ],
    });
    service = TestBed.inject(EquipmentService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  it('loads equipment and active types from the catalog endpoints', () => {
    const results: unknown[] = [];
    service.list().subscribe((value) => results.push(value));
    service.listTypes().subscribe((value) => results.push(value));

    http.expectOne('http://localhost:8000/equipment').flush([]);
    http.expectOne('http://localhost:8000/equipment/types').flush([]);

    expect(results).toEqual([[], []]);
  });

  it('sends search, status and paging as query parameters', () => {
    service.list({ search: 'lap', status: 'in_storage', limit: 21, offset: 20 }).subscribe();

    const request = http.expectOne((req) => req.url === 'http://localhost:8000/equipment');
    expect(request.request.params.get('search')).toBe('lap');
    expect(request.request.params.get('status')).toBe('in_storage');
    expect(request.request.params.get('limit')).toBe('21');
    expect(request.request.params.get('offset')).toBe('20');
    request.flush([]);
  });

  it('creates equipment through the protected catalog endpoint', () => {
    const payload = {
      asset_tag: 'LT-001',
      serial_number: 'SN-001',
      equipment_type_id: 1,
      brand: 'Acme',
      model: 'Pro',
      description: null,
      status: 'in_storage',
    };
    let created: unknown;
    service.create(payload).subscribe((value) => (created = value));
    const request = http.expectOne('http://localhost:8000/equipment');

    expect(request.request.method).toBe('POST');
    expect(request.request.body).toEqual(payload);
    request.flush({ id: 1, ...payload });

    expect(created).toEqual({ id: 1, ...payload });
  });
});
