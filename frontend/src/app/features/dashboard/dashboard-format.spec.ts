import { changeTone, formatChange, formatDowntime, formatHours, formatPct, reasonLabel, sparkline } from './dashboard-format';

describe('dashboard-format', () => {
  it('formats hours in the unit that reads best and shows a dash without data', () => {
    expect(formatHours(null)).toBe('—');
    expect(formatHours(0.25)).toBe('15 min');
    expect(formatHours(12.5)).toBe('12,5 h');
    expect(formatHours(12)).toBe('12 h');
    expect(formatHours(72)).toBe('3 d');
  });

  it('formats percentages and variations', () => {
    expect(formatPct(null)).toBe('—');
    expect(formatPct(87.5)).toBe('87,5%');
    expect(formatChange(null)).toBe('');
    expect(formatChange(12.5)).toBe('▲ 12,5%');
    expect(formatChange(-50)).toBe('▼ 50%');
    expect(formatChange(0)).toBe('= 0%');
  });

  it('colours a change by whether going up is good or bad', () => {
    expect(changeTone(-20, 'lower')).toBe('good'); // MTTR went down
    expect(changeTone(20, 'lower')).toBe('bad');
    expect(changeTone(5, 'higher')).toBe('good'); // SLA went up
    expect(changeTone(-5, 'higher')).toBe('bad');
    expect(changeTone(null, 'higher')).toBe('neutral');
    expect(changeTone(0, 'lower')).toBe('neutral');
  });

  it('draws a sparkline only with two or more values and skips gaps', () => {
    expect(sparkline([], 100, 20)).toBeNull();
    expect(sparkline([null, 5, null], 100, 20)).toBeNull();
    const points = sparkline([1, null, 3], 100, 20)!.split(' ');
    expect(points.length).toBe(2);
    expect(points[0].startsWith('0.0,')).toBeTrue();
    expect(points[1].startsWith('100.0,')).toBeTrue();
  });

  it('labels alert reasons and downtime', () => {
    expect(reasonLabel('sla_breached')).toBe('SLA vencido');
    expect(formatDowntime(null)).toBe('Sin registro de fecha');
    expect(formatDowntime(5)).toBe('5 h');
    expect(formatDowntime(30)).toBe('1 d 6 h');
    expect(formatDowntime(48)).toBe('2 d');
  });
});
