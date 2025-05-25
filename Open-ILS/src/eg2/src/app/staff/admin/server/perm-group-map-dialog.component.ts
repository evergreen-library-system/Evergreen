/* eslint-disable no-shadow, @typescript-eslint/member-ordering */
import {Component, Input, OnDestroy, OnInit, Renderer2} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NgbModal, NgbTypeaheadSelectItemEvent} from '@ng-bootstrap/ng-bootstrap';
import {FormArray, FormBuilder} from '@angular/forms';
import {catchError, debounceTime, distinctUntilChanged, exhaustMap, map, takeUntil, tap, toArray,
    Observable, Subject, of, OperatorFunction} from 'rxjs';

interface PermEntry { id: number; label: string; }

@Component({
    selector: 'eg-perm-group-map-dialog',
    templateUrl: './perm-group-map-dialog.component.html'
})

/**
 * Ask the user which part is the lead part then merge others parts in.
 */
export class PermGroupMapDialogComponent
    extends DialogComponent implements OnInit, OnDestroy {

    @Input() permGroup: IdlObject;

    @Input() permissions: IdlObject[];

    // List of grp-perm-map objects that relate to the selected permission
    // group or are linked to a parent group.
    @Input() permMaps: IdlObject[];

    @Input() orgDepths: number[];

    // Note we have all of the permissions on hand, but rendering the
    // full list of permissions can caus sluggishness.  Render async instead.
    permEntries = this.permEntriesOperator();
    permEntriesFormatter = (entry: PermEntry): string => entry.label;
    selectedPermEntries: PermEntry[] = [];

    // Permissions the user may apply to the current group.
    trimmedPerms: IdlObject[] = [];

    permMapsForm = this.fb.group({ newPermMaps: this.fb.array([]) });
    get newPermMaps() {
        return this.permMapsForm.controls.newPermMaps as FormArray;
    }

    onCreate = new Subject<void>();
    onDestroy = new Subject<void>();

    constructor(
        private idl: IdlService,
        private pcrud: PcrudService,
        private modal: NgbModal,
        private renderer: Renderer2,
        private fb: FormBuilder) {
        super(modal);
    }

    ngOnInit() {

        this.permissions = this.permissions
            .sort((a, b) => a.code() < b.code() ? -1 : 1);

        this.onOpen$.pipe(
            tap(() => this.reset()),
            takeUntil(this.onDestroy)
        ).subscribe(() => this.focusPermSelector());

        this.onCreate.pipe(
            exhaustMap(() => this.create()),
            takeUntil(this.onDestroy)
        ).subscribe(success => this.close(success));

    }

    // Find entries whose code or description match the search term
    private permEntriesOperator(): OperatorFunction<string, PermEntry[]> {
        return term$ => term$.pipe(
            // eslint-disable-next-line no-magic-numbers
            debounceTime(300),
            map(term => (term ?? '').toLowerCase()),
            distinctUntilChanged(),
            map(term => this.permEntryResults(term))
        );
    }

    private permEntryResults(term: string): PermEntry[] {
        if (/^\s*$/.test(term)) {return [];}

        return this.trimmedPerms.reduce<PermEntry[]>((entries, p) => {
            if ((p.code().toLowerCase().includes(term) ||
                (p.description() || '').toLowerCase().includes(term)) &&
                !this.selectedPermEntries.find(s => s.id === p.id())
            ) {entries.push({ id: p.id(), label: p.code() });}
            return entries;
        }, []);
    }

    private reset() {
        this.permMapsForm = this.fb.group({
            newPermMaps: this.fb.array([])
        });
        this.selectedPermEntries = [];
        this.trimmedPerms = [];

        this.permissions.forEach(p => {

            // Prevent duplicate permissions, for-loop for early exit.
            for (let idx = 0; idx < this.permMaps.length; idx++) {
                const map = this.permMaps[idx];
                if (map.perm().id() === p.id() &&
                    map.grp().id() === this.permGroup.id()) {
                    return;
                }
            }

            this.trimmedPerms.push(p);
        });
    }

    private focusPermSelector(): void {
        const el = this.renderer.selectRootElement(
            '#select-perms'
        );
        if (el) {el.focus();}
    }

    select(event: NgbTypeaheadSelectItemEvent<PermEntry>): void {
        event.preventDefault();
        this.newPermMaps.push(this.fb.group({
            ...event.item, depth: 0, grantable: false
        }));
        this.selectedPermEntries.push({ ...event.item });
    }

    remove(index: number): void {
        this.newPermMaps.removeAt(index);
        this.selectedPermEntries.splice(index, 1);
        if (!this.selectedPermEntries.length) {this.focusPermSelector();}
    }

    create(): Observable<boolean> {
        const maps: IdlObject[] = this.newPermMaps.getRawValue().map(
            ({ id, depth, grantable }) => {
                const map = this.idl.create('pgpm');

                map.grp(this.permGroup.id());
                map.perm(id);
                map.grantable(grantable ? 't' : 'f');
                map.depth(depth);

                return map;
            });

        return this.pcrud.create(maps).pipe(
            catchError(() => of(false)),
            toArray(),
            map(newMaps => !newMaps.includes(false))
        );
    }

    ngOnDestroy(): void {
        this.onDestroy.next();
    }
}
