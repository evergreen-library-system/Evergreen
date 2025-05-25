import {Component, ViewChild, OnInit, OnDestroy, Input} from '@angular/core';
import {Subscription, EMPTY, from, lastValueFrom,
    defaultIfEmpty, catchError, concatMap, switchMap, tap} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {DateUtil} from '@eg/share/util/date';
import {PatronNoteDialogComponent
} from '@eg/staff/share/patron/note-dialog.component';


enum NoteAction {
    Archive,
    Unarchive,
    Remove
}

@Component({
    selector: 'eg-patron-messages',
    templateUrl: 'messages.component.html'
})
export class PatronMessagesComponent implements OnInit, OnDestroy {

    @Input() patronId: number;

    mainDataSource: GridDataSource = new GridDataSource();
    archiveDataSource: GridDataSource = new GridDataSource();

    startDateYmd: string;
    endDateYmd: string;

    @ViewChild('mainGrid') private mainGrid: GridComponent;
    @ViewChild('archiveGrid') private archiveGrid: GridComponent;
    @ViewChild('noteDialog')
    private noteDialog: PatronNoteDialogComponent;

    private subscriptions = new Subscription();

    constructor(
        private org: OrgService,
        private net: NetService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private serverStore: ServerStoreService,
        public patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {

        const orgIds = this.org.fullPath(this.auth.user().ws_ou(), true);

        const start = new Date();
        start.setFullYear(start.getFullYear() - 1);
        this.startDateYmd = DateUtil.localYmdFromDate(start);
        this.endDateYmd = DateUtil.localYmdFromDate(); // now

        const flesh = {
            flesh: 1,
            flesh_fields: {
                aump: ['standing_penalty', 'editor', 'staff']
            },
            order_by: {}
        };

        this.mainDataSource.getRows = (pager: Pager, sort: any[]) => {

            const orderBy: any = {aump: 'create_date'};
            if (sort.length) {
                orderBy.aump = sort[0].name + ' ' + sort[0].dir;
            }

            const query = {
                usr: this.patronId,
                org_unit: orgIds,
                '-or' : [
                    {stop_date: null},
                    {stop_date: {'>' : 'now'}}
                ]
            };

            flesh.order_by = orderBy;
            return this.pcrud.search('aump', query, flesh, {authoritative: true});
        };

        this.archiveDataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {aump: 'create_date'};
            if (sort.length) {
                orderBy.aump = sort[0].name + ' ' + sort[0].dir;
            }

            const query = {
                usr: this.patronId,
                org_unit: orgIds,
                stop_date: {'<' : 'now'},
                create_date: {between: this.dateRange()}
            };

            flesh.order_by = orderBy;

            return this.pcrud.search('aump', query, flesh, {authoritative: true});
        };
    }

    ngOnDestroy(): void {
        // This will unsubscribe from all child subscriptions that we added at once
        this.subscriptions.unsubscribe();
    }

    dateRange(): string[] {

        let endDate = this.endDateYmd;
        const today = DateUtil.localYmdFromDate();

        if (endDate === today) { endDate = 'now'; }

        return [this.startDateYmd, endDate];
    }

    dateChange(iso: string, start?: boolean) {
        if (start) {
            this.startDateYmd = iso;
        } else {
            this.endDateYmd = iso;
        }
        this.archiveGrid.reload();
    }

    applyNote() {
        this.noteDialog.note = null;
        this.noteDialog.open({size: 'lg'}).subscribe(changes => {
            if (changes) {
                this.context.refreshPatron()
                    .then(_ => this.mainGrid.reload());
            }
        });
    }

    modify(notes: IdlObject | IdlObject[]) {
        console.debug('MessageComponent: modify(), notes', notes);
        let modified = false;
        const notesArray = Array.isArray(notes) ? notes : [notes];

        const dialogSequence$ = from(notesArray).pipe(
            concatMap(note => {
                this.noteDialog.note = note;
                return this.noteDialog.open({size: 'lg'}).pipe(
                    tap(changed => {
                        if (changed) {
                            modified = true;
                        }
                    }),
                    defaultIfEmpty(false)  // Provides a default value if no emission occurs
                );
            })
        );

        lastValueFrom(dialogSequence$).then(() => {
            if (modified) {
                this.mainGrid.reload();
                this.archiveGrid.reload();
            }
        }).catch(error => {
            console.error('Error processing penalties:', error);
        });
    }

    handleNotes(notes: IdlObject[], action: NoteAction, className: string, idMethodName: string): void {
        this.subscriptions.add(
            this.pcrud.search(className, { id: notes.map(note => note[idMethodName]()) }, {}, {atomic: true}).pipe(
                tap(objects => {
                    // Handle stop_date based on action
                    if (action === NoteAction.Archive || action === NoteAction.Unarchive) {
                        const stopDate = action === NoteAction.Archive ? 'now' : null;
                        objects.forEach(obj => obj.stop_date(stopDate));
                    }
                }),
                switchMap(objects => {
                    // Determine the operation based on action
                    switch (action) {
                        case NoteAction.Archive:
                        case NoteAction.Unarchive:
                            return this.pcrud.update(objects);
                        case NoteAction.Remove:
                            return this.pcrud.remove(objects);
                    }
                }),
                catchError((error: unknown) => {
                    console.error(`MessagesComponent: Error handling ${className} for action ${action}:`, error);
                    return EMPTY;
                })
            ).subscribe({
                next: _ => {
                    this.context.refreshPatron().then(() => {
                        this.mainGrid.reload();
                        this.archiveGrid.reload();
                    });
                },
                error: (err: unknown) => {
                    console.error(`MessagesComponent: Failed to handle ${className}:`, err);
                }
            })
        );
    }

    handlePenalties(notes: IdlObject[], action: NoteAction): void {
        this.handleNotes(notes, action, 'ausp', 'ausp_id');
    }

    handleMessages(notes: IdlObject[], action: NoteAction): void {
        this.handleNotes(notes, action, 'aum', 'aum_id');
    }

    archive(notes: IdlObject[]): void {
        if (notes.length === 0 || !window.confirm($localize`Archive the selected notes?`)) {
            return;
        }
        this.handlePenalties(notes, NoteAction.Archive);
        this.handleMessages(notes, NoteAction.Archive);
    }

    unArchive(notes: IdlObject[]): void {
        if (notes.length === 0 || !window.confirm($localize`Unarchive the selected notes?`)) {
            return;
        }
        this.handlePenalties(notes, NoteAction.Unarchive);
        this.handleMessages(notes, NoteAction.Unarchive);
    }

    remove(notes: IdlObject[]): void {
        if (notes.length === 0 || !window.confirm($localize`Remove the selected notes?`)) {
            return;
        }
        this.handlePenalties(notes, NoteAction.Remove);
        this.handleMessages(notes, NoteAction.Remove);
    }
}



