import { Component, Input, OnInit, inject, Signal, signal, WritableSignal, computed } from '@angular/core';
import { StaffCommonModule } from '@eg/staff/common.module';
import { HoldGroupListComponent, tabChange } from './hold-group-list/hold-group-list.component';
import { HoldGroupUsersComponent } from './hold-group-users/hold-group-users.component';
import { IdlObject } from '@eg/core/idl.service';
import { ActivatedRoute, ParamMap, Router } from '@angular/router';
import { HoldGroupEventsComponent } from './hold-group-events/hold-group-events.component';
import { HoldGroupsService } from './hold-groups.service';
import { of, switchMap, tap } from 'rxjs';

@Component({
    selector: 'eg-hold-groups',
    standalone: true,
    imports: [StaffCommonModule, HoldGroupListComponent, HoldGroupUsersComponent, HoldGroupEventsComponent],
    templateUrl: './hold-groups.component.html'
})
export class HoldGroupsComponent implements OnInit {

    protected hg = inject(HoldGroupsService);
    private route = inject(ActivatedRoute);
    private router = inject(Router);

    selectedUserBucket: WritableSignal<IdlObject | null> = signal(null);
    @Input() selectedUserBucketId: number | null = null;
    @Input() activeTab: 'list' | 'users' | 'events' = 'list';

    protected eventCount: Signal<number> = computed(() => {
        return this.hg.userBucketEventCount.value();
    });


    ngOnInit(): void {
        this.route.firstChild?.paramMap.pipe(
            tap((params: ParamMap) => {
                const tab = params.get('tab');
                if (tab === 'list' || tab === 'users' || tab === 'events') {
                    this.activeTab = tab;
                } else {
                    if (tab !== null) {
                        console.warn(`Invalid tab ${tab}, defaulting to list`);
                    }
                    this.activeTab = 'list';
                }
            }),
            switchMap((params: ParamMap) => {
                const id = params.get('id');
                if (id) {
                    return this.hg.fetchUserBucket(+id);
                }
                return of(null);
            })
        ).subscribe();
    }

    tabAndBucketChange(change: tabChange) {

        this.hg.fetchUserBucket(change.id).subscribe({// Changes id and userBucket as side effect
            complete: () => {
                this.router.navigate([ change.tab, change.id], { relativeTo: this.route});
                this.activeTab = change.tab;
            }

        });


    }

    tabChange(tab: 'list' | 'users' | 'events') {
        this.activeTab = tab;
        this.router.navigate([ tab, this.hg.userBucketId()], { relativeTo: this.route});
    }

}
