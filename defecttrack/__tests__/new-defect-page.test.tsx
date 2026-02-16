import { describe, it, expect } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
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

  it('renders 5 severity buttons (1-5)', () => {
    render(<NewDefectPage />);
    const group = screen.getByRole('group', { name: /severity/i });
    const buttons = group.querySelectorAll('button');
    expect(buttons.length).toBe(5);
    expect(Array.from(buttons).map((b) => b.textContent)).toEqual(['1', '2', '3', '4', '5']);
  });

  it('highlights selected severity button', () => {
    render(<NewDefectPage />);
    const button3 = screen.getByRole('button', { name: '3' });
    expect(button3.getAttribute('aria-pressed')).toBe('false');
    fireEvent.click(button3);
    expect(button3.getAttribute('aria-pressed')).toBe('true');
    expect(button3.className).toContain('bg-blue-600');
  });

  it('renders description textarea', () => {
    render(<NewDefectPage />);
    const textarea = screen.getByLabelText('Description') as HTMLTextAreaElement;
    expect(textarea).toBeDefined();
    expect(textarea.tagName).toBe('TEXTAREA');
  });

  it('renders photo upload input accepting images', () => {
    render(<NewDefectPage />);
    const input = screen.getByLabelText('Photo') as HTMLInputElement;
    expect(input).toBeDefined();
    expect(input.type).toBe('file');
    expect(input.accept).toBe('image/*');
  });
});
