import { Component, Input, ViewChild, ElementRef, ViewEncapsulation, forwardRef } from '@angular/core';
import { ControlValueAccessor, NG_VALUE_ACCESSOR } from '@angular/forms';

@Component({
    selector: 'eg-credential-input',
    templateUrl: './credential-input.component.html',
    styleUrls: ['./credential-input.component.css'],
    encapsulation: ViewEncapsulation.Emulated,
    providers: [{
        provide: NG_VALUE_ACCESSOR,
        useExisting: forwardRef(() => CredentialInputComponent),
        multi: true
    }]
})
export class CredentialInputComponent implements ControlValueAccessor {

  @Input() domId: string;
  @ViewChild('password')
      passwordInput: ElementRef;


  ariaDescription: string = $localize`Your password is not visible.`;
  passwordVisible: boolean;

  togglePasswordVisibility() {
      this.passwordVisible = !this.passwordVisible;
      if (this.passwordVisible) {
          this.ariaDescription = $localize`Your password is visible!`;
      } else {
          this.ariaDescription = $localize`Your password is not visible.`;
      }
      setTimeout(() => this.passwordInput.nativeElement.focus());
  }
  writeValue(value: any): void {
      this.passwordInput.nativeElement.value = value;
  }

  onChange = (_: any) => {};
  onTouched = () => {};
  registerOnChange(fn: (value: string) => any): void {
      this.onChange = fn;
  }
  registerOnTouched(fn: () => any): void {
      this.onTouched = fn;
  }
}
