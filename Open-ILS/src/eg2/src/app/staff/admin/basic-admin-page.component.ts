import {Component, OnInit} from '@angular/core';
import {ActivatedRoute, ParamMap} from '@angular/router';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {Observable, tap, switchMap} from 'rxjs';

/**
 * Generic IDL class editor page.
 */

@Component({
    template: `
      <ng-container *ngIf="idlClass">
      <eg-title i18n-prefix prefix="{{recordLabel || classLabel}} Administration">
      </eg-title>
      <eg-staff-banner bannerText="{{recordLabel || classLabel}}" i18n-bannerText>
      </eg-staff-banner>
      <eg-admin-page persistKeyPfx="{{persistKeyPfx}}" idlClass="{{idlClass}}"
        configLinkBasePath="{{configLinkBasePath}}"
        fieldOrder="{{fieldOrder}}"
        [fieldOptions]="fieldOptions"
        readonlyFields="{{readonlyFields}}"
        recordLabel="{{recordLabel}}"
        orgDefaultAllowed="{{orgDefaultAllowed}}"
        orgFieldsDefaultingToContextOrg="{{orgFieldsDefaultingToContextOrg}}"
        contextOrgSelectorPersistKey="{{contextOrgSelectorPersistKey}}"
        [hideClearFilters]="hideClearFilters"
        [initialFilterValues]="initialFilterValues"
        [defaultNewRecord]="defaultNewRecordIdl"
        [enableUndelete]="enableUndelete"
        [disableDelete]="disableDelete"
        [deleteConfirmation]="deleteConfirmation"
        [disableEdit]="disableEdit"
        [disableOrgFilter]="disableOrgFilter"></eg-admin-page>
      </ng-container>
    `
})

export class BasicAdminPageComponent implements OnInit {

    idlClass: string;
    classLabel: string;
    persistKeyPfx: string;
    fieldOrder = '';
    fieldOptions = {};
    contextOrgSelectorPersistKey = '';
    readonlyFields = '';
    recordLabel = '';
    orgDefaultAllowed = '';
    orgFieldsDefaultingToContextOrg = '';
    hideClearFilters: boolean;
    initialFilterValues: {[field: string]: string};
    defaultNewRecordIdl: IdlObject;
    configLinkBasePath = '/staff/admin';

    // Tell the admin page to disable and hide the automagic org unit filter
    disableOrgFilter: boolean;

    enableUndelete: boolean;
    disableDelete: boolean;
    deleteConfirmation: string;
    disableEdit: boolean;

    private getParams$: Observable<ParamMap>;
    private getRouteData$: Observable<any>;
    private getParentUrl$: Observable<any>;

    private schema: string;
    private table: string;
    private defaultNewRecord: Record<string, any>;

    constructor(
        private route: ActivatedRoute,
        private idl: IdlService
    ) {
    }

    ngOnInit() {
        console.log('BasicAdminPageComponent, this', this);
        this.getParams$ = this.route.paramMap
            .pipe(tap(params => {
                this.schema = params.get('schema');
                this.table = params.get('table');
            }));

        this.getRouteData$ = this.route.data
            .pipe(tap(routeData => {
                const data = routeData[0];

                if (data) {
                    // Schema and table can both be passed
                    // by either param or data
                    if (!this.schema) {
                        this.schema = data['schema'];
                    }
                    if (!this.table) {
                        this.table = data['table'];
                    }
                    this.disableOrgFilter = data['disableOrgFilter'];
                    this.enableUndelete = data['enableUndelete'];
                    this.disableDelete = data['disableDelete'];
                    this.deleteConfirmation = data['deleteConfirmation'];
                    this.disableEdit = data['disableEdit'];
                    this.fieldOrder = data['fieldOrder'];
                    this.fieldOptions = data['fieldOptions'];
                    this.contextOrgSelectorPersistKey = data['contextOrgSelectorPersistKey'];
                    this.readonlyFields = data['readonlyFields'];
                    this.recordLabel = data['recordLabel'];
                    this.orgDefaultAllowed = data['orgDefaultAllowed'];
                    this.orgFieldsDefaultingToContextOrg = data['orgFieldsDefaultingToContextOrg'];
                    this.hideClearFilters = data['hideClearFilters'];
                    this.initialFilterValues = data['initialFilterValues'];
                    this.defaultNewRecord = data['defaultNewRecord'];
                }

            }));

        this.getParentUrl$ = this.route.parent.url
            .pipe(tap(parentUrl => {
                // Set the prefix to "server", "local", "workstation",
                // extracted from the URL path.
                // For admin pages that use none of these, avoid setting
                // the prefix because that will cause it to double-up.
                // e.g. eg.grid.acq.acq.cancel_reason
                this.persistKeyPfx = this.route.snapshot.parent.url[0].path;
                const selfPrefixers = ['acq', 'action_trigger', 'booking'];
                if (selfPrefixers.indexOf(this.persistKeyPfx) > -1) {
                    // selfPrefixers, unlike 'server', 'local', and
                    // 'workstation', are the root of the path.
                    this.persistKeyPfx = '';
                } else {
                    this.configLinkBasePath += '/' + this.persistKeyPfx;
                }
            }));

        this.getParentUrl$.subscribe();
        this.getParams$.pipe(
            switchMap(() => this.getRouteData$)
        ).subscribe(() => {
            const fullTable = this.schema + '.' + this.table;

            Object.keys(this.idl.classes).forEach(class_ => {
                const classDef = this.idl.classes[class_];
                if (classDef.table === fullTable) {
                    this.idlClass = class_;
                    this.classLabel = classDef.label;
                }
            });

            if (!this.idlClass) {
                throw new Error('Unable to find IDL class for table ' + fullTable);
            }

            if (this.defaultNewRecord) {
                const record = this.idl.create(this.idlClass);
                // Call IDL setter for each field that has a default value
                Object.keys(this.defaultNewRecord).forEach(key => {
                    if (typeof (record[key]) === 'function') {
                        record[key].apply(record, [this.defaultNewRecord[key]]);
                    } else {
                        console.warn('Unknown field "' + key + '" in defaultNewRecord for table ' + fullTable);
                    }
                });
                this.defaultNewRecordIdl = record;
            }
        });
    }

}

