import { Injectable } from '@angular/core';

export const BUCKET_CLASSES = ['biblio', 'user', 'callnumber', 'copy'] as const;
export type BucketClass = typeof BUCKET_CLASSES[number];

export interface BucketConfig {
  bucketFmClass: string;
  bucketItemFmClass: string;
  targetField: string;
  bucketItemTargetFmClass: string;
  storageKey: string;
  bucketFlagFmClass: string;
}

@Injectable({
  providedIn: 'root'
})
export class BucketConfigService {
  private config: Record<BucketClass, BucketConfig> = {
    biblio: {
      bucketFmClass: 'cbreb',
      bucketItemFmClass: 'cbrebi',
      targetField: 'target_biblio_record_entry',
      bucketItemTargetFmClass: 'bre',
      storageKey: 'eg.record_bucket',
      bucketFlagFmClass: 'cbrebuf'
    },
    user: {
      bucketFmClass: 'cub',
      bucketItemFmClass: 'cubi',
      targetField: 'target_user',
      bucketItemTargetFmClass: 'au',
      storageKey: 'eg.user_bucket',
      bucketFlagFmClass: 'cubuf'
    },
    callnumber: {
      bucketFmClass: 'ccnb',
      bucketItemFmClass: 'ccnbi',
      targetField: 'target_call_number',
      bucketItemTargetFmClass: 'acn',
      storageKey: 'eg.callnumber_bucket',
      bucketFlagFmClass: 'ccnbuf'
    },
    copy: {
      bucketFmClass: 'ccb',
      bucketItemFmClass: 'ccbi',
      targetField: 'target_copy',
      bucketItemTargetFmClass: 'acp',
      storageKey: 'eg.copy_bucket',
      bucketFlagFmClass: 'ccbuf'
    }
  };

  getBucketFmClass(bucketClass: BucketClass): string {
    return this.config[bucketClass].bucketFmClass;
  }

  getBucketItemFmClass(bucketClass: BucketClass): string {
    return this.config[bucketClass].bucketItemFmClass;
  }

  getTargetField(bucketClass: BucketClass): string {
    return this.config[bucketClass].targetField;
  }

  getBucketItemTargetFmClass(bucketClass: BucketClass): string {
    return this.config[bucketClass].bucketItemTargetFmClass;
  }

  getStorageKey(bucketClass: BucketClass): string {
    return this.config[bucketClass].storageKey;
  }

  getBucketFlagFmClass(bucketClass: BucketClass): string {
    return this.config[bucketClass].bucketFlagFmClass;
  }

  getConfig(bucketClass: BucketClass): BucketConfig {
    return this.config[bucketClass];
  }

  getAllBucketClasses(): readonly BucketClass[] {
    return BUCKET_CLASSES;
  }
}
