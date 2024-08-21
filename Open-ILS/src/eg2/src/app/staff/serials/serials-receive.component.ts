import { Component, EventEmitter, Input, OnInit, Output, inject } from '@angular/core';
import { IdlObject } from '@eg/core/idl.service';
import { ItemLocationSelectModule } from '@eg/share/item-location-select/item-location-select.module';
import { CommonModule } from '@angular/common';
import { CommonWidgetsModule } from '@eg/share/common-widgets.module';
import { AbstractControl, FormArray, FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { NetService } from '@eg/core/net.service';
import { Observable, forkJoin, merge, tap, toArray } from 'rxjs';
import { AuthService } from '@eg/core/auth.service';
import { PrintService } from '@eg/share/print/print.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { EventService } from '@eg/core/event.service';
import { ToastService } from '@eg/share/toast/toast.service';
import { Router } from '@angular/router';
import { ComboboxEntry } from '@eg/share/combobox/combobox.component';
import { SerialsNoteComponent } from './serials-note.component';
import { SerialsService } from './serials.service';


@Component({
    selector: 'eg-serials-receive',
    standalone: true,
    imports: [CommonModule, ItemLocationSelectModule, CommonWidgetsModule, ReactiveFormsModule, SerialsNoteComponent],
    providers: [SerialsService],
    templateUrl: './serials-receive.component.html',
    styles: [
        '.receive-serials-grid td {padding: var(--spacing-1);}'
    ]
})
export class SerialsReceiveComponent implements OnInit {
    @Input() sitems: IdlObject[];
    @Input() bibRecordId: number;

    @Output() cancel = new EventEmitter<void>();

    barcodeModeOn = true;
    showCallNumberAffixes: boolean;
    itemsFormArray: FormArray;
    tableForm: FormGroup;

    callNumberPrefixes: ComboboxEntry[];
    callNumbers: ComboboxEntry[];
    callNumberSuffixes: ComboboxEntry[];

    defaultCallNumberPrefix: ComboboxEntry;
    defaultCallNumber: ComboboxEntry;
    defaultCallNumberSuffix: ComboboxEntry;

    auth = inject(AuthService);
    evt = inject(EventService);
    net = inject(NetService);
    pcrud = inject(PcrudService);
    printer = inject(PrintService);
    router = inject(Router);
    serials = inject(SerialsService);
    toast = inject(ToastService);

    ngOnInit() {
        this.showCallNumberAffixes = this.serials.shouldShowCallNumberAffixes();
        this.itemsFormArray = new FormArray(this.sitems.map((sitem) => this.formGroupForSitem(sitem)));
        this.tableForm = new FormGroup({
            items: this.itemsFormArray
        });
        if(this.anyItemsWithReceiveUnitTemplate) {
            // Add batch controls
            this.tableForm.addControl('batch', new FormGroup({
                prefix: new FormControl<ComboboxEntry>(null),
                callnumber: new FormControl<ComboboxEntry>(null),
                suffix: new FormControl<ComboboxEntry>(null),
                location: new FormControl(),
                modifier: new FormControl<ComboboxEntry>({id: null}),
                barcode: new FormControl('')
            }));

            // Add barcode options
            this.tableForm.addControl('barcodeOptions', new FormGroup({
                barcodeItems: new FormControl(true),
                autoGenerate: new FormControl(false),
                callNumberAffixes: new FormControl(this.showCallNumberAffixes)
            }));

            // Turn barcode mode on/off depending on the checkbox
            this.tableForm.get('barcodeOptions').get('barcodeItems').valueChanges.subscribe((value) => {
                this.barcodeModeOn = value;
                if (value) {
                    this.autoGenerateBarcodeCheckbox.enable();
                    this.showCallNumberAffixesCheckbox.enable();
                } else {
                    this.autoGenerateBarcodeCheckbox.disable();
                    this.showCallNumberAffixesCheckbox.disable();
                }
                this.itemsFormArray.controls.forEach((row) => {
                    if(value) {
                        this.turnOnBarcodeValidationForRow(row);
                    } else {
                        this.turnOffBarcodeValidationForRow(row);
                    }
                });
            });

            // Apply the auto-generate value to the barcode fields or clear them
            this.autoGenerateBarcodeCheckbox.valueChanges.subscribe((value) => {
                const autoGenerateToken = '@@AUTO';
                this.itemsFormArray.controls.forEach((row) => {
                    if (value) {
                        row.get('barcode')?.setValue(autoGenerateToken);
                        row.get('barcode')?.disable();
                    } else {
                        row.get('barcode')?.enable();
                        if (row.get('barcode')?.value === autoGenerateToken) {
                            row.get('barcode')?.setValue('');
                        }
                    }
                });
            });

            this.tableForm.get('barcodeOptions').get('callNumberAffixes').valueChanges.subscribe((value) => {
                this.showCallNumberAffixes = value;
                this.serials.storeCallNumberAffixPreference(value);
            });

            this.fetchCallNumberData$().subscribe(values => {
                this.callNumberPrefixes = values.prefixes;
                this.callNumbers = values.callNumbers;
                this.callNumberSuffixes = values.suffixes;
                this.itemsFormArray.controls.forEach((row) => {
                    row.get('prefix')?.setValue(values.defaultPrefix);
                    row.get('callnumber')?.setValue(values.defaultCallNumber);
                    row.get('suffix')?.setValue({id: values.defaultSuffix});
                });
            });
        }

        // Turn off validation for rows that are not selected
        // for receive
        this.itemsFormArray.controls.forEach((row) => {
            row.get('receive')?.valueChanges.subscribe((value) => {
                if (value === true) {
                    this.turnOnBarcodeValidationForRow(row);
                } else if (value === false) {
                    this.turnOffBarcodeValidationForRow(row);
                }
            });
        });
    }

    get anyItemsWithReceiveUnitTemplate(): boolean {
        return this.sitems.some((sitem) => {
            return sitem.stream().distribution().receive_unit_template();
        });
    }

    get anyItemsWithRoutingList(): boolean {
        return this.sitems.some((sitem) => {
            return sitem.stream().routing_list_users()?.length;
        });
    }

    get anyItemsSelectedForReceive(): boolean {
        return this.itemsFormArray.controls.some((row) => {
            return row.get('receive')?.value;
        });
    }

    get sitemsSelectedForReceive(): IdlObject[] {
        return this.sitems.filter((sitem, index) => {
            return this.itemsFormArray.at(index).get('receive')?.value;
        });
    }

    get sitemsSelectedForReceiveAndPrint(): IdlObject[] {
        return this.sitems.filter((sitem, index) => {
            return this.itemsFormArray.at(index).get('receive')?.value &&
               this.itemsFormArray.at(index).get('routing')?.value;
        });
    }

    handleReceive() {
        this.receiveItems$().subscribe((response) => {
            const evt = this.evt.parse(response);
            if (evt) {
                this.toast.danger(evt.toString());
            } else {
                this.reportSuccess();
            }
        });
    }

    handleReceiveAndPrint() {
        this.receiveItems$().subscribe((response) => {
            const evt = this.evt.parse(response);
            if (evt) {
                this.toast.danger(evt.toString());
            } else {
                this.sitemsSelectedForReceiveAndPrint.forEach((sitem) => {
                    this.printRoutingList(sitem);
                });
            }
        });
    }

    // Apply batch values to the other rows
    handleApplyBatch() {
        ['prefix', 'callnumber', 'suffix', 'location', 'modifier', 'barcode'].forEach((batchField) => {
            const batchControl = this.tableForm.get('batch')?.get(batchField);
            if (batchControl?.touched) {
                this.itemsFormArray.controls.forEach((row) => {
                    row.get(batchField)?.patchValue(batchControl?.value);
                });
            }
        });
    }

    receiveItems$(): Observable<any> {
        this.prepareForSunitGeneration();
        return this.net.request('open-ils.serial',
            'open-ils.serial.receive_items',
            this.auth.token(),
            this.sitemsSelectedForReceive,
            this.barcodeHash,
            this.callNumberHash,
            this.unitHash,
            this.hashOfHashes
        );
    }

    get showBarcodeFields(): boolean {
        return this.anyItemsWithReceiveUnitTemplate && this.barcodeModeOn;
    }

    // A serials item can have notes at various levels:
    //   * on the item itself
    //   * on the distribution
    //   * on the subscription
    // This method combines them all, regardless of level
    notesForSitem(sitem: IdlObject): IdlObject[] {
        const sitem_notes = sitem.notes() || [];
        const sdist_notes = sitem.stream().distribution().notes() || [];
        const ssub_notes = sitem.issuance().subscription().notes() || [];
        return sitem_notes.concat(sdist_notes, ssub_notes);
    }

    private printRoutingList(sitem: IdlObject) {
        const templateData = {
            issuance: sitem.issuance(),
            distribution: sitem.stream().distribution(),
            stream: sitem.stream(),
        };
        const getTheList$ = this.net.request('open-ils.serial',
            'open-ils.serial.routing_list_users.fleshed_and_ordered',
            this.auth.token(),
            sitem.stream().id())
            .pipe(
                toArray(),
                tap((list) => {
                    templateData['routing_list'] = list;
                }));
        const getTheTitle$ = this.pcrud.retrieve('mwde', this.bibRecordId)
            .pipe(tap((mwde) => {
                templateData['title'] = mwde.title();
            }));

        // Make both requests asynchronously, and when they
        // have both retrieved their data, print the routing list
        merge(getTheList$, getTheTitle$).subscribe({complete: () => {
            this.printer.print({
                templateName: 'serials_routing_list',
                contextData: templateData,
                printContext: 'receipt'
            });
            this.reportSuccess();
        }});
    }

    private reportSuccess() {
        this.toast.success($localize`Items received`);
        this.router.navigate(['/staff', 'catalog', 'record', this.bibRecordId]);
    }

    private get barcodeHash() {
        return this.hashFromFormValues('barcode');
    }

    private get callNumberHash() {
        return this.sitemsSelectedForReceive.reduce((hash, sitem, index) => {
            const value = this.itemsFormArray.at(index).get('callnumber')?.value?.label;
            if (value) {
                hash[sitem.id()] = [
                    this.itemsFormArray.at(index).get('prefix')?.value?.label || null,
                    value,
                    this.itemsFormArray.at(index).get('suffix')?.value?.label || null
                ];
            }
            return hash;
        }, {});
    }

    private get unitHash() {
        // When receiving, we should send an empty
        // hash to indicate that we want the Perl code
        // to generate some serial.units for us
        return {};
    }

    private get hashOfHashes() {
        return {
            circ_mods: this.sitemsSelectedForReceive.reduce((hash, sitem, index) => {
                const value = this.itemsFormArray.at(index).get('modifier')?.value?.id;
                if (value) {
                    hash[sitem.id()] = value;
                }
                return hash;
            }, {}),
            copy_locations: this.hashFromFormValues('location')
        };
    }

    private hashFromFormValues(field: string): {[key: number]: string} {
        return this.sitemsSelectedForReceive.reduce((hash, sitem, index) => {
            const value = this.itemsFormArray.at(index).get(field)?.value;
            if (value) {
                hash[sitem.id()] = value;
            }
            return hash;
        }, {});
    }

    private formGroupForSitem(sitem: IdlObject): FormGroup {
        const controls = {receive: new FormControl(true)};
        if (sitem.stream().distribution().receive_unit_template()) {
            controls['prefix'] = new FormControl<ComboboxEntry>({id: null});
            controls['callnumber'] = new FormControl<ComboboxEntry>({id: null}, Validators.required);
            controls['suffix'] = new FormControl<ComboboxEntry>({id: null});
            controls['location'] = new FormControl(this.defaultLocationForSitem(sitem));
            controls['modifier'] = new FormControl<ComboboxEntry>(this.defaultCircModifier(sitem));
            controls['barcode'] = new FormControl('', Validators.required);
        }
        if (sitem.stream().routing_list_users()?.length) {
            controls['routing'] = new FormControl(true);
        }
        return new FormGroup(controls);
    }

    private defaultCircModifier(sitem: IdlObject): ComboboxEntry {
        if (sitem.stream().distribution().receive_unit_template().circ_modifier) {
            const circModifier = sitem.stream().distribution().receive_unit_template().circ_modifier();
            if (circModifier) {
                return {id: circModifier};
            }
        }
        return {id: null};
    }

    // Setting the serial.unit id to -1 here will cause the Perl code
    // to generate a new serial.unit for us with our desired barcode
    private prepareForSunitGeneration() {
        this.sitems.forEach((sitem) => {
            // We can only generate serial.units for items that have
            // a receive unit template, so no need to set the unit id
            // to -1 for items without a template.
            // Similarly, we should only send -1 to
            // open-ils.serial.receive_items if the user has barcode
            // mode on.
            if (sitem.stream().distribution().receive_unit_template() && this.barcodeModeOn) {
                sitem.unit(-1);
            }
        });
    }

    private turnOnBarcodeValidationForRow(row: AbstractControl) {
        row.get('barcode')?.setValidators(Validators.required);
        row.get('barcode')?.updateValueAndValidity();
        row.get('callnumber')?.setValidators(Validators.required);
        row.get('callnumber')?.updateValueAndValidity();
    }

    private turnOffBarcodeValidationForRow(row: AbstractControl) {
        row.get('barcode')?.clearValidators();
        row.get('barcode')?.updateValueAndValidity();
        row.get('callnumber')?.clearValidators();
        row.get('callnumber')?.updateValueAndValidity();
    }

    private get autoGenerateBarcodeCheckbox(): AbstractControl {
        return this.tableForm.get('barcodeOptions').get('autoGenerate');
    }

    private get showCallNumberAffixesCheckbox(): AbstractControl {
        return this.tableForm.get('barcodeOptions').get('callNumberAffixes');
    }

    private fetchCallNumberData$(): Observable<CallNumberData> {
        return forkJoin({
            prefixes: this.serials.callNumberPrefixesAsComboboxEntries$(),
            callNumbers: this.serials.callNumbersAsComboboxEntries$(this.bibRecordId, this.distributionLibraryId),
            suffixes: this.serials.callNumberSuffixesAsComboboxEntries$(),
            defaultPrefix: this.serials.defaultCallNumberPrefix$(this.bibRecordId, this.distributionLibraryId),
            defaultCallNumber: this.serials.defaultCallNumber$(this.bibRecordId, this.distributionLibraryId),
            defaultSuffix: this.serials.defaultCallNumberSuffix$(this.bibRecordId, this.distributionLibraryId)
        });
    }

    private get distributionLibraryId(): number {
        if (typeof this.sitems[0]?.stream()?.distribution()?.holding_lib()?.id === 'function') {
            return this.sitems[0].stream().distribution().holding_lib().id();
        }
        return null;
    }

    private defaultLocationForSitem(sitem: IdlObject): IdlObject {
        if (sitem.stream().distribution().receive_unit_template().location) {
            return sitem.stream().distribution().receive_unit_template().location();
        }
        return null;
    }
}

interface CallNumberData {
    prefixes: ComboboxEntry[];
    callNumbers: ComboboxEntry[];
    suffixes: ComboboxEntry[];
    defaultPrefix: ComboboxEntry;
    defaultCallNumber: ComboboxEntry;
    defaultSuffix: ComboboxEntry;
}
