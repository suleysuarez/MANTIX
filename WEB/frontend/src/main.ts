import { bootstrapApplication } from '@angular/platform-browser';

import { appConfig } from './app/app.config';
import { AppComponent } from './app/app.component';
import { loadRuntimeConfig } from './app/core/api.config';

// La URL del API debe conocerse antes de que cualquier servicio se construya.
loadRuntimeConfig()
  .then(() => bootstrapApplication(AppComponent, appConfig))
  .catch((error: unknown) => console.error(error));
