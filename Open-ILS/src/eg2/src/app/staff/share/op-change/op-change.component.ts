import {Component, OnInit, Input, Renderer2} from '@angular/core';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';

@Component({
  selector: 'eg-op-change',
  templateUrl: 'op-change.component.html'
})

export class OpChangeComponent
    extends DialogComponent implements OnInit {

    @Input() username: string;
    @Input() password: string;
    @Input() loginType = 'temp';

    @Input() successMessage: string;
    @Input() failMessage: string;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private renderer: Renderer2,
        private toast: ToastService,
        private auth: AuthService) {
        super(modal);
    }

    ngOnInit() {

        // Focus the username any time the dialog is opened.
        this.onOpen$.subscribe(
            val => this.renderer.selectRootElement('#username').focus()
        );
    }

    login(): Promise<any> {
        if (!(this.username && this.password)) {
            return Promise.reject('Missing Params');
        }

        return this.auth.login(
            {   username    : this.username,
                password    : this.password,
                workstation : this.auth.workstation(),
                type        : this.loginType
            },  true        // isOpChange
        ).then(
            ok => {
                this.password = '';
                this.username = '';

                // Fetch the user object
                this.auth.testAuthToken().then(
                    ok2 => {
                        this.close();
                        this.toast.success(this.successMessage);
                    }
                );
            },
            notOk => {
                this.password = '';
                this.toast.danger(this.failMessage);
            }
        );
    }

    restore(): Promise<any> {
        return this.auth.undoOpChange().then(
            ok => this.toast.success(this.successMessage),
            err => this.toast.danger(this.failMessage)
        );
    }
}


