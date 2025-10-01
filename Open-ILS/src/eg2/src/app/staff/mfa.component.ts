import {Component, OnInit} from '@angular/core';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {Location} from '@angular/common';
import {Router, ActivatedRoute} from '@angular/router';
import {AuthService, AuthWsState} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {OfflineService} from '@eg/staff/share/offline.service';
import {StoreService} from '@eg/core/store.service';
import {OrgService} from '@eg/core/org.service';
import * as moment from 'moment-timezone';

@Component({
    styleUrls: ['./mfa.component.css'],
    templateUrl : './mfa.component.html'
})

export class StaffMFAComponent implements OnInit {

    active_factor = 'CONFIG';
    method_suffix = '';
    totp_uri = '';
    totp_uri_parts = {};
    provisional = false;
    required_for_token = true;
    allowed_for_token = true;
    has_config = false;
    loading = true;
    userId: number;
    routeTo: string;
    hostname: string;
    recent_activity: IdlObject;

    webauthn_RPs: string[];
    available_factors: string[];
    configured_factors: string[];
    configured_factor_maps = {};
    factor_details = {};
    factor_flags = {};
    sms_carriers = [];

    sms_otp_sent = false;
    email_otp_sent = false;
    webauthn_remove_init: any = null;

    email_otp_addr = '';
    sms_otp_phone = '';
    sms_otp_carrier: number;

    constructor(
      private net: NetService,
      private router: Router,
      private route: ActivatedRoute,
      private ngLocation: Location,
      private auth: AuthService,
      private org: OrgService,
      private store: StoreService,
      private offline: OfflineService
    ) {
        this.configured_factors = [];
        this.available_factors = [];
        this.hostname = window.location.hostname;
        if (this.auth.provisional()) {
            this.provisional = true;
            this.method_suffix = '.provisional';
        }

        this.net.request(
            'open-ils.auth_mfa',
            'open-ils.auth_mfa.token_factors.available' + this.method_suffix,
            this.auth.token()
        ).toPromise().then( available_factors => {
            this.available_factors = available_factors || [];

            if (this.available_factors.includes('sms')) {
                this.net.request(
                    'open-ils.auth_mfa',
                    'open-ils.auth_mfa.sms_carriers' + this.method_suffix,
                    this.auth.token()
                ).toPromise().then(sms_carriers => this.sms_carriers = sms_carriers);
            }

            this.net.request(
                'open-ils.auth_mfa',
                'open-ils.auth_mfa.factor_details',
                this.available_factors
            ).toPromise().then( factor_details => {
                this.factor_details = factor_details.factors;
                this.factor_flags = factor_details.flags;
                this.net.request(
                    'open-ils.auth_mfa',
                    'open-ils.auth_mfa.allowed_for_token' + this.method_suffix,
                    this.auth.token()
                ).toPromise().then(allowed => {
                    this.allowed_for_token = !!Number(allowed);
                    this.net.request(
                        'open-ils.auth_mfa',
                        'open-ils.auth_mfa.required_for_token' + this.method_suffix,
                        this.auth.token()
                    ).toPromise().then(required => {
                        this.required_for_token = !!Number(required);
                        this.refreshConfiguredFactors().then(() => {
                            if (this.provisional && !this.required_for_token && this.configured_factors.length !== 0) {
                                this.upgradeSession();
                            } else {
                                this.loading = false;
                            }

                            if (this.configured_factors.length) {
                                this.active_factor = this.configured_factors[0];
                            }
                        });
                    });
                });
            });
        });
    }

    showFactor (factor): boolean {
        // No factors configured, but we MUST have one -- show them all to configure
        if (this.factorsConfiguredHere().length === 0) {
            return this.available_factors.includes(factor);
        }

        return this.available_factors.includes(factor) &&
            (this.provisional ? this.factorsConfiguredHere().includes(factor) : true);
    }

    factorsConfiguredHere (): string[] {
        return this.configured_factors.filter(f => (f === 'webauthn') ? this.hostnameCoveredByRP() : true);
    }

    refreshConfiguredFactors (): Promise<any> {
        return this.net.request(
            'open-ils.auth_mfa',
            'open-ils.auth_mfa.token_factors.configured.detail' + this.method_suffix,
            this.auth.token()
        ).toPromise().then(configured_factors => {
            configured_factors.factors.forEach(f => this.configured_factor_maps[f.factor()] = f);
            // Instead of just grabbing the key from the configured_factor_map object, we do
            // this in order to maintain the config-time ascending order supplied by the server.
            if (configured_factors.webauthn) {
                this.webauthn_RPs = configured_factors.webauthn.RPs;
            } else {
                this.webauthn_RPs = [];
            }
            this.configured_factors = configured_factors.factors.map(f => f.factor());
            this.recent_activity = configured_factors.activity;
        });
    }

    hostnameCoveredByRP(): boolean {
        return !!this.webauthn_RPs?.find(r => new RegExp(r + '$').test(this.hostname));
    }

    ngOnInit() {
        this.routeTo = this.route.snapshot.queryParamMap.get('routeTo');

        if (this.routeTo) {
            if (this.routeTo.match(/^[a-z]+:\/\//i)) {
                console.warn(
                    'routeTo must contain only path information: ', this.routeTo);
                this.routeTo = null;
            } else {
                // Remove /eg2/:locale/ however many times it's been prepended, so it's added back only once in prepareExternalUrl()
                // eslint-disable-next-line quotes
                this.routeTo = this.routeTo.replace(/^(\/eg2\/([a-z]{2}-[A-Z]{2}))+/, "");
            }
        }
    }

    parse_totp_uri_parts(): any {
        const path = this.totp_uri.split('?')[0];

        // eslint-disable-next-line no-magic-numbers
        const who = path.split('/')[3]; // 3 isn't a magic number here, any more than 0 above, or 1 below. whatevs.

        this.totp_uri_parts = {
            type         : path.split('/')[2],
            issuer_label : decodeURIComponent(who.split(':')[0]),
            account      : decodeURIComponent(who.split(':')[1]),
        };

        this.totp_uri // split up the cgi params
            .split('?')[1]
            .split('&')
            .forEach( p => {
                const x = p.split('=');
                this.totp_uri_parts[x[0]] = decodeURIComponent(x[1]);
            });
    }

    initFactorSetup(factor: string, data?: any) {
        this.net.request(
            'open-ils.auth_mfa',
            'open-ils.auth_mfa.token_factor.configure.init' + this.method_suffix,
            this.auth.token(), factor, data
        ).toPromise().then( res => {
            if (res) {
                if (factor === 'totp') {
                    this.totp_uri = res.uri;
                    /* Angular's DefaultUrlSerializer is crap and returns an empty UrlTree for otpauth URIs */
                    // const parser = new DefaultUrlSerializer();
                    // this.parsed_totp_uri = parser.parse(this.totp_uri);
                    this.parse_totp_uri_parts();
                } else if (factor === 'email') {
                    this.email_otp_addr = res.email;
                    this.email_otp_sent = !!res.sent;
                } else if (factor === 'sms') {
                    this.sms_otp_phone = res.email;
                    this.sms_otp_carrier = Number(res.carrier);
                    this.sms_otp_sent = !!res.sent;
                } else if (factor === 'webauthn') {

                    if (!isNaN(parseInt(res.timeout, 10))) {
                        res.timeout = parseInt(res.timeout, 10);
                    }

                    if (!isNaN(parseInt(res.authenticatorSelection.requireResidentKey, 10))) {
                        res.authenticatorSelection.requireResidentKey =
                            !!parseInt(res.authenticatorSelection.requireResidentKey, 10);
                    }


                    const credOptions = {
                        attestation: res.attestation,
                        authenticatorSelection: {...res.authenticatorSelection},
                        challenge: Uint8Array.from(atob(res.challenge_b64), c=>c.charCodeAt(0)),
                        pubKeyCredParams: [...res.pubKeyCredParams],
                        excludeCredentials: [],
                        rp: {...res.rp},
                        timeout: res.timeout,
                        user: {...res.user},
                    };
                    credOptions.user.id = Uint8Array.from(atob(credOptions.user.id), c=>c.charCodeAt(0));

                    if (res.excludeCredentials_b64?.length) {
                        credOptions.excludeCredentials = res.excludeCredentials_b64.map(e => Uint8Array.from(atob(e), c=>c.charCodeAt(0)));
                    } else {
                        delete credOptions.excludeCredentials;
                    }

                    navigator.credentials.create({publicKey:credOptions}).then(
                        (cred: any) => {
                            const response = cred.response;
                            const cred_copy = {
                                id: cred.id,
                                attestationObject_b64: btoa(String.fromCharCode(...new Uint8Array(response.attestationObject))),
                                clientDataJSON_b64: btoa(String.fromCharCode(...new Uint8Array(response.clientDataJSON))),
                                authenticatorData_b64: btoa(String.fromCharCode(...new Uint8Array(response.getAuthenticatorData()))),
                                publicKey_b64: btoa(String.fromCharCode(...new Uint8Array(response.getPublicKey()))),
                                publicKeyAlgorithm: response.getPublicKeyAlgorithm(),
                                transports: response.getTransports()
                            };

                            return this.completeFactorSetup(factor, cred_copy);
                        },
                        (e)   => {
                            console.error('webauthn cred creation error:', e);
                            alert($localize`"WebAuthn credential creation failed`); /* error */
                        }
                    );
                }
            }

            this.refreshConfiguredFactors();
        });
    }

    completeFactorSetup(factor: string, data?: any) {
        this.net.request(
            'open-ils.auth_mfa',
            'open-ils.auth_mfa.token_factor.configure.complete' + this.method_suffix,
            this.auth.token(), factor, data
        ).toPromise().then( res => {
            if (res) {
                if (factor === 'totp') {
                    this.totp_uri = '';
                    this.totp_uri_parts = {};
                } else if (factor === 'email') {
                    this.email_otp_addr = '';
                    this.email_otp_sent = false;
                } else if (factor === 'sms') {
                    this.sms_otp_phone = '';
                    this.sms_otp_carrier = null;
                    this.sms_otp_sent = false;
                }
            }

            this.refreshConfiguredFactors();
        });
    }

    removeFactor(factor: string, data?: any, finalRemoval?: boolean) {
        return this.net.request(
            'open-ils.auth_mfa',
            'open-ils.auth_mfa.token_factor.configure.remove' + this.method_suffix,
            this.auth.token(), factor, data
        ).toPromise().then( res => {
            if (res) {
                if (factor === 'totp') {
                    this.totp_uri = '';
                    this.totp_uri_parts = {};
                } else if (factor === 'email') {
                    this.email_otp_sent = false;
                } else if (factor === 'sms') {
                    this.sms_otp_sent = false;
                } else if (!finalRemoval && factor === 'webauthn') {
                    if (!Number(res.success)) {
                        console.error('WebAuthn validation failed:', res);
                        alert($localize`WebAuthn validation failed`);
                        return;
                    } else if (Number(res.success) > 0) {
                        return this.completeFactor(factor);
                    }

                    if (!isNaN(parseInt(res.timeout, 10))) {
                        res.timeout = parseInt(res.timeout, 10);
                    }

                    const credOptions = {
                        challenge: Uint8Array.from(atob(res.challenge_b64), c=>c.charCodeAt(0)),
                        timeout: res.timeout,
                        rpId: res.rpId,
                        allowCredentials: [],
                        userVerification: res.userVerification
                    };

                    if (res.allowCredentials_b64?.length) {
                        credOptions.allowCredentials = res.allowCredentials_b64.map(e => {
                            return { id: Uint8Array.from(atob(e), c=>c.charCodeAt(0)), type: 'public-key'};
                        });
                    } else {
                        delete credOptions.allowCredentials;
                    }

                    return navigator.credentials.get({publicKey:credOptions}).then(
                        (cred: any) => {
                            const response = cred.response;
                            const cred_copy = {
                                id: cred.id,
                                signature_b64: btoa(String.fromCharCode(...new Uint8Array(response.signature))),
                                clientDataJSON_b64: btoa(String.fromCharCode(...new Uint8Array(response.clientDataJSON))),
                                authenticatorData_b64: btoa(String.fromCharCode(...new Uint8Array(response.authenticatorData))),
                                userHandle_b64: btoa(String.fromCharCode(...new Uint8Array(response.userHandle))),
                                extention_results: cred.getClientExtensionResults()
                            };

                            return this.removeFactor(factor, cred_copy, true).then(() => this.webauthn_remove_init = null);
                        },
                        (e)   => {
                            console.error('webauthn cred validation error:', e);
                            alert($localize`WebAuthn credential verification failed`); /* error */
                        }
                    );
                }

                this.refreshConfiguredFactors();
            }
        });
    }

    initFactor(factor: string, data?: any) {
        this.net.request(
            'open-ils.auth_mfa',
            'open-ils.auth_mfa.process.init',
            this.auth.token(), factor, data
        ).toPromise().then( res => {
            if (res) {
                console.debug(`factor ${factor} initialized for verification`);
                if (factor === 'email') {
                    this.email_otp_sent = true;
                } else if (factor === 'sms') {
                    this.sms_otp_sent = true;
                } else if (factor === 'webauthn') {
                    return this.validateFactor(factor,data);
                }
            }
        });
    }

    initFactorRemoval(factor: string, data?: any) {
        this.net.request(
            'open-ils.auth_mfa',
            'open-ils.auth_mfa.removal.init',
            this.auth.token(), factor, data
        ).toPromise().then( res => {
            if (res) {
                console.debug(`factor ${factor} initialized for removal`);
                if (factor === 'totp') {
                    this.totp_uri = '';
                    this.totp_uri_parts = {};
                } else if (factor === 'email') {
                    this.email_otp_sent = true;
                } else if (factor === 'sms') {
                    this.sms_otp_sent = true;
                } else if (factor === 'webauthn') {
                    this.webauthn_remove_init = res;
                }
            }
        });
    }

    validateFactor(factor: string, data?: any, forRemoval?: boolean) {
        return this.net.request(
            'open-ils.auth_mfa',
            'open-ils.auth_mfa.process.validate',
            this.auth.token(), factor, data
        ).toPromise().then( res => {
            if (res) {
                if (factor === 'webauthn') {
                    if (!Number(res.success)) {
                        console.error('WebAuthn validation failed:', res);
                        alert($localize`WebAuthn validation failed`);
                        return;
                    } else if (Number(res.success) > 0) {
                        return this.completeFactor(factor);
                    }

                    if (!isNaN(parseInt(res.timeout, 10))) {
                        res.timeout = parseInt(res.timeout, 10);
                    }

                    const credOptions = {
                        challenge: Uint8Array.from(atob(res.challenge_b64), c=>c.charCodeAt(0)),
                        timeout: res.timeout,
                        rpId: res.rpId,
                        allowCredentials: [],
                        userVerification: res.userVerification
                    };

                    if (res.allowCredentials_b64?.length) {
                        credOptions.allowCredentials = res.allowCredentials_b64.map(e => {
                            return { id: Uint8Array.from(atob(e), c=>c.charCodeAt(0)), type: 'public-key'};
                        });
                    } else {
                        delete credOptions.allowCredentials;
                    }

                    navigator.credentials.get({publicKey:credOptions}).then(
                        (cred: any) => {
                            const response = cred.response;
                            const cred_copy = {
                                id: cred.id,
                                signature_b64: btoa(String.fromCharCode(...new Uint8Array(response.signature))),
                                clientDataJSON_b64: btoa(String.fromCharCode(...new Uint8Array(response.clientDataJSON))),
                                authenticatorData_b64: btoa(String.fromCharCode(...new Uint8Array(response.authenticatorData))),
                                userHandle_b64: btoa(String.fromCharCode(...new Uint8Array(response.userHandle))),
                                extention_results: cred.getClientExtensionResults()
                            };

                            return this.validateFactor(factor, cred_copy);
                        },
                        (e)   => {
                            console.error('webauthn cred validation error:', e);
                            alert($localize`WebAuthn credential verification failed`); /* error */
                        }
                    );
                } else {
                    console.debug(`factor ${factor} verified`, res);
                    this.completeFactor(factor);
                }
            }
        });
    }

    completeFactor(factor: string, data?: any) {
        this.net.request(
            'open-ils.auth_mfa',
            'open-ils.auth_mfa.process.complete',
            this.auth.token(), factor, data
        ).toPromise().then( res => {
            if (res) {
                console.debug(`factor ${factor} verification completion confirmed`);

                // upgrade our local data after factor validation
                this.auth.provisionalTokenUpgraded();

                const url: string = this.routeTo || '/staff/splash';
                this.offline.refreshOfflineData()
                // Initial login clears cached org unit settings.
                    .then(_ => this.org.clearCachedSettings())
                    .then(_ => {

                        // Force reload of the app after a successful login.
                        // This allows the route resolver to re-run with a
                        // valid auth token and workstation.
                        window.location.href =
                        this.ngLocation.prepareExternalUrl(url);
                    });
            }
        });
    }

    upgradeSession(): Promise<any> {
        return this.net.request(
            'open-ils.auth_mfa',
            'open-ils.auth_mfa.provisional_upgrade',
            this.auth.token()
        ).toPromise().then(res => {
            if (res) {
                // upgrade our local data after factor validation
                this.auth.provisionalTokenUpgraded();

                const url: string = this.routeTo || '/staff/splash';
                this.offline.refreshOfflineData()
                // Initial login clears cached org unit settings.
                    .then(_ => this.org.clearCachedSettings())
                    .then(_ => {

                        // Force reload of the app after a successful login.
                        // This allows the route resolver to re-run with a
                        // valid auth token and workstation.
                        window.location.href =
                        this.ngLocation.prepareExternalUrl(url);
                    });
            }
        });
    }

    humanizeDuration(seconds: number): string {
        return moment.duration(seconds, 'seconds').humanize({ss: 0});
    }
}

