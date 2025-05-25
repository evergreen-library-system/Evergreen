import {Component, OnInit, Input, Renderer2} from '@angular/core';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {NetRequest, NetService} from '@eg/core/net.service';

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

    requestToEscalate: NetRequest;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private renderer: Renderer2,
        private toast: ToastService,
        private net: NetService,
        private auth: AuthService) {
        super(modal);
    }

    ngOnInit() {
        // Focus the username any time the dialog is opened.
        this.onOpen$.subscribe(
            val => this.renderer.selectRootElement('#username').focus()
        );
    }

    my_close() {
        if (this.requestToEscalate) {
            this.requestToEscalate.observer.error('Operation canceled');
            delete this.requestToEscalate;
        }
        this.close(); // dialog close
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
                        if (this.requestToEscalate) {
                            // Allow a breath for the dialog to clean up.
                            setTimeout(() => this.sendEscalatedRequest());
                        }
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

    escalateRequest(req: NetRequest) {
        this.requestToEscalate = req;
        this.open({});
    }

    // Resend a net request using the credentials just created
    // via operator change.
    sendEscalatedRequest() {
        const sourceReq = this.requestToEscalate;
        delete this.requestToEscalate;

        console.debug('Op-Change escalating request', sourceReq);

        // Clone the source request, modifying the params to
        // use the op-change'd authtoken
        const req = new NetRequest(
            sourceReq.service,
            sourceReq.method,
            [this.auth.token()].concat(sourceReq.params.splice(1))
        );

        // Relay responses received for our escalated request to
        // the caller via the original request observer.
        this.net.requestCompiled(req)
            .subscribe({
                next: res => sourceReq.observer.next(res),
                error: (err: unknown) => sourceReq.observer.error(err),
                complete: ()  => sourceReq.observer.complete()
            }).add(() => this.auth.undoOpChange());
    }
}


