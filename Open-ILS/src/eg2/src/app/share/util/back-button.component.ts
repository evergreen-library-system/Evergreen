import { Component, Input } from '@angular/core';

@Component({
    selector: 'eg-back-button',
    template: `
    <button class="btn btn-info label-with-material-icon" type="button"
      (click)="goBack()" [disabled]="hasNoHistory()">
      <span class="material-icons" aria-hidden="true">keyboard_backspace</span>
      {{ label }}
    </button>
  `
})
export class BackButtonComponent {
  @Input() label: string = $localize`Return`;
  hasNoHistory(): boolean {
      return history.length <= 1;
  }

  goBack() {
      history.back();
  }
}
