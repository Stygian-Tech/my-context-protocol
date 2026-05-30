/**
 * English singular/plural word choice from a numeric count.
 * Uses absolute value (e.g. -1 reads as singular).
 */
export function pluralEn(count: number, singular: string, plural: string): string {
  return Math.abs(count) === 1 ? singular : plural;
}
