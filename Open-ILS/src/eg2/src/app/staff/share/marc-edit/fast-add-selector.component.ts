import { Component, OnInit, output } from '@angular/core';
import { FormControl, FormGroup, ReactiveFormsModule } from '@angular/forms';
import { Maybe, None, Some } from '@eg/share/maybe';

export interface FastAddItem {
    label: string,
    barcode: string,
    fast_add: boolean
}

@Component({
    selector: 'eg-fast-add-selector',
    templateUrl: './fast-add-selector.component.html',
    standalone: true,
    imports: [ReactiveFormsModule]
})
export class FastAddSelectorComponent implements OnInit {
    public fastAddItemChange = output<Maybe<FastAddItem>>();

    protected form = new FormGroup({
        fastAddItem: new FormControl(false),
        callNumber: new FormControl(''),
        barcode: new FormControl('')
    });

    protected get showFields(): boolean {
        return this.fastAddItem;
    }

    private isValid(): boolean {
        return this.fastAddItem && !!this.callNumber && !!this.barcode;
    }

    private get fastAddItem(): boolean {
        return this.form.get('fastAddItem').value;
    }

    private get barcode(): string {
        return this.form.get('barcode').value;

    }

    private get callNumber(): string {
        return this.form.get('callNumber').value;
    }

    ngOnInit(): void {
        this.form.valueChanges.subscribe(() => {
            if(this.isValid()) {
                this.fastAddItemChange.emit(new Some<FastAddItem>({label: this.callNumber, barcode: this.barcode, fast_add: true}));
            } else {
                this.fastAddItemChange.emit(new None<FastAddItem>());
            }
        });
    }
}
