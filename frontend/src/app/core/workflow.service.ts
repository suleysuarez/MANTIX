import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, shareReplay } from 'rxjs';

import { apiBaseUrl } from './api.config';

/** Dato que una persona debe dar para pasar un ticket a un estado (lo pide el State Pattern del servidor). */
export type Requirement = 'category' | 'priority' | 'technician' | 'resolution_summary' | 'reason';

export interface WorkflowState {
  status: string;
  order: number;
  allowed_targets: string[];
  requires: Requirement[];
  terminal: boolean;
  /** Sigue esperando trabajo: es una columna de la bandeja de solicitudes pendientes. */
  in_queue?: boolean;
  /** Permiso que hace falta para mover un ticket A este estado. */
  permission?: string;
  /** Si la persona que mira tiene ese permiso (el servidor lo calcula; el tablero apaga el resto). */
  can_enter?: boolean;
}

/** Los estados del ticket y los pasos válidos entre ellos, leídos del servidor (no escritos aquí). */
@Injectable({ providedIn: 'root' })
export class WorkflowService {
  private readonly http = inject(HttpClient);
  private cached: Observable<WorkflowState[]> | null = null;

  /** Se pide una vez; las pantallas que lo usan comparten la respuesta. */
  states(): Observable<WorkflowState[]> {
    this.cached ??= this.http.get<WorkflowState[]>(`${apiBaseUrl()}/maintenance/requests/workflow`).pipe(shareReplay({ bufferSize: 1, refCount: false }));
    return this.cached;
  }

  /** Vuelve a pedirlo la próxima vez (p. ej. tras un error de red). */
  reset(): void {
    this.cached = null;
  }
}

/** Texto en español de lo que falta para entrar a un estado. */
export const REQUIREMENT_LABELS: Record<Requirement, string> = {
  category: 'la categoría',
  priority: 'la prioridad',
  technician: 'un técnico',
  resolution_summary: 'el resumen de la resolución',
  reason: 'el motivo',
};

/** Lo que una persona completó en el diálogo de un paso. */
export interface TransitionData {
  category?: string;
  priority?: string;
  technicianId?: number;
  resolutionSummary?: string;
  reason?: string;
}
