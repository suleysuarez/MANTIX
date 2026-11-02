import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, Subject, catchError, concat, forkJoin, map, of, toArray } from 'rxjs';

import { saveBlob } from './download';
import { Attachment, Equipment, EquipmentService } from './equipment.service';
import { httpErrorMessage } from './http-error';
import { MaintenanceListItem, MaintenanceService } from './maintenance.service';
import { MaintenanceSchedule, SchedulePayload, SchedulesService } from './schedules.service';

export interface DetailAbilities {
  /** `maintenance.read`: historial de tickets y planes del equipo. */
  readMaintenance: boolean;
}

export interface DetailState {
  equipment: Equipment | null;
  tickets: MaintenanceListItem[];
  schedules: MaintenanceSchedule[];
  attachments: Attachment[];
  loading: boolean;
  busy: boolean;
  error: string;
  notice: string;
}

interface UploadResult {
  attachment?: Attachment;
  failed?: string;
}

const CLOSED: DetailState = {
  equipment: null,
  tickets: [],
  schedules: [],
  attachments: [],
  loading: false,
  busy: false,
  error: '',
  notice: '',
};

/**
 * Observer pattern para el panel de detalle de un equipo: ficha, historial de tickets,
 * planes preventivos y adjuntos. Cada bloque se carga por separado y un fallo en uno
 * no oculta los demás.
 */
@Injectable({ providedIn: 'root' })
export class EquipmentDetailStore {
  private readonly equipmentApi = inject(EquipmentService);
  private readonly maintenanceApi = inject(MaintenanceService);
  private readonly schedulesApi = inject(SchedulesService);
  private readonly subject = new BehaviorSubject<DetailState>(CLOSED);
  private readonly changedSource = new Subject<Equipment>();
  private abilities: DetailAbilities = { readMaintenance: false };

  readonly state$: Observable<DetailState> = this.subject.asObservable();
  /** Emite el equipo actualizado cuando cambia su ubicación o custodio (la lista se refresca). */
  readonly changed$ = this.changedSource.asObservable();

  open(equipment: Equipment, abilities: DetailAbilities): void {
    this.abilities = abilities;
    this.subject.next({ ...CLOSED, equipment, loading: true });
    forkJoin({
      tickets: abilities.readMaintenance
        ? this.maintenanceApi
            .list({ equipmentId: equipment.id, sort: '-created_at', limit: 5 })
            .pipe(catchError(() => of([] as MaintenanceListItem[])))
        : of([] as MaintenanceListItem[]),
      schedules: abilities.readMaintenance
        ? this.schedulesApi.listForEquipment(equipment.id).pipe(catchError(() => of([] as MaintenanceSchedule[])))
        : of([] as MaintenanceSchedule[]),
      attachments: this.equipmentApi.listAttachments(equipment.id).pipe(catchError(() => of([] as Attachment[]))),
    }).subscribe(({ tickets, schedules, attachments }) =>
      this.patch({ tickets, schedules, attachments, loading: false }),
    );
  }

  close(): void {
    this.subject.next(CLOSED);
  }

  relocate(locationId: number): void {
    this.run(
      (id) => this.equipmentApi.assignLocation(id, locationId),
      'No se pudo cambiar la ubicación.',
      'Ubicación actualizada.',
    );
  }

  reassign(userId: number): void {
    this.run(
      (id) => this.equipmentApi.assignCustody(id, userId),
      'No se pudo reasignar el equipo.',
      'Custodio actualizado.',
    );
  }

  /** Sube los archivos en orden; informa cuáles fallaron sin perder los que sí se subieron. */
  upload(files: File[]): void {
    const equipment = this.subject.value.equipment;
    if (!equipment || files.length === 0) {
      return;
    }
    this.patch({ busy: true, error: '', notice: '' });
    concat(
      ...files.map((file) =>
        this.equipmentApi.uploadAttachment(equipment.id, file).pipe(
          map((attachment): UploadResult => ({ attachment })),
          catchError((error) =>
            of<UploadResult>({ failed: `«${file.name}»: ${httpErrorMessage(error, 'no se pudo subir')}` }),
          ),
        ),
      ),
    )
      .pipe(toArray())
      .subscribe((results) => {
        const uploaded = results.flatMap((result) => (result.attachment ? [result.attachment] : []));
        const failures = results.flatMap((result) => (result.failed ? [result.failed] : []));
        this.patch({
          busy: false,
          attachments: [...uploaded, ...this.subject.value.attachments],
          error: failures.join(' '),
          notice: uploaded.length ? `${uploaded.length} archivo(s) adjuntado(s).` : '',
        });
      });
  }

  download(attachment: Attachment): void {
    this.equipmentApi.downloadAttachment(attachment.id).subscribe({
      next: (blob) => saveBlob(blob, attachment.file_name),
      error: (error) => this.patch({ error: httpErrorMessage(error, 'No se pudo descargar el archivo.') }),
    });
  }

  schedule(payload: SchedulePayload): void {
    this.patch({ busy: true, error: '', notice: '' });
    this.schedulesApi.create(payload).subscribe({
      next: (created) =>
        this.patch({
          busy: false,
          schedules: [...this.subject.value.schedules, created].sort((a, b) =>
            a.next_due_at.localeCompare(b.next_due_at),
          ),
          notice: 'Mantenimiento programado.',
        }),
      error: (error) =>
        this.patch({ busy: false, error: httpErrorMessage(error, 'No se pudo programar el mantenimiento.') }),
    });
  }

  private run(call: (id: number) => Observable<Equipment>, failure: string, success: string): void {
    const equipment = this.subject.value.equipment;
    if (!equipment) {
      return;
    }
    this.patch({ busy: true, error: '', notice: '' });
    call(equipment.id).subscribe({
      next: (updated) => {
        this.patch({ busy: false, equipment: updated, notice: success });
        this.changedSource.next(updated);
      },
      error: (error) => this.patch({ busy: false, error: httpErrorMessage(error, failure) }),
    });
  }

  private patch(partial: Partial<DetailState>): void {
    this.subject.next({ ...this.subject.value, ...partial });
  }
}
