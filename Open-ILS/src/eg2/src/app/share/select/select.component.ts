import { ChangeDetectionStrategy, Component, ElementRef, forwardRef, input, signal, viewChild } from '@angular/core';
import { ControlValueAccessor, NG_VALUE_ACCESSOR } from '@angular/forms';

export type SelectOption = { label: string, value: string };

// This component is a light wrapper around a native HTML <select>
@Component({
    selector: 'eg-select',
    standalone: true,
    imports: [],
    templateUrl: './select.component.html',
    changeDetection: ChangeDetectionStrategy.OnPush,
    providers: [
        {
            provide: NG_VALUE_ACCESSOR,
            useExisting: forwardRef(() => SelectComponent),
            multi: true,
        },
    ]
})
export class SelectComponent implements ControlValueAccessor {
    protected domId = input.required<string>();
    protected options = input<SelectOption[]>();
    protected required = input<boolean>(false);
    protected select = viewChild.required<ElementRef<HTMLSelectElement>>('select');

    protected onChange: any;
    protected onTouched: any;

    writeValue(value: string): void {
        this.select().nativeElement.value = value;
    }
    registerOnChange(fn: any): void {
        this.onChange = fn;
    }
    registerOnTouched(fn: any): void {
        this.onTouched = fn;
    }
    setDisabledState?(isDisabled: boolean): void {
        this.select().nativeElement.disabled = isDisabled;
    }
}
