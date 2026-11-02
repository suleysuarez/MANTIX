/**
 * Escapa una celda CSV. Un texto que empieza por `=`, `+`, `-` o `@` lo interpretaría una hoja
 * de cálculo como fórmula (inyección CSV): se antepone un apóstrofo para que se lea como texto.
 */
export function csvCell(value: unknown): string {
  let text = String(value ?? '');
  if (/^[=+\-@\t\r]/.test(text)) {
    text = `'${text}`;
  }
  return /[",\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

/** Filas a texto CSV con saltos CRLF (la primera fila son los encabezados). */
export function toCsv(rows: unknown[][]): string {
  return rows.map((row) => row.map(csvCell).join(',')).join('\r\n');
}
