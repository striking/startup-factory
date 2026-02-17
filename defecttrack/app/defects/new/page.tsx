'use client';

import { useState } from 'react';

const CATEGORIES = [
  'structural',
  'waterproofing',
  'electrical',
  'plumbing',
  'fire safety',
  'cosmetic',
] as const;

export default function NewDefectPage() {
  const [category, setCategory] = useState('');
  const [location, setLocation] = useState('');

  return (
    <div className="min-h-screen p-4">
      <div className="mx-auto max-w-lg">
        <h1 className="text-2xl font-bold mb-6">Log Defect</h1>
        <form className="space-y-4">
          <div>
            <label htmlFor="category" className="block text-sm font-medium mb-1">
              Category
            </label>
            <select
              id="category"
              value={category}
              onChange={(e) => setCategory(e.target.value)}
              className="w-full border rounded-md p-2"
            >
              <option value="">Select category</option>
              {CATEGORIES.map((cat) => (
                <option key={cat} value={cat}>
                  {cat}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor="location" className="block text-sm font-medium mb-1">
              Location
            </label>
            <input
              id="location"
              type="text"
              value={location}
              onChange={(e) => setLocation(e.target.value)}
              placeholder="e.g. Level 3, Unit 5, Bathroom"
              className="w-full border rounded-md p-2"
            />
          </div>
        </form>
      </div>
    </div>
  );
}
