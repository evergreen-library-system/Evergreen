import {Component, OnInit} from '@angular/core';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {VandelayService} from './vandelay.service';

@Component({
    templateUrl: 'recent-imports.component.html'
})

export class RecentImportsComponent implements OnInit {

    trackers: IdlObject[];
    refreshInterval = 2000; // ms
    sinceDate: string;
    pollTimeout: any;

    constructor(
        private idl: IdlService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private vandelay: VandelayService
    ) {
        this.trackers = [];
    }

    ngOnInit() {
        // Default to showing all trackers created today.
        const d = new Date();
        d.setHours(0);
        d.setMinutes(0);
        d.setSeconds(0);
        this.sinceDate = d.toISOString();

        this.pollTrackers();
    }

    dateFilterChange(iso: string) {
        if (iso) {
            this.sinceDate = iso;
            if (this.pollTimeout) {
                clearTimeout(this.pollTimeout);
                this.pollTimeout = null;
            }
            this.trackers = [];
            this.pollTrackers();
        }
    }

    pollTrackers() {

        // Report on recent trackers for this workstation and for the
        // logged in user.  Always show active trackers regardless
        // of sinceDate.
        const query: any = {
            '-and': [
                {
                    '-or': [
                        {workstation: this.auth.user().wsid()},
                        {usr: this.auth.user().id()}
                    ],
                }, {
                    '-or': [
                        {create_time: {'>=': this.sinceDate}},
                        {state: 'active'}
                    ]
                }
            ]
        };

        this.pcrud.search('vst', query, {order_by: {vst: 'create_time'}})
        .subscribe(
            tracker => {
                // The screen flickers less if the tracker array is
                // updated inline instead of rebuilt every time.

                const existing =
                    this.trackers.filter(t => t.id() === tracker.id())[0];

                if (existing) {
                    existing.update_time(tracker.update_time());
                    existing.state(tracker.state());
                    existing.total_actions(tracker.total_actions());
                    existing.actions_performed(tracker.actions_performed());
                } else {

                    // Only show the import tracker when both an enqueue
                    // and import tracker exist for a given session.
                    const sameSes = this.trackers.filter(
                        t => t.session_key() === tracker.session_key())[0];

                    if (sameSes) {
                        if (sameSes.action_type() === 'enqueue') {
                            // Remove the enqueueu tracker

                            for (let idx = 0; idx < this.trackers.length; idx++) {
                                const trkr = this.trackers[idx];
                                if (trkr.id() === sameSes.id()) {
                                    console.debug(
                                        `removing tracker ${trkr.id()} from the list`);
                                    this.trackers.splice(idx, 1);
                                    break;
                                }
                            }
                       } else if (sameSes.action_type() === 'import') {
                            // Avoid adding the new enqueue tracker
                            return;
                        }
                    }

                    console.debug(`adding tracker ${tracker.id()} to list`);

                    this.trackers.unshift(tracker);
                    this.fleshTrackerQueue(tracker);
                }
            },
            err => {},
            ()  => {
                const active =
                    this.trackers.filter(t => t.state() === 'active');

                // Continue updating the display with updated tracker
                // data as long as we have any active trackers.
                if (active.length > 0) {
                    this.pollTimeout = setTimeout(
                        () => this.pollTrackers(), this.refreshInterval);
                } else {
                    this.pollTimeout = null;
                }
            }
        );
    }

    fleshTrackerQueue(tracker: IdlObject) {
        const qClass = tracker.record_type() === 'bib' ? 'vbq' : 'vaq';
        this.pcrud.retrieve(qClass, tracker.queue())
        .subscribe(queue => tracker.queue(queue));
    }

}
