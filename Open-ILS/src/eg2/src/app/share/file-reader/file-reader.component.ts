/**
 * <eg-file-reader [(ngModel)]="fileContents">
 * </eg-file-reader>
 */
import {Component, forwardRef} from '@angular/core';
import {ControlValueAccessor, NG_VALUE_ACCESSOR} from '@angular/forms';

@Component({
    selector: 'eg-file-reader',
    templateUrl: './file-reader.component.html',
    providers: [{
        provide: NG_VALUE_ACCESSOR,
        useExisting: forwardRef(() => FileReaderComponent),
        multi: true
    }]
})
export class FileReaderComponent implements ControlValueAccessor {

    // Stub functions required by ControlValueAccessor
    propagateChange = (_: any) => {};
    propagateTouch = () => {};

    changeListener($event): void {
        const me = this;
        if ($event.target.files.length < 1) {
            return;
        }
        const reader = new FileReader();
        reader.onloadend = function(e) {
            me.propagateChange(me.parseFileContents(reader.result));
        };
        reader.readAsText($event.target.files[0]);
    }

    parseFileContents(contents): Array<string> {
        const values = contents.split('\n');
        values.forEach((val, idx) => {
            val = val.replace(/\s+$/, '');
            val = val.replace(/^\s+/, '');
            values[idx] = val;
        });
        return values;
    }

    writeValue(value: any) {
        // intentionally empty
    }

    registerOnChange(fn) {
        this.propagateChange = fn;
    }

    registerOnTouched(fn) {
        this.propagateTouch = fn;
    }
}
