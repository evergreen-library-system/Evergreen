import {Component, OnInit, Input, Renderer2} from '@angular/core';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {LocaleService} from '@eg/core/locale.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';

@Component({
  selector: 'eg-translate',
  templateUrl: 'translate.component.html'
})

export class TranslateComponent
    extends DialogComponent implements OnInit {

    idlClassDef: any;
    locales: IdlObject[];
    selectedLocale: string;
    translatedValue: string;
    existingTranslation: IdlObject;

    // These actions should update the idlObject and/or fieldName values,
    // forcing the dialog to load a new string to translate.  When set,
    // applying a translation in the dialog will leave the dialog window open
    // so the next/prev buttons can be used to fetch the next string.
    nextString: () => void;
    prevString: () => void;

    idlObj: IdlObject;
    @Input() set idlObject(o: IdlObject) {
        if (o) {
            this.idlObj = o;
            this.idlClassDef = this.idl.classes[o.classname];
            this.fetchTranslation();
        }
    }

    field: string;
    @Input() set fieldName(n: string) {
        this.field = n;
    }

    constructor(
        private modal: NgbModal, // required for passing to parent
        private renderer: Renderer2,
        private idl: IdlService,
        private toast: ToastService,
        private locale: LocaleService,
        private pcrud: PcrudService,
        private auth: AuthService) {
        super(modal);
    }

    ngOnInit() {
        // Default to the login locale
        this.selectedLocale = this.locale.currentLocaleCode();
        this.locales = [];
        this.locale.supportedLocales().subscribe(l => this.locales.push(l));

        this.onOpen$.subscribe(() => {
            const elm = this.renderer.selectRootElement('#translation-input');
            if (elm) {
                elm.focus();
                elm.select();
            }
        });
    }

    localeChanged(code: string) {
        this.fetchTranslation();
    }

    fetchTranslation() {
        const exist = this.existingTranslation;

        if (exist
            && exist.fq_field() === this.fqField()
            && exist.identity_value() === this.identValue()) {
            // Already have the current translation object.
            return;
        }

        this.translatedValue = '';
        this.existingTranslation = null;

        this.pcrud.search('i18n', {
            translation: this.selectedLocale,
            fq_field : this.fqField(),
            identity_value: this.identValue()
        }).subscribe(tr => {
            this.existingTranslation = tr;
            this.translatedValue = tr.string();
            console.debug('found existing translation ', tr);
        });
    }

    fqField(): string {
        return this.idlClassDef.classname + '.' + this.field;
    }

    identValue(): string {
        return this.idlObj[this.idlClassDef.pkey || 'id']();
    }

    translate() {
        if (!this.translatedValue) { return; }

        let entry;

        if (this.existingTranslation) {
            entry = this.existingTranslation;
            entry.string(this.translatedValue);

            this.pcrud.update(entry).toPromise().then(
                ok => {
                    if (!this.nextString) {
                        this.close(this.translatedValue);
                    }
                },
                err => console.error(err)
            );

            return;
        }

        entry = this.idl.create('i18n');
        entry.fq_field(this.fqField());
        entry.identity_value(this.identValue());
        entry.translation(this.selectedLocale);
        entry.string(this.translatedValue);

        this.pcrud.create(entry).toPromise().then(
            ok => {
                if (!this.nextString) {
                    this.close(this.translatedValue);
                }
            },
            err => console.error('Translation creation failed')
        );
    }
}


