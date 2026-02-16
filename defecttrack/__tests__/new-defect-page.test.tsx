import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import NewDefectPage from '../app/defects/new/page';

describe('NewDefectPage', () => {
  it('renders the Log Defect heading', () => {
    render(<NewDefectPage />);
    expect(screen.getByText('Log Defect')).toBeDefined();
  });

  it('renders category dropdown with all 6 options', () => {
    render(<NewDefectPage />);
    const select = screen.getByLabelText('Category') as HTMLSelectElement;
    expect(select).toBeDefined();

    const options = Array.from(select.querySelectorAll('option'));
    const values = options.map((o) => o.value).filter(Boolean);
    expect(values).toEqual([
      'structural',
      'waterproofing',
      'electrical',
      'plumbing',
      'fire safety',
      'cosmetic',
    ]);
  });

  it('renders location input with placeholder', () => {
    render(<NewDefectPage />);
    const input = screen.getByLabelText('Location') as HTMLInputElement;
    expect(input).toBeDefined();
    expect(input.placeholder).toBeTruthy();
  });
});
