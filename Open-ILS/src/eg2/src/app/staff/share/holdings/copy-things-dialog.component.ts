/* eslint-disable max-len */
import { Component, Input, ViewChild, TemplateRef, Optional, Inject, InjectionToken } from '@angular/core';
import { lastValueFrom, Observable, throwError, from, tap, defaultIfEmpty, switchMap } from 'rxjs';
import { IdlService, IdlObject } from '@eg/core/idl.service';
import { ToastService } from '@eg/share/toast/toast.service';
import { AuthService } from '@eg/core/auth.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { OrgService } from '@eg/core/org.service';
import { StringComponent } from '@eg/share/string/string.component';
import { DialogComponent } from '@eg/share/dialog/dialog.component';
import { NgbModal, NgbModalOptions } from '@ng-bootstrap/ng-bootstrap';

/**
 * Base interface for methods we expect on all thing objects
 */
export interface IThingObject extends IdlObject {
    id(val?: number): number;
    isnew(val?: boolean): boolean;
    ischanged(val?: boolean): boolean;
    isdeleted(val?: boolean): boolean;
}

/**
 * Interface for tracking thing changes
 * Each implementation will extend this with its specific types
 */
export interface IThingChanges<T extends IThingObject> {
    newThings: T[];
    changedThings: T[];
    deletedThings?: T[];
}

/**
 * Configuration options for thing types
 */
export interface IThingConfig<T extends IThingObject> {
    idlClass: string;
    thingField: string;  // Field name on copy object (e.g., 'copy_alerts')
    fleshDepth?: number;
    fleshFields?: {[key: string]: any};
    defaultValues?: {[key: string]: any};
}

// voodoo; thanks prod build
export const THINGDATA_CONFIG = new InjectionToken<IThingConfig<any>>('THINGDATA_CONFIG');

/**
 * Base component for managing copy things
 * T = The thing type (Alert, Note, Tag)
 * C = The changes tracking type
 */
@Component({
    templateUrl: './copy-things-dialog.component.html'
})
export abstract class CopyThingsDialogComponent<
    T extends IThingObject,
    C extends IThingChanges<T>
> extends DialogComponent {

    @Input() copyIds: number[] = [];
    @Input() copies: IdlObject[] = []; // Pre-loaded copies from parent
    @Input() inPlaceCreateMode = false;
    @Input() templateOnlyMode = false;

    // Change tracking collections - can be pre-populated by parent
    @Input() newThings: T[] = [];
    @Input() changedThings: T[] = [];
    @Input() deletedThings: T[] = [];

    protected copy: IdlObject; // Current copy in single mode
    autoId = -1;

    // Template support properties
    protected abstract thingType: string;
    protected abstract successMessage: string;
    protected abstract errorMessage: string;
    protected abstract batchWarningMessage: string;

    @ViewChild('dialogContent') dialogContent: TemplateRef<any>;
    @ViewChild('existingThings') existingThings: TemplateRef<any>;
    @ViewChild('pendingThings') pendingThings: TemplateRef<any>;
    @ViewChild('newThingForm') newThingForm: TemplateRef<any>;

    @ViewChild('successMsg', { static: true })
    protected successMsg: StringComponent;

    @ViewChild('errorMsg', { static: true })
    protected errorMsg: StringComponent;

    // protected config: IThingConfig<T>;

    constructor(
        protected modal: NgbModal,
        protected toast: ToastService,
        protected idl: IdlService,
        protected pcrud: PcrudService,
        protected org: OrgService,
        protected auth: AuthService,
        @Optional() @Inject(THINGDATA_CONFIG) protected config?: IThingConfig<T>
    ) {
        super(modal);
        this.config = config;
    }

    /**
     * Initialize component state
     * Override in child classes for additional initialization
     */
    protected async initialize(): Promise<void> {
        if (this.templateOnlyMode) {return;}

        // defense: make sure both .copyIds and .copies contain things
        // console.debug(`CopyThingsDialog(${this.thingType}): starting with this.copies, this.copyIds`, this.copies, this.copyIds);
        if (!this.hasCopy()) {
            // console.debug(`CopyThingsDialog(${this.thingType}): setting this.copies = []`);
            this.copies = [];
        }
        if (!this.copyIds) {
            // console.debug(`CopyThingsDialog(${this.thingType}): setting this.copyIds = []`);
            this.copyIds = [];
        }

        if (this.hasCopy() && !this.copyIds.length) {
            this.copyIds = this.copies.map(c => c.id());
            // console.debug(`CopyThingsDialog(${this.thingType}): mapped this.copies to this.copyIds`, this.copyIds);
        }
        if (this.copyIds.length && !this.hasCopy()) {
            await this.fetchCopies();
            // console.debug(`CopyThingsDialog(${this.thingType}): fetched copies for this.copies`, this.copies);
        }
        if (!this.hasCopy()) {
            // if no copies at this point, it's an error
            // console.error('No copies to work with. this.copies, this.copyIds', this.copies, this.copyIds);
        }

        await this.initializeCopies();

        if (this.copies.length >= 1) {
            this.copy = this.copies[0];
        }

        return;
    }

    /**
     * Opens the dialog with appropriate setup
     */
    open(args: NgbModalOptions): Observable<C> {
        if (this.copyIds.length === 0 && !this.copies.length) {
            console.error(`CopyThingsDialog(${this.thingType}): No copies provided`);
            return throwError('No copies provided');
        }

        const obs = from(this.initialize());
        return obs.pipe(switchMap(() => super.open(args)));
    }

    /**
     * Fetch copies from database when not pre-loaded
     */
    protected async fetchCopies(): Promise<void> {
        if (!this.copyIds && !this.copyIds.length) {
            console.error(`CopyThingsDialog(${this.thingType}): no this.copyIds for fetchCopies`);
        }
        const ids = this.copyIds.filter(id => id > 0);
        if (ids.length === 0) {
            console.error(`CopyThingsDialog(${this.thingType}): no copies fetched for this.copies. this.copyids =`, this.copyIds);
            return;
        }

        const searchOpts: any = {};
        if (this.config.fleshFields) {
            searchOpts.flesh = this.config.fleshDepth;
            searchOpts.flesh_fields = this.config.fleshFields;
        }
        const reqOpts: any = { atomic: true };

        const result = await this.pcrud.search('acp',
            { id: ids },
            searchOpts,
            reqOpts
        ).toPromise();

        if (typeof result.length === 'undefined') {
            this.copies = [ result ]; // single
        } else {
            this.copies = result; // multiple
        }

        if (!this.copies && !this.copies.length) {
            console.error(`CopyThingsDialog(${this.thingType}): pcrud did not find copies with ids from this.copyIds`, this.copyIds);
        }
    }

    /**
     * Initialize thing arrays on copies if needed
     */
    protected async initializeCopies(): Promise<void> {
        /*
        console.debug(`CopyThingsDialog(${this.thingType}): initializeCopies(), this.copies,
            this.copyIds`, this.copies, this.copyIds);
        /** */
        if (!this.copies) {
            console.error(`CopyThingsDialog(${this.thingType}): initializeCopies(), 
                nothing in this.copies. this.copies, this.copyIds`, this.copies, this.copyIds);
            return;
        }
        this.copies.forEach(copy => {
            const field = this.config.thingField;
            // Ensure we have an array
            if (!Array.isArray(copy[field]())) {
                copy[field]([]);
            }
        });

        /*
        console.debug(`CopyThingsDialog(${this.thingType}): initializeCopies();
            this.inPlaceCreateMode, this.inBatch()`, this.inPlaceCreateMode, this.inBatch());
        /** */

        // Re-fetch thing data, even if not needed, for simplicty and single
        // source of truth for pre-filtering ah, but not single source of truth,
        // with our fetchCopies elsewhere fleshing these things. so if needed
        // for performance, maybe wrap this back into an !inPlacecopies test
        // This is also mucking with our pending changes when the dialog is
        // reinvoked before save; hrmm. clones/new-instances vs references
        /*
        console.debug(`CopyThingsDialog(${this.thingType}): initializeCopies();
            calling this.getThings`);
        /** */
        await this.getThings();

        // Process batch things if needed
        if (this.inBatch()) {
            /*
            console.debug(`CopyThingsDialog(${this.thingType}): initializeCopies();
                calling this.processCommonThings`);
            /** */
            await this.processCommonThings();
        }
    }

    /**
     * Create a new thing
     */
    protected createNewThing(): T {
        const thing = this.idl.create(this.config.idlClass) as T;
        thing.id(this.autoId--);
        thing.isnew(true);

        if (this.config.defaultValues) {
            Object.entries(this.config.defaultValues).forEach(([key, value]) => {
                thing[key](value);
            });
        }

        return thing;
    }

    /**
     * Fetch things for the copies
     * Must be implemented by child classes
     */
    protected abstract getThings(): Promise<void>;

    /**
     * Process common things for batch operations
     * Override in child classes as needed
     */
    protected abstract processCommonThings(): Promise<void>;

    /**
     * Match things for batch operations
     * Must be implemented by child classes
     */
    protected abstract compositeMatch(a: T, b: T): boolean;

    /**
     * Validate current state
     * Override in child classes as needed
     */
    protected validate(): boolean {
        return true;
    }

    /**
     * Apply changes to copies
     * Must be implemented by child classes
     */
    protected abstract applyChanges(): Promise<void>;

    /**
     * Utility methods
     */
    protected hasCopy(): boolean {
        return this.copies && this.copies.length > 0;
    }

    protected inBatch(): boolean {
        return  this.copies &&this.copies.length > 1;
    }

    /**
     * Clear pending changes
     */
    clearPending(): void {
        this.newThings = [];
        this.changedThings = [];
        this.deletedThings = [];
    }

    /**
     * Toast message handling
     */
    protected async showSuccess(): Promise<void> {
        const msg = await this.successMsg.current();
        this.toast.success(msg || this.successMessage);
    }

    protected async showError(err: any): Promise<void> {
        const msg = await this.errorMsg.current();
        this.toast.danger(msg || this.errorMessage);
        console.error(`Error in ${this.thingType} operation:`, err);
    }

    /**
     * Package changes for return to caller
     */
    protected gatherChanges(): C {
        const changes = {
            newThings: this.newThings,
            changedThings: this.changedThings,
            deletedThings: this.deletedThings
        } as C;
        // console.debug('gatherChanges', changes);
        return changes;
    }

    /**
     * Apply changes to copies and mark as changed
     */
    protected markCopiesChanged(): void {
        this.copies.forEach(copy => copy.ischanged(true));
    }


    /**
     * Remove in-memory things and flag in-db things for deletion, or act as a toggle
     */
    removeThing(things: T[]): void {
        /*
        console.debug(`CopyThingsDialog(${this.thingType}): removeThing: things`,
            this.idl.clone(things));
        console.debug(`CopyThingsDialog(${this.thingType}): removeThing:
            incoming this.newThings`, this.newThings.length, this.idl.clone(this.newThings));
        console.debug(`CopyThingsDialog(${this.thingType}): removeThing:
            incoming this.changedThings`, this.changedThings.length, this.idl.clone(this.changedThings));
        console.debug(`CopyThingsDialog(${this.thingType}): removeThing:
            incoming this.deletedThings`, this.deletedThings.length, this.idl.clone(this.deletedThings));
        /** */
        things.forEach(thing => {
            /*
            console.debug(`CopyThingsDialog(${this.thingType}): removeThing:
                considering thing with id, isnew, ischanged, isdeleted`, this.idl.clone(thing),
                thing?.id(), thing?.isnew(), thing?.ischanged(), thing?.isdeleted());
            /** */
            if (thing === undefined) {
                console.error('removeThing: What? Why? How? ^');
            }

            // considering this.newThings
            if (this.newThings.find(t => t.id() === thing.id())) {
                // console.debug('removeThing: thing to be removed found in this.newThings');
                if (thing.id() < 0) {
                    if (thing?.isnew() ?? false) {
                        console.debug('removeThing: isnew() is true, removing from this.newThings. removing');
                    } else {
                        console.error('removeThing: isnew() is false, yet found in this.newThings. removing');
                    }
                } else {
                    console.error('removeThing: id() not negative, yet found in this.newThings. removing');
                }
                this.newThings = this.newThings.filter(t => t.id() !== thing.id());
            } else {
                console.debug('removeThing: thing to be removed not found in this.newThings');

                if (thing.id() < 0) {
                    console.error('removeThing: thing has isnew() = true, so why not in newThings?');
                }

                // considering this.changedThings
                if (this.changedThings.find(t => t.id() === thing.id())) {
                    console.warn('removeThing: thing to be removed found in this.changedThings. Removing from this.changedThings.');
                    this.changedThings = this.changedThings.filter(t => t.id() !== thing.id());
                }

                // considering this.deletedThings
                if (this.deletedThings.find(t => t.id() === thing.id())) {
                    console.debug('removeThing: thing to be removed already found in this.deletedThings');
                    if (thing?.isdeleted() ?? false) {
                        console.log('removeThing: undeleting thing and removing from this.deletedThings');
                        this.deletedThings = this.deletedThings.filter(t => t.id() !== thing.id());
                        thing.isdeleted(false);
                        if (thing?.isnew() ?? false) {
                            console.error('removeThing: undeleted thing has isnew = true, putting into newThings');
                            this.newThings.push(thing);
                        } else if (thing?.ischanged() ?? false) {
                            console.warn('removeThing: undeleted thing has ischanged = true, putting into changedThings');
                            this.changedThings.push(thing);
                        }
                    } else {
                        console.error('removeThing: thing to be removed has isdeleted = false; why is it already in deletedThings? setting isdeleted(true)');
                        thing.isdeleted(true);
                    }
                } else {
                    console.debug('removeThing: thing to be removed not already found in this.deletedThings');
                    if (thing?.isdeleted() ?? false) {
                        console.error('removeThing: thing to be removed has isdeleted = true. Why not already in deletedThings? Will "undelete"');
                    } else {
                        console.log('removeThing: setting thing to isdeleted(true) and putting into deletedThings');
                        thing.isdeleted(true);
                        this.deletedThings.push(thing);
                    }
                }
            }
        });
        // console.debug(`CopyThingsDialog(${this.thingType}): removeThing: outgoing this.newThings`, this.newThings.length, this.newThings);
        // console.debug(`CopyThingsDialog(${this.thingType}): removeThing: outgoing this.changedThings`, this.changedThings.length, this.changedThings);
        // console.debug(`CopyThingsDialog(${this.thingType}): removeThing: outgoing this.deletedThings`, this.deletedThings.length, this.deletedThings);
    }

    /**
     * Save changes directly to database
     * Only called when not in inPlaceCreateMode
     */
    protected async saveChanges(): Promise<boolean> {
        const pendingDeletions = [];
        const pendingUpdates = [];
        this.copies.forEach( c=> {
            const things = c[this.config.thingField]();
            things.forEach( t=> {
                if (t.isdeleted()) {
                    pendingDeletions.push(t);
                } else if (t.isnew() || t.ischanged()) {
                    pendingUpdates.push(t);
                }
            });
        });
        // console.debug(`CopyThingsDialog(${this.thingType}), saveChanges, pendingDeletions, pendingUpdates`, pendingDeletions, pendingUpdates);

        // Validate required fields
        for (const thing of pendingUpdates) {
            if (!thing.classname || !this.idl.classes[thing.classname]) {
                throw new Error(`Hope not to ever see this: ${thing.classname}`);
            }

            const requiredFields = this.idl.classes[thing.classname].fields
                .filter(field => field.required)
                .map(field => field.name);

            for (const fieldName of requiredFields) {
                if (thing[fieldName]() === null || thing[fieldName]() === undefined) {
                    throw new Error(
                        `Required field "${fieldName}" is not set for changed ${thing.classname} object`
                    );
                }
            }
        }

        let resp = false;
        // Handle deletions first if supported
        if (pendingDeletions.length > 0) {
            try {
                resp = await lastValueFrom(
                    this.pcrud.remove(pendingDeletions)
                        .pipe(
                            tap({
                                next: (val) => console.debug(`CopyThingsDialog(${this.thingType}), saveChanges, pcrud.remove next`, val),
                                error: (err: unknown) => console.error(`CopyThingsDialog(${this.thingType}), saveChanges, pcrud.remove err`, err),
                                complete: () => console.debug(`CopyThingsDialog(${this.thingType}), saveChanges, pcrud.remove completed`)
                            }),
                            defaultIfEmpty(null)
                        )
                );
                if (!resp) {
                    // console.debug(`CopyThingsDialog(${this.thingType}), saveChanges, pcrud.remove returned null, early abort`);
                    return false;
                }
            } catch(E) {
                console.error(`CopyThingsDialog(${this.thingType}), saveChanges, pcrud.remove error`, E);
                return false;
            }
        }

        try {
            if (pendingUpdates.length > 0) {
                const resp2 = await lastValueFrom(
                    this.pcrud.autoApply(pendingUpdates)
                        .pipe(
                            tap({
                                next: (val) => console.debug(`CopyThingsDialog(${this.thingType}), saveChanges, pcrud.autoApply next`, val),
                                error: (err: unknown) => console.error(`CopyThingsDialog(${this.thingType}), saveChanges, pcrud.autoApply err`, err),
                                complete: () => console.debug(`CopyThingsDialog(${this.thingType}), saveChanges, pcrud.autoApply completed`)
                            }),
                            defaultIfEmpty(null)
                        )
                );
                // console.debug(`CopyThingsDialog(${this.thingType}), saveChanges, pcrud.autoApply response`, resp2);
                if (resp2) {
                    this.clearPending();
                }
                // console.debug(`CopyThingsDialog(${this.thingType}), saveChanges(), resp2`, resp2);
                return resp2 ? true : false;
            } else {
                // console.debug(`CopyThingsDialog(${this.thingType}), saveChanges(), resp`, resp);
                return resp ? true : false;
            }
        } catch(E) {
            console.error(`CopyThingsDialog(${this.thingType}), saveChanges, pcrud.autoApply error`, E);
            return false;
        }
    }

    /**
     * Template context helper
     */
    protected getTemplateContext() {
        return {
            $implicit: this,
            copies: this.copies,
            copyIds: this.copyIds,
            inBatch: () => this.inBatch(),
            thingType: this.thingType
        };
    }
}
