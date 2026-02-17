import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, act, waitFor } from '@testing-library/react';
import NewDefectPage from '../app/defects/new/page';

// Mock storage
vi.mock('../app/defects/storage', () => ({
  saveDefect: vi.fn(),
}));

import { saveDefect } from '../app/defects/storage';

// Mock crypto.randomUUID
vi.stubGlobal('crypto', { randomUUID: () => 'test-uuid-123' });

describe('Form submission', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  function fillRequiredFields() {
    fireEvent.change(screen.getByLabelText('Category'), { target: { value: 'structural' } });
    fireEvent.change(screen.getByLabelText('Location'), { target: { value: 'Level 2' } });
    fireEvent.click(screen.getByText('3'));
  }

  it('does not submit when required fields are missing', () => {
    render(<NewDefectPage />);
    fireEvent.click(screen.getByText('Submit Defect'));
    expect(saveDefect).not.toHaveBeenCalled();
  });

  it('saves defect to localStorage on valid submission', () => {
    render(<NewDefectPage />);
    fillRequiredFields();
    fireEvent.click(screen.getByText('Submit Defect'));
    expect(saveDefect).toHaveBeenCalledTimes(1);
    expect(saveDefect).toHaveBeenCalledWith(
      expect.objectContaining({
        category: 'structural',
        location: 'Level 2',
        severity: 3,
        id: 'test-uuid-123',
      })
    );
  });

  it('shows success toast after submission', () => {
    render(<NewDefectPage />);
    fillRequiredFields();
    fireEvent.click(screen.getByText('Submit Defect'));
    expect(screen.getByRole('alert').textContent).toContain('Defect logged successfully');
  });

  it('auto-dismisses toast after 3 seconds', () => {
    render(<NewDefectPage />);
    fillRequiredFields();
    fireEvent.click(screen.getByText('Submit Defect'));
    expect(screen.getByRole('alert')).toBeTruthy();
    act(() => {
      vi.advanceTimersByTime(3000);
    });
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('resets form after successful submission', () => {
    render(<NewDefectPage />);
    fillRequiredFields();
    fireEvent.change(screen.getByLabelText('Description'), { target: { value: 'cracked wall' } });
    fireEvent.click(screen.getByText('Submit Defect'));
    expect((screen.getByLabelText('Category') as HTMLSelectElement).value).toBe('');
    expect((screen.getByLabelText('Location') as HTMLInputElement).value).toBe('');
    expect((screen.getByLabelText('Description') as HTMLTextAreaElement).value).toBe('');
    // Severity buttons should all be unpressed
    const buttons = screen.queryAllByRole('button', { pressed: true });
    expect(buttons).toHaveLength(0);
  });
});
