import { WorkflowState } from '../../core/workflow.service';
import { allowedTargets, permissionBlock } from './transition-flow';

const state = (status: string, allowed: string[], over: Partial<WorkflowState> = {}): WorkflowState => ({
  status, order: 1, allowed_targets: allowed, requires: [], terminal: allowed.length === 0, ...over,
});

/** Lo que el servidor le diría a un técnico: puede trabajar, no asignar ni cancelar. */
const technicianView: WorkflowState[] = [
  state('assigned', ['in_progress', 'cancelled'], { can_enter: false, permission: 'tickets:asignar' }),
  state('in_progress', ['waiting', 'resolved', 'cancelled'], { can_enter: true, permission: 'tickets:cambiar_estado' }),
  state('waiting', ['in_progress', 'cancelled'], { can_enter: true }),
  state('resolved', ['closed', 'in_progress'], { can_enter: true }),
  state('closed', [], { can_enter: true }),
  state('cancelled', [], { can_enter: false, permission: 'solicitudes:aprobar' }),
];

describe('allowedTargets', () => {
  it('only offers the states the role can enter', () => {
    expect(allowedTargets({ can_act: true }, 'in_progress', technicianView)).toEqual(['waiting', 'resolved']);
    expect(allowedTargets({ can_act: true }, 'assigned', technicianView)).toEqual(['in_progress']);
  });

  it('offers nothing for a card the person cannot work (not assigned to them)', () => {
    expect(allowedTargets({ can_act: false }, 'in_progress', technicianView)).toEqual([]);
  });

  it('offers everything the workflow allows to someone who can enter every state', () => {
    const supervisorView = technicianView.map((s) => ({ ...s, can_enter: true }));
    expect(allowedTargets({ can_act: true }, 'in_progress', supervisorView)).toEqual(['waiting', 'resolved', 'cancelled']);
  });

  it('does not block anything when the server did not say (older answer): the server still decides', () => {
    const plain = [state('assigned', ['in_progress']), state('in_progress', [])];
    expect(allowedTargets({}, 'assigned', plain)).toEqual(['in_progress']);
  });

  it('a final state has nowhere to go', () => {
    expect(allowedTargets({ can_act: true }, 'closed', technicianView)).toEqual([]);
  });
});

describe('permissionBlock', () => {
  const label = (status: string): string => status.toUpperCase();

  it('explains that only their own tickets can be moved', () => {
    expect(permissionBlock({ can_act: false }, 'resolved', technicianView, label)).toBe('Solo puedes mover los tickets que te asignaron.');
  });

  it('names the state and the permission the role lacks', () => {
    expect(permissionBlock({ can_act: true }, 'cancelled', technicianView, label)).toBe(
      'Tu rol no puede pasar tickets a «CANCELLED» (Requiere permiso de Solicitudes · aprobar o rechazar).',
    );
  });

  it('says nothing when the block is not about permissions', () => {
    expect(permissionBlock({ can_act: true }, 'resolved', technicianView, label)).toBeNull();
  });
});
