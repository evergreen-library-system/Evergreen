import {Component, Input, OnInit, DoCheck} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {IdlService} from '@eg/core/idl.service';
import {VolCopyContext} from './volcopy';
import {VolCopyService} from './volcopy.service';

@Component({
    selector: 'eg-volcopy-config',
    templateUrl: 'config.component.html'
})
export class VolCopyConfigComponent implements OnInit, DoCheck {

    @Input() context: VolCopyContext;

    defaultsCopy: any;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private idl: IdlService,
        public  volcopy: VolCopyService
    ) {}

    ngOnInit() {
        console.debug('DEFAULTS', this.volcopy.defaults);

        // Not an IDL object, but clones just the same
        this.defaultsCopy = this.idl.clone(this.volcopy.defaults);
    }

    // Watch for changes in the form and auto-save them.
    ngDoCheck() {
        const hidden = this.volcopy.defaults.hidden;
        for (const key in hidden) {
            if (hidden[key] !== this.defaultsCopy.hidden[key]) {
                this.save();
                return;
            }
        }

        const values = this.volcopy.defaults.values;
        for (const key in values) {
            if (values[key] !== this.defaultsCopy.values[key]) {
                this.save();
                return;
            }
        }
    }

    save() {
        this.volcopy.saveDefaults().then(_ =>
            this.defaultsCopy = this.idl.clone(this.volcopy.defaults)
        );
    }
}


