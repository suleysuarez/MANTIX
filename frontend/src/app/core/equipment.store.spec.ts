import { TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';

import { Equipment, EquipmentPayload, EquipmentService } from './equipment.service';
import { EquipmentState, EquipmentStore } from './equipment.store';

const item = (id: number, tag: string): Equipment =>
  ({ id, asset_tag: tag, equipment_type: { id: 1, code: 'LT', name: 'Laptop' } }) as Equipment;

const payload: EquipmentPayload = {
  asset_tag: 'B', serial_number: null, equipment_type_id: 1,
  brand: 'Acme', model: 'Pro', description: null, status: 'in_storage',
};

describe('EquipmentStore', () => {
  let api: jasmine.SpyObj<EquipmentService>;
  let store: EquipmentStore;
  let latest: EquipmentState;

  beforeEach(() => {
    api = jasmine.createSpyObj('EquipmentService', ['list', 'listTypes', 'create']);
    TestBed.configureTestingModule({
      providers: [EquipmentStore, { provide: EquipmentService, useValue: api }],
    });
    store = TestBed.inject(EquipmentStore);
    store.state$.subscribe((state) => (latest = state));
  });

  it('emits the initial loading state to subscribers immediately', () => {
    expect(latest.loading).toBeTrue();
    expect(latest.equipment).toEqual([]);
  });

  it('publishes equipment and types once loaded', () => {
    api.list.and.returnValue(of([item(1, 'A')]));
    api.listTypes.and.returnValue(of([{ id: 1, code: 'LT', name: 'Laptop' }]));

    store.load();

    expect(latest.loading).toBeFalse();
    expect(latest.equipment.length).toBe(1);
    expect(latest.types.length).toBe(1);
  });

  it('publishes an error when loading fails', () => {
    api.list.and.returnValue(throwError(() => new Error('boom')));
    api.listTypes.and.returnValue(of([]));

    store.load();

    expect(latest.loading).toBeFalse();
    expect(latest.error).toContain('could not be loaded');
  });

  it('inserts a created item in asset-tag order and clears saving', () => {
    api.list.and.returnValue(of([item(1, 'A'), item(3, 'C')]));
    api.listTypes.and.returnValue(of([]));
    api.create.and.returnValue(of(item(2, 'B')));
    store.load();

    store.create(payload);

    expect(latest.equipment.map((e) => e.asset_tag)).toEqual(['A', 'B', 'C']);
    expect(latest.saving).toBeFalse();
    expect(latest.error).toBe('');
  });

  it('emits equipmentCreated$ on success only', () => {
    api.list.and.returnValue(of([]));
    api.listTypes.and.returnValue(of([]));
    store.load();
    let emissions = 0;
    store.equipmentCreated$.subscribe(() => emissions++);

    api.create.and.returnValue(of(item(2, 'B')));
    store.create(payload);
    api.create.and.returnValue(throwError(() => new Error('conflict')));
    store.create(payload);

    expect(emissions).toBe(1);
  });

  it('keeps the list and reports an error when creation fails', () => {
    api.list.and.returnValue(of([item(1, 'A')]));
    api.listTypes.and.returnValue(of([]));
    api.create.and.returnValue(throwError(() => new Error('conflict')));
    store.load();

    store.create(payload);

    expect(latest.equipment.length).toBe(1);
    expect(latest.saving).toBeFalse();
    expect(latest.error).toContain('could not be created');
  });
});
