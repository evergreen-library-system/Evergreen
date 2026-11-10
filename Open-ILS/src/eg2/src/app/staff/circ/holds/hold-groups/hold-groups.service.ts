import { inject, Injectable, OnInit,Signal, WritableSignal, signal, computed, Resource, resource } from '@angular/core';
import { firstValueFrom, Observable, tap, of } from 'rxjs';
import { IdlObject } from '@eg/core/idl.service';
import { PcrudService } from '@eg/core/pcrud.service';

@Injectable({
    providedIn: 'root'
})
export class HoldGroupsService {
    private pcrud: PcrudService = inject(PcrudService);

    public userBucket: WritableSignal<IdlObject | null> = signal(null);
    public userBucketId: Signal<number | null> = computed(() => this.userBucket()?.id());
    public userBucketEventCount: Resource<number> = resource({
        params: () => ({bucket: this.userBucket()}),
        loader: ({params}) => {
            const id = params.bucket?.id();
            if (!id) {
                return Promise.resolve(0);
            }
            return firstValueFrom(this.pcrud.search('abhe', {bucket: id}, {}, {count_only: true}));
        }
    });

    fetchUserBucket(bucketId?: number | null, reload = false) : Observable<IdlObject | null> {
        if (bucketId === null) {
            return of();
        }

        if (!bucketId) {
            return this.fetchUserBucket(this.userBucketId());
        }

        if (!reload && this.userBucket() !== null && bucketId === this.userBucketId()) {
            return of(this.userBucket());
        }

        const pcrudOps = {
            flesh: 3,
            flesh_fields: {
                cub: ['items', 'owner', 'owning_lib'],
                cubi: ['target_user'],
                au: ['card'] // Needed for displaying barcode in results of placing a hold event
            }
        };

        return this.pcrud.retrieve('cub', bucketId, pcrudOps, {fleshSelectors: true})
            .pipe(
                tap((bucket: IdlObject) => this.userBucket.set(bucket))
            );
    }

    reloadUserBucket() {
        this.fetchUserBucket(this.userBucketId(), true).subscribe();
    }

}
