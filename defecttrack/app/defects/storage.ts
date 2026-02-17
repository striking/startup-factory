import { Defect } from './types';

const STORAGE_KEY = 'defecttrack_defects';

export function getDefects(): Defect[] {
  if (typeof window === 'undefined') return [];
  const data = localStorage.getItem(STORAGE_KEY);
  if (!data) return [];
  try {
    return JSON.parse(data) as Defect[];
  } catch {
    return [];
  }
}

export function saveDefect(defect: Defect): void {
  const defects = getDefects();
  defects.push(defect);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(defects));
}
