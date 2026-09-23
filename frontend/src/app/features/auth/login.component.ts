import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../../core/auth.service';

@Component({
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  template: `
    <main class="auth-page">
      <section class="auth-card">
        <h1>Technology Equipment Maintenance</h1>
        <p>Sign in to manage your maintenance workspace.</p>
        <form [formGroup]="form" (ngSubmit)="submit()">
          <label>Email <input type="email" formControlName="email" autocomplete="email" /></label>
          <small *ngIf="form.controls.email.touched && form.controls.email.invalid">Enter a valid email.</small>
          <label>Password <input type="password" formControlName="password" autocomplete="current-password" /></label>
          <small *ngIf="form.controls.password.touched && form.controls.password.invalid">Password must have at least 8 characters.</small>
          <p class="error" *ngIf="error">{{ error }}</p>
          <button type="submit" [disabled]="form.invalid || loading">{{ loading ? 'Signing in…' : 'Sign in' }}</button>
        </form>
      </section>
    </main>
  `,
  styles: [
    `.auth-page { min-height: 100vh; display: grid; place-items: center; background: #f1f5f9; }
     .auth-card { width: min(92vw, 420px); padding: 2rem; background: white; border-radius: 12px; box-shadow: 0 10px 30px #0f172a1a; }
     form { display: grid; gap: .75rem; } label { display: grid; gap: .35rem; font-weight: 600; } input { padding: .7rem; border: 1px solid #cbd5e1; border-radius: 6px; } button { margin-top: .5rem; padding: .75rem; border: 0; border-radius: 6px; background: #1d4ed8; color: white; font-weight: 700; } button:disabled { opacity: .55; } small, .error { color: #b91c1c; }`,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class LoginComponent {
  private readonly formBuilder = inject(FormBuilder);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  readonly form = this.formBuilder.nonNullable.group({
    email: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required, Validators.minLength(8)]],
  });
  loading = false;
  error = '';

  submit(): void {
    if (this.form.invalid) { this.form.markAllAsTouched(); return; }
    this.loading = true;
    this.error = '';
    const { email, password } = this.form.getRawValue();
    this.auth.login(email, password).subscribe({
      next: () => void this.router.navigate(['/dashboard']),
      error: () => { this.error = 'Invalid email or password.'; this.loading = false; },
    });
  }
}
