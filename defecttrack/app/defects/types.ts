export type DefectCategory =
  | 'structural'
  | 'waterproofing'
  | 'electrical'
  | 'plumbing'
  | 'fire safety'
  | 'cosmetic';

export type SeverityRating = 1 | 2 | 3 | 4 | 5;

export interface Defect {
  id: string;
  photo: string | null;
  category: DefectCategory;
  location: string;
  severity: SeverityRating;
  description: string;
  createdAt: string;
}
