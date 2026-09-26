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

  it('loads equipment and active types from the catalog endpoints', async () => {
    const equipmentPromise = service.list();
    const typesPromise = service.listTypes();

    http.expectOne('http://localhost:8000/equipment').flush([]);
    http.expectOne('http://localhost:8000/equipment/types').flush([]);

    expect(await equipmentPromise).toEqual([]);
    expect(await typesPromise).toEqual([]);
  });

  it('creates equipment through the protected catalog endpoint', async () => {
    const payload = {
      asset_tag: 'LT-001',
      serial_number: 'SN-001',
      equipment_type_id: 1,
      brand: 'Acme',
      model: 'Pro',
      description: null,
      status: 'in_storage',
    };
    const promise = service.create(payload);
    const request = http.expectOne('http://localhost:8000/equipment');

    expect(request.request.method).toBe('POST');
    expect(request.request.body).toEqual(payload);
    request.flush({ id: 1, ...payload });

    await expectAsync(promise).toBeResolved();
  });
});
