import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';

import { EquipmentPage, EquipmentPayload, EquipmentService } from './equipment.service';

const BASE = 'http://localhost:8000';

describe('EquipmentService', () => {
  let service: EquipmentService;
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [EquipmentService, provideHttpClient(), provideHttpClientTesting()],
    });
    service = TestBed.inject(EquipmentService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  it('sends filters, sort and paging as query parameters', () => {
    service
      .list({ search: 'lap', status: 'assigned,in_storage', equipmentTypeId: 2, locationId: 7, sort: '-created_at', page: 3, size: 10 })
      .subscribe();

    const request = http.expectOne((req) => req.url === `${BASE}/equipment`);
    const params = request.request.params;
    expect(params.get('search')).toBe('lap');
    expect(params.get('status')).toBe('assigned,in_storage');
    expect(params.get('equipment_type_id')).toBe('2');
    expect(params.get('location_id')).toBe('7');
    expect(params.get('sort')).toBe('-created_at');
    expect(params.get('page')).toBe('3');
    expect(params.get('size')).toBe('10');
    request.flush([]);
  });

  it('omits empty filters', () => {
    service.list({ search: '', status: '', equipmentTypeId: null, locationId: null }).subscribe();

    const request = http.expectOne((req) => req.url === `${BASE}/equipment`);
    expect(request.request.params.keys()).toEqual([]);
    request.flush([]);
  });

  it('reads the total from the X-Total-Count header', () => {
    let page: EquipmentPage | undefined;
    service.list({ page: 2, size: 2 }).subscribe((value) => (page = value));

    http
      .expectOne((req) => req.url === `${BASE}/equipment`)
      .flush([{ id: 3 }, { id: 4 }], { headers: { 'X-Total-Count': '45' } });

    expect(page?.items.length).toBe(2);
    expect(page?.total).toBe(45);
  });

  it('falls back to the number of rows when the header is missing or invalid', () => {
    const totals: number[] = [];
    service.list().subscribe((value) => totals.push(value.total));
    service.list().subscribe((value) => totals.push(value.total));

    const [first, second] = http.match((req) => req.url === `${BASE}/equipment`);
    first.flush([{ id: 1 }]);
    second.flush([{ id: 1 }, { id: 2 }], { headers: { 'X-Total-Count': 'abc' } });

    expect(totals).toEqual([1, 2]);
  });

  it('listAll returns just the rows, up to the requested size', () => {
    let rows: unknown[] = [];
    service.listAll(200).subscribe((value) => (rows = value));

    const request = http.expectOne((req) => req.url === `${BASE}/equipment`);
    expect(request.request.params.get('size')).toBe('200');
    request.flush([{ id: 1 }], { headers: { 'X-Total-Count': '1' } });

    expect(rows).toEqual([{ id: 1 }]);
  });

  it('loads catalog helpers from their endpoints', () => {
    service.summary().subscribe();
    service.listTypes().subscribe();
    service.listLocations().subscribe();

    http.expectOne(`${BASE}/equipment/summary`).flush({ total: 0, by_status: {} });
    http.expectOne(`${BASE}/equipment/types`).flush([]);
    const locations = http.expectOne((req) => req.url === `${BASE}/locations`);
    expect(locations.request.params.get('size')).toBe('500');
    locations.flush([]);
  });

  const payload: EquipmentPayload = {
    asset_tag: 'LT-001',
    serial_number: 'SN-001',
    equipment_type_id: 1,
    brand: 'Acme',
    model: 'Pro',
    description: null,
    status: 'in_storage',
    purchase_date: null,
    purchase_cost: null,
    warranty_start_date: null,
    warranty_end_date: null,
  };

  it('creates equipment with POST and updates it with PATCH', () => {
    service.create(payload).subscribe();
    const create = http.expectOne(`${BASE}/equipment`);
    expect(create.request.method).toBe('POST');
    expect(create.request.body).toEqual(payload);
    create.flush({ id: 1 });

    service.update(1, { brand: 'Other' } as never).subscribe();
    const update = http.expectOne(`${BASE}/equipment/1`);
    expect(update.request.method).toBe('PATCH');
    expect(update.request.body).toEqual({ brand: 'Other' });
    update.flush({ id: 1 });
  });

  it('assigns location and custody with the ids the API expects', () => {
    service.assignLocation(4, 9).subscribe();
    service.assignCustody(4, 12).subscribe();

    const location = http.expectOne(`${BASE}/equipment/4/location`);
    expect(location.request.body).toEqual({ location_id: 9 });
    location.flush({});
    const custody = http.expectOne(`${BASE}/equipment/4/custody`);
    expect(custody.request.body).toEqual({ assigned_to_user_id: 12 });
    custody.flush({});
  });

  it('searches custodian candidates, with and without a term', () => {
    service.custodianCandidates('ana').subscribe();
    service.custodianCandidates('').subscribe();

    const [withTerm, withoutTerm] = http.match((req) => req.url === `${BASE}/equipment/custodian-candidates`);
    expect(withTerm.request.params.get('search')).toBe('ana');
    expect(withoutTerm.request.params.has('search')).toBeFalse();
    withTerm.flush([]);
    withoutTerm.flush([]);
  });

  it('uploads attachments as multipart and downloads them as blobs', () => {
    const file = new File(['%PDF-'], 'ficha.pdf', { type: 'application/pdf' });
    service.uploadAttachment(4, file).subscribe();
    const upload = http.expectOne(`${BASE}/equipment/4/attachments`);
    expect(upload.request.method).toBe('POST');
    expect(upload.request.body instanceof FormData).toBeTrue();
    expect((upload.request.body as FormData).get('file')).toEqual(jasmine.any(File));
    upload.flush({ id: 1 });

    service.downloadAttachment(8).subscribe();
    const download = http.expectOne(`${BASE}/attachments/8/download`);
    expect(download.request.responseType).toBe('blob');
    download.flush(new Blob(['x']));
  });

  it('exports the inventory report with the active filters', () => {
    service.exportReport('csv', { status: 'in_repair', equipmentTypeId: 3 }).subscribe();

    const request = http.expectOne((req) => req.url === `${BASE}/reports/equipment`);
    expect(request.request.params.get('format')).toBe('csv');
    expect(request.request.params.get('status')).toBe('in_repair');
    expect(request.request.params.get('equipment_type_id')).toBe('3');
    expect(request.request.responseType).toBe('blob');
    request.flush(new Blob(['a,b']));
  });
});
