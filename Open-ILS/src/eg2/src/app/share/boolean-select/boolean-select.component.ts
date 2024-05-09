/* eslint-disable */
import { Component, ChangeDetectorRef, forwardRef, OnInit, Input, Output } from '@angular/core';
import {ControlValueAccessor, NG_VALUE_ACCESSOR} from '@angular/forms';

@Component({
    selector: 'eg-bool-select',
    templateUrl: './boolean-select.component.html',
    styleUrls: ['./boolean-select.component.css'],
    providers: [
        {
            provide: NG_VALUE_ACCESSOR,
            useExisting: forwardRef(() => BooleanSelectComponent),
            multi: true
        }
    ]
})

export class BooleanSelectComponent implements ControlValueAccessor {

  @Input() label: string;
  @Input() name: string;
  @Input() options: Array<{ label: string; value: any }> = [
      { label: $localize`Yes`, value: true },
      { label: $localize`No`, value: false },
  ];
  private _value = false;
  private _disabled = false;
  private _required = false;

  onChange: (value: boolean) => void = () => {};
  onTouched: () => void = () => {};

  get value(): boolean {
      return this._value;
  }

  set value(value: boolean) {
      this._value = value;
      this.onChange(value);
      this.onTouched();
  }

  writeValue(value: any): void {
      this._value = value;
      this.cdr.detectChanges();
  }

  registerOnChange(fn: (value: boolean) => void): void {
      this.onChange = fn;
  }

  registerOnTouched(fn: () => void): void {
      this.onTouched = fn;
  }

  get disabled(): boolean {
      return this._disabled;
  }

  set disabled(value: boolean) {
      this._disabled = value;
  }

  setDisabledState?(isDisabled: boolean): void {
      this.disabled = isDisabled;
  }

  get required(): boolean {
      return this._required;
  }

  set required(value: boolean) {
      this._required = value;
  }

  setRequiredState?(isRequired: boolean): void {
      this.required = isRequired;
  }

  constructor(public cdr: ChangeDetectorRef) {}

  ngOnInit(): void {}

}
