import { signal } from '@angular/core';
import { Observable } from 'rxjs';

import { TransitionData, WorkflowState } from '../../core/workflow.service';
import { KanbanOutcome } from './kanban-board.component';

export const DIALOG_TITLES: Record<string, string> = {
  triaged: 'Clasificar ticket',
  assigned: 'Asignar técnico',
  resolved: 'Resolver ticket',
  cancelled: 'Cancelar ticket',
};
export const DIALOG_CONFIRM: Record<string, string> = { triaged: 'Clasificar', assigned: 'Asignar', resolved: 'Resolver', cancelled: 'Cancelar ticket' };

/** Diálogo abierto por un paso que pide datos; `answer(null)` lo cancela. */
export interface TransitionDialogRequest {
  title: string;
  subtitle: string;
  confirm: string;
  requires: WorkflowState['requires'];
  initial: TransitionData;
  answer: (data: TransitionData | null) => void;
}

export interface TransitionAsk {
  to: string;
  subtitle: string;
  requires: WorkflowState['requires'];
  initial?: TransitionData;
  /** Título y botón; por defecto, los del estado destino. */
  title?: string;
  confirm?: string;
}

/**
 * Pasos del tablero que exigen datos (categoría, técnico, resumen, motivo…): abre el diálogo, espera la
 * respuesta y ejecuta el paso con ella. Si se cancela, la tarjeta vuelve a su columna. Lo comparten
 * Tickets y Solicitudes pendientes, así el flujo es el mismo en ambas.
 */
export class TransitionFlow {
  readonly dialog = signal<TransitionDialogRequest | null>(null);
  readonly busy = signal(false);

  run(ask: TransitionAsk, execute: (data: TransitionData) => Observable<KanbanOutcome>): Observable<KanbanOutcome> {
    if (ask.requires.length === 0) {
      return execute({});
    }
    return new Observable<KanbanOutcome>((subscriber) => {
      const finish = (outcome: KanbanOutcome): void => {
        this.busy.set(false);
        this.dialog.set(null);
        subscriber.next(outcome);
        subscriber.complete();
      };
      this.dialog.set({
        title: ask.title ?? DIALOG_TITLES[ask.to] ?? 'Completa los datos',
        subtitle: ask.subtitle,
        confirm: ask.confirm ?? DIALOG_CONFIRM[ask.to] ?? 'Confirmar',
        requires: ask.requires,
        initial: ask.initial ?? {},
        answer: (data) => {
          if (!data) {
            finish({ ok: false, cancelled: true });
            return;
          }
          this.busy.set(true);
          execute(data).subscribe(finish);
        },
      });
    });
  }
}
