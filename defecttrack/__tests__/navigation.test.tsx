import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import React from 'react';

// Mock next/font/google
vi.mock('next/font/google', () => ({
  Geist: () => ({ className: 'mock-font' }),
}));

// Mock @vercel/analytics/react
vi.mock('@vercel/analytics/react', () => ({
  Analytics: () => null,
}));

// Mock next/link
vi.mock('next/link', () => ({
  default: ({ href, children, ...props }: any) => <a href={href} {...props}>{children}</a>,
}));

import Page from '../app/page';
import NewDefectPage from '../app/defects/new/page';

describe('Navigation', () => {
  it('landing page has a link to /defects/new', () => {
    render(<Page />);
    const link = screen.getByRole('link', { name: /log defect/i });
    expect(link).toBeDefined();
    expect(link.getAttribute('href')).toBe('/defects/new');
  });

  it('defect form page has a back link to /', () => {
    render(<NewDefectPage />);
    const link = screen.getByRole('link', { name: /back to home/i });
    expect(link).toBeDefined();
    expect(link.getAttribute('href')).toBe('/');
  });
});
