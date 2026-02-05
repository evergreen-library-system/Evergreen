export enum Cardinality {
    Low = 'Low',
    High = 'High',
    Unbounded = 'Unbounded',
    Unknown = 'Unknown'
}

// Given data about an idl class, here is our best guess as to
// the cardinality.
export function cardinalityGuess(idlClass: any): Cardinality {
    switch(idlClass.cardinality) {
        case 'low':
            return Cardinality.Low;
        case 'high':
            return Cardinality.High;
        case 'unbounded':
            return Cardinality.Unbounded;
        default: {
            // if cardinality wasn't set at all, let's make extra sure this isn't a log or history table
            const table = idlClass.table;
            if (table?.endsWith('_log') || table?.endsWith('_history')) {
                return Cardinality.Unbounded;
            }
            return Cardinality.Unknown;
        }
    }
}
