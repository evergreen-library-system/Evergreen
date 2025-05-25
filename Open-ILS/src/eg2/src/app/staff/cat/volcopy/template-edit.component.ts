/* eslint-disable max-len, no-prototype-builtins */
import {Component, OnInit, OnDestroy, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {BehaviorSubject, Subject, filter, take, takeUntil} from 'rxjs';
import {IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {VolCopyContext} from './volcopy';
import {VolCopyService} from './volcopy.service';
import {CopyAttrsComponent} from './copy-attrs.component';

@Component({
    selector: 'eg-volcopy-template-edit',
    templateUrl: 'template-edit.component.html',
    styles: ['::ng-deep body:has(eg-volcopy-template-edit) { background-color: var(--bs-body-bg-highlight) }']
})
export class VolCopyTemplateEditComponent implements OnInit, OnDestroy {

    private destroy$ = new Subject<void>();

    target: string = null; // id for edit, null for new
    newTemplate = true;

    context: VolCopyContext;
    private contextChange = new BehaviorSubject<VolCopyContext>(null);
    // or this.context instead of null, but subscribers will get the broadcast during init
    contextChanged = this.contextChange.asObservable();

    @ViewChild('copyAttrs', {static: false}) copyAttrs: CopyAttrsComponent;

    loading = true;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private idl: IdlService,
        private org: OrgService,
        private auth: AuthService,
        public  volcopy: VolCopyService
    ) {}

    ngOnInit() {
        // console.debug('VolCopyTemplateEditComponent, ngOnInit, this', this);

        this.initVolCopyService().then( () => {

            // console.debug('VolCopyTemplateEditComponent, VolCopyService initialized');
            this.loading = false;
            this.createStubs();

            this.route.paramMap.pipe(
                takeUntil(this.destroy$)
            ).subscribe(
                (params: ParamMap) => {
                    this.negotiateRoute(params);
                    if (this.target) {
                        this.autoApplyTargetTemplate();
                    } else {
                        // ensure no template selected in combobox
                        this.copyAttrs.saveTemplateCboxSelection(null);
                    }
                    this.contextChange.next(this.context); // tickles CopyAttrsComponent
                }
            );
        });
        this.volcopy.templatesRefreshed$.pipe(
            takeUntil(this.destroy$)
        ).subscribe(() => {
            // console.debug('VolCopyTemplateEditComponent, noticed templatesRefreshed$');
            // If we're editing an existing template, check if it still exists
            if (this.target && !this.volcopy.templates.hasOwnProperty(this.target)) {
                console.warn('Template being edited deleted elsewhere');
            }
        });
    }

    autoApplyTargetTemplate() {
        // console.debug('VolCopyTemplateEditComponent, autoApplyTargetTemplate, setting up subscription');
        if (this.copyAttrs) {
            this.copyAttrs.initialized$.pipe(
                filter(initialized => initialized), // shorthand for filter on true
                take(1)
            ).subscribe(() => {
                // console.debug('VolCopyTemplateEditComponent, calling copyAttrs.applyTemplate()');
                this.copyAttrs.applyTemplate( { id: this.target, label: this.target } ); // my original quick and dirty idea I should have tried first
            });
        } else {
            console.error('VolCopyTemplateEditComponent, autoApplyTargetTemplate, copyAttrs not ready');
        }
    }

    initVolCopyService(): Promise<any> {
        // console.debug('VolCopyTemplateEditComponent, initVolCopyService');
        if (this.volcopy.currentContext) {
            // Avoid clobbering the context on route change.
            this.context = this.volcopy.currentContext;
            // console.debug('VolCopyTemplateEditComponent, reusing currentContext');
        } else {
            this.context = new VolCopyContext();
            this.context.org = this.org; // inject;
            this.context.idl = this.idl; // inject;
            // console.debug('VolCopyTemplateEditComponent, new context');
        }

        if (this.volcopy.currentContext) {
            return Promise.resolve();
        } else {
            // Avoid refetching the data during route changes.
            this.volcopy.currentContext = this.context;
            return this.volcopy.load(); // returns a promise, not an observable
        }
    }

    negotiateRoute(params: ParamMap) {
        // console.debug('VolCopyTemplateEditComponent, negotiateRoute', params);
        const encodedTarget = params.get('target');
        this.target = encodedTarget ? decodeURIComponent(atob(encodedTarget)) : null;

        if (this.target) {
            this.newTemplate = false;
        }

        if (this.target) {
            // console.debug('VolCopyTemplateEditComponent, target', this.target);
            // console.debug('VolCopyTemplateEditComponent, templates we are checking against', this.volcopy.templates);
            if (!this.volcopy.templates.hasOwnProperty(this.target)) {
                console.warn('VolCopyTemplateEditComponent, template not found, using as default name for a new one');
            } else {
                console.debug('VolCopyTemplateEditComponent, found template', this.target);
            }
        } else {
            console.debug('VolCopyTemplateEditComponent, new template');
        }
    }

    createStubs() {
        // console.debug('VolCopyTemplateEditComponent, creating stubs');
        const vol = this.volcopy.createStubVol( -1, this.auth.user().ws_ou() );
        this.idl.classes['acn'].fields.forEach( field => {
            if (field.name !== 'id' && field.name !== 'owning_lib') {
                vol[field.name](null);
            }
        });
        const item = this.volcopy.createStubCopy(vol);
        this.idl.classes['acp'].fields.forEach( field => {
            if (field.name !== 'id' && field.name !== 'call_number' && field.name !== 'copy_alerts' && field.name !== 'tags' && field.name !== 'notes') {
                item[field.name](null);
            }
        });
        // item.call_number().label('');
        this.context.findOrCreateCopyNode( item );
    }

    attrsCanSaveChange($event) {
        console.debug('VolCopyTemplateEditComponent, attrsCanSaveChange', $event);
    }

    ngOnDestroy() {
        this.destroy$.next();
        this.destroy$.complete();
    }
}


