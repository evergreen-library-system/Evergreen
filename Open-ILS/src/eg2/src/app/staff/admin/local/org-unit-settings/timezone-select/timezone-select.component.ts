import { Component, ViewChild, forwardRef, inject } from '@angular/core';
import { ControlValueAccessor, NG_VALUE_ACCESSOR } from '@angular/forms';
import { ComboboxComponent, ComboboxEntry } from '@eg/share/combobox/combobox.component';
import { Timezone } from '@eg/share/util/timezone';

@Component({
    selector: 'eg-timezone-select',
    templateUrl: './timezone-select.component.html',
    providers: [
        Timezone,
        {
            provide: NG_VALUE_ACCESSOR,
            useExisting: forwardRef(() => TimezoneSelectComponent),
            multi: true
        }],
    imports: [ComboboxComponent]
})
export class TimezoneSelectComponent implements ControlValueAccessor {
    private timezone = inject(Timezone);

    entries: ComboboxEntry[];
    startId: string;

    constructor() {
        this.entries = this.timezone.values().map((timezoneValue) => {
            return {id: timezoneValue, label: timezoneValue};
        });
    }

  @ViewChild('combobox') combobox: ComboboxComponent;

  writeValue(id: string): void {
      if (this.combobox) {
          this.combobox.selectedId = id;
      } else {
      // Too early in the lifecycle
          this.startId = id;
      }
  }

  cboxChanged(entry: ComboboxEntry) {
      this.propagateChange(entry?.id);
  }

  // Stub functions required by ControlValueAccessor
  propagateChange = (_: any) => {};
  propagateTouch = () => {};
  registerOnChange(fn) {
      this.propagateChange = fn;
  }
  registerOnTouched(fn) {
      this.propagateTouch = fn;
  }
}
