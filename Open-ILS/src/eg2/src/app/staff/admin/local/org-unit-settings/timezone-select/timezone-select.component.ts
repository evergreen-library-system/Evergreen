import { Component, ViewChild, forwardRef } from '@angular/core';
import { ControlValueAccessor, NG_VALUE_ACCESSOR } from '@angular/forms';
import { ComboboxComponent, ComboboxEntry } from '@eg/share/combobox/combobox.component';
import { Timezone } from '@eg/share/util/timezone';

@Component({
    selector: 'eg-timezone-select',
    templateUrl: './timezone-select.component.html',
    providers: [{
        provide: NG_VALUE_ACCESSOR,
        useExisting: forwardRef(() => TimezoneSelectComponent),
        multi: true
    }]
})
export class TimezoneSelectComponent implements ControlValueAccessor {
    entries: ComboboxEntry[];
    startId: string;

    constructor(
    private timezone: Timezone
    ) {
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
