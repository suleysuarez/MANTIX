/** Descarga un Blob en el navegador con el nombre indicado. */
export function saveBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.rel = 'noopener';
  document.body.appendChild(link);
  link.click();
  link.remove();
  // Se libera en el siguiente turno para que el navegador alcance a iniciar la descarga.
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

export function reportFilename(stem: string, extension: string, now = new Date()): string {
  const pad = (value: number) => String(value).padStart(2, '0');
  return `${stem}-${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}.${extension}`;
}
