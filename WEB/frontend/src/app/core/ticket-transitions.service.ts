import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { MaintenanceRequest, MaintenanceService } from './maintenance.service';
import { TransitionData } from './workflow.service';

/** Estados desde los que «cancelar» es un rechazo (con motivo en el historial y la auditoría). */
const REJECTABLE = ['submitted', 'triaged', 'assigned'];

/**
 * Traduce «pasar el ticket X al estado Y» a la llamada correcta de la API: clasificar, asignar,
 * rechazar o cambiar de estado. El servidor sigue siendo quien valida el paso (State Pattern).
 */
@Injectable({ providedIn: 'root' })
export class TicketTransitionService {
  private readonly api = inject(MaintenanceService);

  move(id: number, from: string, to: string, data: TransitionData): Observable<MaintenanceRequest> {
    switch (to) {
      case 'triaged':
        return this.api.classify(id, { category: data.category ?? '', priority: data.priority ?? '', notes: null });
      case 'assigned':
        return this.api.assign(id, data.technicianId ?? 0, null);
      case 'cancelled':
        return REJECTABLE.includes(from) ? this.api.reject(id, data.reason ?? '') : this.api.transition(id, 'cancelled', data.reason ?? null, null);
      case 'resolved':
        return this.api.transition(id, 'resolved', null, data.resolutionSummary ?? null);
      default:
        return this.api.transition(id, to, null, null);
    }
  }
}
