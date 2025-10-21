import {Component, OnInit, OnDestroy, Input, ViewChild} from '@angular/core';
import {Observable, of, from, Subscription, tap, catchError, switchMap} from 'rxjs';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {PermService} from '@eg/core/perm.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

/**
 * Dialog container for patron note (penalty/message) application
 *
 * <eg-patron-note-dialog [patronId]="myPatronId">
 * </eg-patron-note-dialog>
 */

@Component({
    selector: 'eg-patron-note-dialog',
    templateUrl: 'note-dialog.component.html'
})

export class PatronNoteDialogComponent
    extends DialogComponent implements OnInit, OnDestroy {

    @Input() patronId: number;
    @Input() patron: IdlObject;
    @Input() note: IdlObject;               // actor.usr_message_penalty (aump)
    penalty: IdlObject;                     // actor.usr_standing_penalty (ausp)
    penaltyType: IdlObject;                 // config.standing_penalty (csp)
    penaltyTypeId: number;
    usr_message: IdlObject;                 // actor.usr_message (aum)
    @Input() orgId: number;
    @Input() defaultPub: boolean;
    @Input() defaultTitle: string;
    @Input() defaultMessage: string;
    @Input() readOnly = false;
    org_unit: IdlObject;                    // actor.org_unit (aou)
    pub = false;
    title = '';
    message = '';
    initials = '';
    requireInitials = false;

    /* eslint-disable no-magic-numbers */
    ALERT_NOTE = 20;
    SILENT_NOTE = 21;
    STAFF_CHR = 25;
    /* eslint-enable no-magic-numbers */

    goodOrgs: number[] = [];
    penaltyTypes: IdlObject[] = [];
    penaltyTypesMap: Map<number, IdlObject>;
    cbPenaltyTypeEntries: ComboboxEntry[] = [];
    cbPenaltyTypeEntriesMap: Map<number, ComboboxEntry>;

    penaltyTypeFromSelect: ComboboxEntry;
    orgDepthFromSelect = 0;
    penaltyTypeFromButton: number;
    dataLoaded = false;

    @ViewChild('successMsg', {static: false}) successMsg: StringComponent;
    @ViewChild('errorMsg', {static: false}) errorMsg: StringComponent;

    constructor(
        private modal: NgbModal,
        private idl: IdlService,
        private org: OrgService,
        private net: NetService,
        private store: ServerStoreService,
        private evt: EventService,
        private toast: ToastService,
        private auth: AuthService,
        private perm: PermService,
        private pcrud: PcrudService) {
        super(modal);
    }

    private subscription: Subscription;

    ngOnInit() {
        console.debug('NoteDialogComponent: this',this);

        this.dataLoaded = false;
        this.clear_fields();

        this.subscription = this.onOpen$.pipe(
            switchMap(() => this.init()),
            switchMap(() => this.note_and_dialog_init()),
            catchError((error: unknown) => {
                console.error('NoteDialogComponent: error initializing',error);
                return of(null);
            }),
            tap(() => {
                console.debug('NoteDialogComponent: data loaded');
                this.dataLoaded = true;
            })
        ).subscribe();
    }

    ngOnDestroy() {
        this.subscription.unsubscribe(); // Clean up the subscription to avoid memory leaks
    }

    // Coerce initials to up to 3 uppercase letters only
    onInitialsInput(val: string) {
        const maxLength = 3;
        const cleaned = (val || '').toUpperCase().replace(/[^A-Z]/g, '').slice(0, maxLength);
        if (cleaned !== this.initials) {
            this.initials = cleaned;
        }
    }

    init(): Observable<any> {

        console.debug('NoteDialogComponent: init()');

        if (!this.patronId) {
            this.patronId = this.note?.usr() ?? this.penalty?.usr() ?? this.usr_message?.usr();
        }

        const obs1 = this.pcrud.retrieve('au', this.patronId)
            .pipe(tap(usr => this.patron = usr));

        // Load org setting for requiring initials on notes/penalties
        const obsSettings = from(
            this.org.settings([
                'ui.staff.require_initials.patron_standing_penalty'
            ])
        ).pipe(tap(settings => {
            // Single authoritative setting controls initials requirement
            this.requireInitials = Boolean(
                settings['ui.staff.require_initials.patron_standing_penalty']
            );
        }));

        const obs2 = obs1.pipe(
            switchMap(() => obsSettings),
            switchMap(_ => {
                console.debug('NoteDialogComponent: init(), first switchMap');
                // Check if penaltyTypes is already loaded and includes the current note's penalty type if applicable
                const currentPenaltyId = this.note?.standing_penalty()?.id();
                const isPenaltyLoaded = currentPenaltyId ? this.cbPenaltyTypeEntriesMap?.has(currentPenaltyId) ?? false : true;

                if (this.penaltyTypes.length > 0 && isPenaltyLoaded) {
                    // Return an Observable of the current value to skip the penaltyTypes fetch
                    console.debug('NoteDialogComponent: init(), penalty loading shortcut');
                    return of(this.penaltyTypes);
                }
                // If not loaded, fetch penaltyTypes
                return this.pcrud.search(
                    'csp', {'-or': [
                        {id: [
                            this.SILENT_NOTE,
                            this.ALERT_NOTE,
                            this.STAFF_CHR,
                            ...(this.note ? [ this.idl.pkeyValue( this.note.standing_penalty() ) ] : [])
                        ]}
                        ,{id: {'>': 100}}
                    ]}, {}, {atomic: true}
                ).pipe(tap(ptypes => {
                    console.debug('NoteDialogComponent: init(), csp search, ptypes',ptypes);
                    this.penaltyTypes = ptypes.sort((a, b) => a.label() < b.label() ? -1 : 1);
                    this.penaltyTypesMap = new Map<number, IdlObject>();
                    this.penaltyTypes.forEach(ptype => {
                        this.penaltyTypesMap.set(ptype.id(), ptype);
                    });
                    this.cbPenaltyTypeEntries = this.penaltyTypes.map(p => ({id: p.id(), label: p.label()} as ComboboxEntry));
                    this.cbPenaltyTypeEntriesMap = new Map<number, ComboboxEntry>();
                    this.cbPenaltyTypeEntries.forEach(entry => {
                        this.cbPenaltyTypeEntriesMap.set(entry.id, entry);
                    });
                    console.debug('NoteDialogComponent: penaltyTypes, combobox entries, entries map',
                        this.penaltyTypes, this.cbPenaltyTypeEntries, this.cbPenaltyTypeEntriesMap);
                }));
            }),
            switchMap(ptypes => {
                console.debug('NoteDialogComponent: init(), second switchMap');
                // After handling penaltyTypes, check if we already have some goodOrgs
                if (this.goodOrgs.length > 0) {
                    // Return an Observable of the current value to skip the permission fetch
                    return of(this.goodOrgs);
                }
                // If not set, check permissions and set goodOrgs
                return from(this.perm.hasWorkPermAt(['UPDATE_USER'], true)).pipe(
                    tap(permMap => {
                        console.debug('NoteDialogComponent: permMap',permMap);
                        if (permMap['UPDATE_USER'] && permMap['UPDATE_USER'].length > 0) {
                            this.goodOrgs = permMap['UPDATE_USER'];
                            console.debug('NoteDialogComponent: goodOrgs',this.goodOrgs);
                        }
                    })
                );
            })
        );

        return obs2;
    }

    newPenalty(): IdlObject {
        console.debug('NoteDialogComponent: newPenalty()');
        const penalty = this.idl.create('ausp');
        penalty.isnew(true);
        penalty.usr(this.patronId);
        penalty.org_unit(this.auth.user().ws_ou());
        penalty.set_date('now');
        penalty.staff(this.auth.user().id());
        return penalty;
    }

    newUsrMessage(): IdlObject {
        console.debug('NoteDialogComponent: newUsrMessage()');
        const usr_message = this.idl.create('aum');
        usr_message.isnew(true);
        return usr_message;
    }

    note_and_dialog_init(): Observable<any> {
        console.debug('NoteDialogComponent: note_and_dialog_init()');

        // note = actor.usr_message_penalty (aump)
        if (!this.note) {
            // Because aump is a view, we're just using this as a placeholder
            // for various fields that we'll pass to open-ils.actor.user.note.*
            // along with the penalty object those methods still expect.
            this.note = this.idl.create('aump');
            this.note.isnew(true);
            this.note.pub(this.pub);
            this.note.org_unit( this.auth.user().ws_ou() );
        } else {
            this.note.isnew(false);
        }

        console.debug('NoteDialogComponent: note_and_dialog_init(), this.note.ausp_id()', this.note.ausp_id());
        this.penalty = null;
        this.usr_message = null;

        const obs$ = of( this.note.ausp_id() ).pipe(

            // penalty = actor.usr_standing_penalty (ausp)
            switchMap(penalty => {
                console.debug('NoteDialogComponent: First switchMap, penalty',penalty);
                if (!penalty) {
                    console.debug('NoteDialogComponent: First switchMap, penalty is falsey');
                    return of(this.newPenalty());
                } else if (typeof penalty === 'number') {
                    console.debug('NoteDialogComponent: First switchMap, penalty is number');
                    return this.pcrud.retrieve('ausp', penalty);
                } else {
                    console.debug('NoteDialogComponent: First switchMap, penalty is wierd', typeof penalty);
                }
                return of(penalty);
            }),
            catchError((error: unknown) => {
                console.error('NoteDialogComponent: Error retrieving penalty; creating a new one.', error);
                return of(this.newPenalty());
            }),
            tap(penalty => {
                this.penalty = penalty;
                this.penalty.isnew(this.idl.toBoolean(this.penalty.isnew()));
            }),

            // standing_penalty = config.standing_penalty
            switchMap(_ => {
                let penaltyType = this.penaltyType;
                if (!penaltyType) {
                    if (this.penalty?.standing_penalty()) {
                        penaltyType = this.penalty.standing_penalty();
                    } else if (this.note?.standing_penalty()) {
                        penaltyType = this.note.standing_penalty();
                    } else {
                        penaltyType = this.penaltyTypesMap.get(this.ALERT_NOTE);
                    }
                }
                return of(penaltyType);
            }),
            switchMap(penaltyType => {
                if (typeof penaltyType === 'number' || typeof penaltyType === 'string') {
                    return of( this.penaltyTypesMap.get(penaltyType) );
                } else {
                    return of(penaltyType);
                }
            }),
            tap(penaltyType => {
                this.penaltyType = penaltyType;
                this.penaltyTypeId = penaltyType.id();
                this.penalty.standing_penalty( this.penaltyType );
            }),

            // usr_message = actor.usr_message (aum)
            switchMap(_ => {
                let usr_message;
                if (this.penalty.usr_message()) {
                    usr_message = this.penalty.usr_message();
                } else if (this.note.ausp_usr_message()) {
                    usr_message = this.note.ausp_usr_message();
                } else {
                    usr_message = this.newUsrMessage();
                }
                return of(usr_message);
            }),
            switchMap(usr_message => {
                console.debug('NoteDialogComponent: typeof usr_message', typeof usr_message);
                if (typeof usr_message === 'number' || typeof usr_message === 'string') {
                    return this.pcrud.retrieve('aum',usr_message);
                } else {
                    return of(usr_message);
                }
            }),
            catchError((error: unknown) => {
                console.error('NoteDialogComponent: Error retrieving usr_message; creating a new one.', error);
                return of(this.newUsrMessage());
            }),
            tap(usr_message => {
                this.usr_message = usr_message;
                this.usr_message.isnew( this.idl.toBoolean(this.usr_message.isnew()) );
            }),

            // UI: this.title
            switchMap(_ => {
                let title = this.defaultTitle;
                if (!title) {
                    if ( /* aump not new */ !this.idl.toBoolean( this.note?.isnew() )) {
                        title = this.note?.title();
                    } else if ( /* aum not new */ !this.idl.toBoolean( this.usr_message?.isnew() )) {
                        title = this.usr_message?.title();
                    }
                }
                return of(title);
            }),
            catchError((error: unknown) => {
                console.error('NoteDialogComponent: Error setting title; using an empty string.', error);
                return of('');
            }),
            tap(title => {
                this.title = title;
            }),

            // UI: this.message
            switchMap(_ => {
                let message = this.defaultMessage;
                if (!message) {
                    if ( /* aump not new */ !this.idl.toBoolean( this.note?.isnew() )) {
                        message = this.note.message();
                    } else if ( /* aum not new */ !this.idl.toBoolean( this.usr_message?.isnew() )) {
                        message = this.usr_message.message();
                    }
                }
                return of(message);
            }),
            catchError((error: unknown) => {
                console.error('NoteDialogComponent: Error setting message; using an empty string.', error);
                return of('');
            }),
            tap(message => {
                this.message = message;
            }),

            // UI: this.pub
            switchMap(_ => {
                let pub = this.defaultPub;
                if ( /* aump not new */ !this.idl.toBoolean( this.note.isnew() )) {
                    pub = this.note.pub();
                } else if ( /* aum not new */ !this.idl.toBoolean( this.usr_message.isnew() )) {
                    pub = this.usr_message.pub();
                }
                return of(pub);
            }),
            catchError((error: unknown) => {
                console.error('NoteDialogComponent: Error setting public flag; using false.', error);
                return of(false);
            }),
            tap(pub => {
                this.pub = this.idl.toBoolean(pub);
            }),
            tap(_ => {
                const sp_id = this.penaltyType.id();

                if (sp_id === this.ALERT_NOTE ||
                    sp_id === this.SILENT_NOTE ||
                    sp_id === this.STAFF_CHR) {

                    this.penaltyTypeFromButton = sp_id;
                }
                this.penaltyTypeFromSelect = this.cbPenaltyTypeEntriesMap.get( sp_id );

                // org_unit = actor.org_unit (aou)
                this.org_unit = this.org.get( this.penalty.org_unit() );

                console.debug('NoteDialogComponent: note_and_dialog_init(), this.note', this.note);
                console.debug('NoteDialogComponent: note_and_dialog_init(), this.note.id()', this.note.id());
                console.debug('NoteDialogComponent: note_and_dialog_init(), this.note.isnew()', this.note.isnew());
                console.debug('NoteDialogComponent: note_and_dialog_init(), this.penalty', this.penalty);
                console.debug('NoteDialogComponent: note_and_dialog_init(), this.penalty.id()', this.penalty.id());
                console.debug('NoteDialogComponent: note_and_dialog_init(), this.penalty.isnew()', this.penalty.isnew());
                console.debug('NoteDialogComponent: note_and_dialog_init(), this.usr_message', this.usr_message);
                console.debug('NoteDialogComponent: note_and_dialog_init(), this.usr_message.id()', this.usr_message.id());
                console.debug('NoteDialogComponent: note_and_dialog_init(), this.usr_message.isnew()', this.usr_message.isnew());
                console.debug('NoteDialogComponent: note_and_dialog_init(), this.penaltyType', this.penaltyType);
                console.debug('NoteDialogComponent: note_and_dialog_init(), this.org_unit', this.org_unit);
                console.debug('NoteDialogComponent: note_and_dialog_init(), this.title, this.message, this.pub',
                    this.title, this.message, this.pub);
            })
        );
        return obs$;
    }

    currentPenaltyLabel(): string {
        const key = this.idl.pkeyValue(this.note?.standing_penalty());
        if (key === undefined) {
            return $localize`:@@NoteDialogComponent.noLabelAvailable:No label available`;
        }
        return this.cbPenaltyTypeEntriesMap?.get(key)?.label
        || $localize`:@@NoteDialogComponent.labelNotFound:Label not found`;
    }

    apply() {

        const msg = {};
        if (this.idl.toBoolean( this.note.isnew() )) {
            msg['title'] = this.title;
            // Append initials if required / provided
            let composedMessage = this.message || '';
            if (this.initials) {
                // Mimic legacy format: append initials in brackets; keep minimalist implementation
                composedMessage = `${composedMessage}${composedMessage ? ' ' : ''}[${this.initials}]`;
            }
            msg['message'] = composedMessage;
            msg['pub'] = this.pub;
            msg['sending_lib'] = this.auth.user().ws_ou();
            msg['org_unit'] = this.usr_message?.sending_lib() ?? msg['sending_lib'];
        } else {
            this.usr_message.title( this.title );
            let composedMessage = this.message ? this.message : '';
            if (this.initials) {
                composedMessage = `${composedMessage}${composedMessage ? ' ' : ''}[${this.initials}]`;
            }
            this.usr_message.message( composedMessage );
            this.usr_message.pub( this.idl.toBoolean( this.pub ) );
            this.usr_message.usr( this.patronId );
            this.usr_message.sending_lib( this.auth.user().ws_ou() );
        }

        this.penalty.usr(this.patronId);
        this.penalty.org_unit( this.idl.pkeyValue( this.org_unit ) );
        this.penalty.set_date('now');
        this.penalty.staff( this.idl.pkeyValue( this.auth.user() ) );
        this.penalty.standing_penalty( this.idl.pkeyValue(this.penaltyType) );

        // console.debug('NoteDialogComponent: this.note.isnew()', this.idl.toBoolean( this.note.isnew() ));
        // console.debug('NoteDialogComponent: this.penalty.isnew()', this.idl.toBoolean( this.penalty.isnew() ));
        // console.debug('NoteDialogComponent: this.usr_message.isnew()', this.idl.toBoolean( this.usr_message.isnew() ));
        // console.debug('NoteDialogComponent: msg', msg);

        this.net.request(
            'open-ils.actor',
            this.idl.toBoolean( this.note.isnew() )
                ? 'open-ils.actor.user.note.apply'
                : 'open-ils.actor.user.note.modify',
            this.auth.token(),
            this.penalty,
            this.idl.toBoolean( this.note.isnew() )
                ? msg
                : this.usr_message
        ).subscribe(resp => {
            const e = this.evt.parse(resp);
            if (e) {
                // Keep dialog open and preserve user input
                this.errorMsg.current().then(m => this.toast.danger(m));
                return; // do not close
            } else {
                // resp == penalty ID on success
                this.successMsg.current().then(m => this.toast.success(m));
                this.clear_fields();
                this.close(resp);
            }
        });
    }

    clear_fields() {
        this.title = this.defaultTitle ?? '';
        this.message = this.defaultMessage ?? '';
        this.initials = '';
        this.pub = this.defaultPub ?? false;
        if (this.orgId) {
            this.org_unit = this.org.get(this.orgId);
        } else {
            this.org_unit = this.penalty?.org_unit();
        }
    }

    buttonClass(pType: number): string {
        return this.penaltyTypeFromButton === pType ?
            'btn-primary' : 'btn-normal';
    }

    set_penalty(id: number) {
        console.debug('NoteDialogComponent: set_penalty',id);
        if ( !(this.idl.toBoolean(this.note.pub()) && this.note.read_date()) && !this.idl.toBoolean(this.note.isdeleted()) ) {
            if (id === this.ALERT_NOTE ||
                id === this.SILENT_NOTE ||
                id === this.STAFF_CHR) {
                this.penaltyTypeFromButton = id;
            } else {
                this.penaltyTypeFromButton = null;
            }
            this.penaltyTypeFromSelect = this.cbPenaltyTypeEntriesMap.get(id);
            this.penaltyTypeId = id;
            this.penaltyType = this.penaltyTypesMap.get(id);
            if (this.penaltyType.org_depth() || this.penaltyType.org_depth() === 0) {
                this.updateOrgViaDepth(this.penaltyType.org_depth());
            }
        }
    }

    update_org(id: number) {
        if ( !(this.note.pub() && this.note.read_date()) && !this.note.isdeleted() ) {
            this.org_unit = this.org.get(id);
            console.debug('NoteDialogComponent: update_org', this.org_unit);
        } else {
            console.debug('NoteDialogComponent: org unit frozen', this.org_unit);
        }
    }

    cant_use_org(id: number) {
        return (this.note.pub() && this.note.read_date()) || !this.note.isdeleted() || this.goodOrgs.indexOf(id);
    }

    onDepthChange(depth: ComboboxEntry) {
        this.updateOrgViaDepth(depth.id);
    }

    updateOrgViaDepth(depth: number) {
        this.net.request(
            'open-ils.actor',
            'open-ils.actor.org_unit.ancestor_at_depth.retrieve',
            this.auth.token(),
            this.auth.user().ws_ou(),
            depth
        ).subscribe(
            (context_org: IdlObject) => {
                console.debug('NoteDialogComponent: ancestor_at_depth', context_org);
                this.update_org( this.idl.pkeyValue(context_org) );
            }
        );
    }

}



