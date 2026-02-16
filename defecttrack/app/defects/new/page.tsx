'use client';

import { useState, type ChangeEvent } from 'react';
import type { SeverityRating } from '../types';

const CATEGORIES = [
  'structural',
  'waterproofing',
  'electrical',
  'plumbing',
  'fire safety',
  'cosmetic',
] as const;

const SEVERITY_LEVELS: SeverityRating[] = [1, 2, 3, 4, 5];

export default function NewDefectPage() {
  const [category, setCategory] = useState('');
  const [location, setLocation] = useState('');
  const [severity, setSeverity] = useState<SeverityRating | null>(null);
  const [description, setDescription] = useState('');
  const [photo, setPhoto] = useState<string | null>(null);

  function handlePhotoChange(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onloadend = () => {
      setPhoto(reader.result as string);
    };
    reader.readAsDataURL(file);
  }

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
          <div>
            <span className="block text-sm font-medium mb-1">Severity</span>
            <div className="flex gap-2" role="group" aria-label="Severity rating">
              {SEVERITY_LEVELS.map((level) => (
                <button
                  key={level}
                  type="button"
                  onClick={() => setSeverity(level)}
                  className={`w-10 h-10 rounded-md border font-medium ${
                    severity === level
                      ? 'bg-blue-600 text-white border-blue-600'
                      : 'bg-white text-gray-700 border-gray-300'
                  }`}
                  aria-pressed={severity === level}
                >
                  {level}
                </button>
              ))}
            </div>
          </div>
          <div>
            <label htmlFor="description" className="block text-sm font-medium mb-1">
              Description
            </label>
            <textarea
              id="description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Describe the defect..."
              rows={4}
              className="w-full border rounded-md p-2"
            />
          </div>
          <div>
            <label htmlFor="photo" className="block text-sm font-medium mb-1">
              Photo
            </label>
            <input
              id="photo"
              type="file"
              accept="image/*"
              onChange={handlePhotoChange}
              className="w-full"
            />
            {photo && (
              <img
                src={photo}
                alt="Defect preview"
                className="mt-2 w-32 h-32 object-cover rounded-md"
              />
            )}
          </div>
        </form>
      </div>
    </div>
  );
}
