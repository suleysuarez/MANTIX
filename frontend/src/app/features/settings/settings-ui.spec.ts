import { actionLabel, frequencyText, integrationLabel, jobName, jobStatus, jobStatusLabel } from './settings-ui';

describe('settings-ui', () => {
  it('writes the frequency in plain Spanish', () => {
    expect(frequencyText(15)).toBe('Cada 15 min');
    expect(frequencyText(60)).toBe('Cada hora');
    expect(frequencyText(360)).toBe('Cada 6 h');
    expect(frequencyText(1440)).toBe('Diaria');
    expect(frequencyText(2880)).toBe('Cada 2 días');
    expect(frequencyText(null)).toBe('—');
  });

  it('calls a healthy integration connected and keeps the other states in words', () => {
    expect(integrationLabel('ok')).toBe('Conectada');
    expect(integrationLabel('warning')).toBe('Atención');
    expect(integrationLabel('error')).toBe('Con fallo');
    expect(integrationLabel('disabled')).toBe('Desactivado');
  });

  it('translates the task name and falls back to the server name for unknown ones', () => {
    expect(jobName({ id: 'schedule-reminders', name: 'Preventive maintenance reminders' })).toBe('Recordatorios de mantenimiento preventivo');
    expect(jobName({ id: 'other', name: 'Other job' })).toBe('Other job');
  });

  it('shows a stopped scheduler as disabled whatever the last result was', () => {
    expect(jobStatus({ running: false, last_status: 'ok' })).toBe('disabled');
    expect(jobStatusLabel(jobStatus({ running: true, last_status: 'ok' }))).toBe('Operativa');
    expect(jobStatusLabel(jobStatus({ running: true, last_status: 'never' }))).toBe('Sin ejecutar');
    expect(jobStatusLabel(jobStatus({ running: true, last_status: 'error' }))).toBe('Con fallo');
  });

  it('names audit actions and shows unknown ones as they are', () => {
    expect(actionLabel('user.created')).toBe('Creación de usuario');
    expect(actionLabel('something.new')).toBe('something.new');
  });
});
