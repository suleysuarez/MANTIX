import { TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';

import { DetailState, EquipmentDetailStore } from './equipment-detail.store';
import { Attachment, Equipment, EquipmentService } from './equipment.service';
import { MaintenanceService } from './maintenance.service';
import { MaintenanceSchedule, SchedulesService } from './schedules.service';

const item = { id: 5, asset_tag: 'LT-5', current_location: null, current_custodian: null } as Equipment;
const attachment = (id: number, name: string) =>
  ({ id, file_name: name, mime_type: 'application/pdf', file_size: 10 }) as Attachment;

describe('EquipmentDetailStore', () => {
  let equipmentApi: jasmine.SpyObj<EquipmentService>;
  let maintenanceApi: jasmine.SpyObj<MaintenanceService>;
  let schedulesApi: jasmine.SpyObj<SchedulesService>;
  let store: EquipmentDetailStore;
  let latest: DetailState;

  beforeEach(() => {
    equipmentApi = jasmine.createSpyObj('EquipmentService', [
      'listAttachments', 'uploadAttachment', 'downloadAttachment', 'assignLocation', 'assignCustody',
    ]);
    maintenanceApi = jasmine.createSpyObj('MaintenanceService', ['list']);
    schedulesApi = jasmine.createSpyObj('SchedulesService', ['listForEquipment', 'create']);
    equipmentApi.listAttachments.and.returnValue(of([attachment(1, 'a.pdf')]));
    maintenanceApi.list.and.returnValue(of([{ id: 9, title: 'Fix' } as never]));
    schedulesApi.listForEquipment.and.returnValue(of([]));
    TestBed.configureTestingModule({
      providers: [
        EquipmentDetailStore,
        { provide: EquipmentService, useValue: equipmentApi },
        { provide: MaintenanceService, useValue: maintenanceApi },
        { provide: SchedulesService, useValue: schedulesApi },
      ],
    });
    store = TestBed.inject(EquipmentDetailStore);
    store.state$.subscribe((state) => (latest = state));
  });

  it('is closed until an equipment is opened', () => {
    expect(latest.equipment).toBeNull();
  });

  it('loads tickets, plans and attachments for the opened equipment', () => {
    store.open(item, { readMaintenance: true });

    expect(latest.equipment).toBe(item);
    expect(latest.loading).toBeFalse();
    expect(maintenanceApi.list).toHaveBeenCalledWith({ equipmentId: 5, sort: '-created_at', limit: 5 });
    expect(schedulesApi.listForEquipment).toHaveBeenCalledWith(5);
    expect(latest.tickets.length).toBe(1);
    expect(latest.attachments.length).toBe(1);
  });

  it('does not ask for tickets or plans without maintenance.read', () => {
    store.open(item, { readMaintenance: false });

    expect(maintenanceApi.list).not.toHaveBeenCalled();
    expect(schedulesApi.listForEquipment).not.toHaveBeenCalled();
    expect(latest.attachments.length).toBe(1);
  });

  it('a failing block does not hide the others', () => {
    maintenanceApi.list.and.returnValue(throwError(() => new Error('500')));

    store.open(item, { readMaintenance: true });

    expect(latest.tickets).toEqual([]);
    expect(latest.attachments.length).toBe(1);
    expect(latest.loading).toBeFalse();
  });

  it('closing clears the panel', () => {
    store.open(item, { readMaintenance: true });
    store.close();

    expect(latest.equipment).toBeNull();
    expect(latest.attachments).toEqual([]);
  });

  it('relocating updates the equipment and announces the change', () => {
    const moved = { ...item, current_location: { id: 2, code: 'R2', name: 'Room 2' } } as Equipment;
    equipmentApi.assignLocation.and.returnValue(of(moved));
    const changes: Equipment[] = [];
    store.changed$.subscribe((value) => changes.push(value));
    store.open(item, { readMaintenance: false });

    store.relocate(2);

    expect(equipmentApi.assignLocation).toHaveBeenCalledWith(5, 2);
    expect(latest.equipment?.current_location?.name).toBe('Room 2');
    expect(latest.notice).toContain('Ubicación');
    expect(latest.busy).toBeFalse();
    expect(changes).toEqual([moved]);
  });

  it('reports a reassignment failure without losing the panel', () => {
    equipmentApi.assignCustody.and.returnValue(throwError(() => new Error('404')));
    store.open(item, { readMaintenance: false });

    store.reassign(99);

    expect(latest.equipment).toBe(item);
    expect(latest.error).toContain('No se pudo reasignar');
    expect(latest.busy).toBeFalse();
  });

  it('uploads files in order and lists failures next to the ones that worked', () => {
    equipmentApi.uploadAttachment.and.callFake((_id, file) =>
      file.name === 'bad.exe' ? throwError(() => new Error('415')) : of(attachment(10, file.name)),
    );
    store.open(item, { readMaintenance: false });

    store.upload([new File(['a'], 'new.pdf'), new File(['b'], 'bad.exe')]);

    expect(latest.attachments.map((a) => a.file_name)).toEqual(['new.pdf', 'a.pdf']);
    expect(latest.notice).toContain('1 archivo');
    expect(latest.error).toContain('bad.exe');
    expect(latest.busy).toBeFalse();
  });

  it('ignores an empty upload', () => {
    store.open(item, { readMaintenance: false });
    store.upload([]);

    expect(equipmentApi.uploadAttachment).not.toHaveBeenCalled();
  });

  it('adds a scheduled plan keeping them ordered by due date', () => {
    schedulesApi.listForEquipment.and.returnValue(of([{ id: 1, next_due_at: '2026-12-01T09:00:00Z' } as MaintenanceSchedule]));
    schedulesApi.create.and.returnValue(of({ id: 2, next_due_at: '2026-11-01T09:00:00Z' } as MaintenanceSchedule));
    store.open(item, { readMaintenance: true });

    store.schedule({
      equipment_id: 5, title: 't', description: null, interval_days: 30,
      remind_days_before: 3, first_due_at: '2026-11-01T09:00:00Z',
    });

    expect(latest.schedules.map((s) => s.id)).toEqual([2, 1]);
    expect(latest.notice).toContain('programado');
  });

  it('reports a scheduling failure', () => {
    schedulesApi.create.and.returnValue(throwError(() => new Error('422')));
    store.open(item, { readMaintenance: true });

    store.schedule({
      equipment_id: 5, title: 't', description: null, interval_days: 30,
      remind_days_before: 3, first_due_at: '2026-11-01T09:00:00Z',
    });

    expect(latest.error).toContain('No se pudo programar');
    expect(latest.busy).toBeFalse();
  });
});
