/**
  * Simple wrapper class for our external MARC21.Record JS library.
  */

declare var MARC21;

// MARC breaker delimiter
const DELIMITER = '$';

export class MarcRecord {

    id: number; // Database ID when known.
    deleted: boolean;
    record: any; // MARC21.Record object
    breakerText: string;

    constructor(xml: string) {
        this.record = new MARC21.Record({marcxml: xml, delimiter: DELIMITER});
        this.breakerText = this.record.toBreaker();
    }

    toXml(): string {
        return this.record.toXmlString();
    }

    toBreaker(): string {
        return this.record.toBreaker();
    }

    absorbBreakerChanges() {
        this.record = new MARC21.Record(
            {marcbreaker: this.breakerText, delimiter: DELIMITER});
    }
}

